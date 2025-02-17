import uvicorn
from fastapi import FastAPI, Security, Depends
from fastapi import HTTPException
from fastapi.responses import PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi_azure_auth import SingleTenantAzureAuthorizationCodeBearer
from fastapi_azure_auth.user import User
from fastapi.security.api_key import APIKeyHeader
from pydantic import AnyHttpUrl, computed_field
from pydantic_settings import BaseSettings
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from datetime import datetime
import logging
import valkey as redis

from models import SSHKeyPutRequest, SSHKeyDeleteRequest

api_key_header_auth = APIKeyHeader(name="x-api-key", auto_error=True)

async def api_key_auth(api_key_header: str = Security(api_key_header_auth)):
    if api_key_header != settings.API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("SSHKeyAPI")

# Redis connection
redis_client = redis.Redis(host="localhost", port=6379, decode_responses=True)

class Settings(BaseSettings):
    BACKEND_CORS_ORIGINS: list[str | AnyHttpUrl] = ['http://localhost:8000']
    OPENAPI_CLIENT_ID: str = ""
    APP_CLIENT_ID: str = ""
    TENANT_ID: str = ""
    CLIENT_SECRET: str = ""
    SCOPE_DESCRIPTION: str = "user.read.profile"
    API_KEY: str = ""

    @computed_field
    @property
    def SCOPE_NAME(self) -> str:
        return f'api://{self.APP_CLIENT_ID}/{self.SCOPE_DESCRIPTION}'

    @computed_field
    @property
    def SCOPES(self) -> dict:
        return {
            self.SCOPE_NAME: self.SCOPE_DESCRIPTION,
        }

    class Config:
        env_file = '.env'
        env_file_encoding = 'utf-8'
        case_sensitive = True

settings = Settings()

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """
    Load OpenID config on startup.
    """
    await azure_scheme.openid_config.load_config()
    yield

app = FastAPI(
    swagger_ui_oauth2_redirect_url='/oauth2-redirect',
    swagger_ui_init_oauth={
        'usePkceWithAuthorizationCodeGrant': True,
        'clientId': settings.OPENAPI_CLIENT_ID,
    },
)

if settings.BACKEND_CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[str(origin) for origin in settings.BACKEND_CORS_ORIGINS],
        allow_credentials=True,
        allow_methods=['*'],
        allow_headers=['*'],
    )

azure_scheme = SingleTenantAzureAuthorizationCodeBearer(
    app_client_id=settings.APP_CLIENT_ID,
    tenant_id=settings.TENANT_ID,
    scopes=settings.SCOPES,
)

def add_user(email):
    """
    Add a new user with an auto-incremented UID, email, and metadata.
    """
    # Check if the email is already registered
    if redis_client.exists(f"email:{email}"):
        raise ValueError("Email already exists.")

    # Generate a new UID
    uid = redis_client.incr("user:id_counter")

    # Create user metadata
    user_key = f"user:{uid}"
    redis_client.hset(user_key, mapping={
        "email": email,
        "created_at": datetime.utcnow().isoformat()
    })

    # Map email to UID
    redis_client.set(f"email:{email}", uid)

    print(f"User created: UID={uid}, Email={email}")
    return uid

def list_users():
    return redis_client.smembers("users")

@app.get("/", dependencies=[Security(azure_scheme)])
async def root():
    return {"message": "Hello World"}

# TODO: Define output schema/validator
@app.get("/api/v1/users/me", dependencies=[Security(azure_scheme)])
async def hello_user(user: User = Depends(azure_scheme)):
    """
    Retrieve user metadata and SSH keys using email.
    """
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_id = redis_client.get(f"email:{email}")
    if not user_id:
        user_id = add_user(email)

    print(f"User {email} has ID {user_id}")

    user_key = f"user:{user_id}"
    user_data = redis_client.hgetall(user_key)
    user_keys_key = f"user:{user_id}:keys"
    ssh_keys = redis_client.hgetall(user_keys_key)

    return {"id": user_id, "user_data": user_data, "ssh_keys": ssh_keys}

@app.get("/api/v1/users/me/id", dependencies=[Security(azure_scheme)])
async def current_user_id(user: User = Depends(azure_scheme)) -> dict[str, int]:
    """
    Retrieve user id using email.
    """
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_id = redis_client.get(f"email:{email}")
    if not user_id:
        user_id = add_user(email)

    return {"id": user_id}

# TODO: Define output schema/validator
@app.get("/api/v1/users/{user_id}", dependencies=[Security(azure_scheme)])
async def get_ssh_keys(user_id: int, ssh_key: str | None = None, user: User = Depends(azure_scheme)):# -> dict[str, str]:
    email = user.claims.get("preferred_username") or user.claims.get("email")
    mail = redis_client.hget(f"user:{user_id}", "email")
    if email != mail:
        raise HTTPException(status_code=401, detail=f"User {email} is not authorized to access user {user_id}'s data.")

    if ssh_key:
        ssh_key_comment = redis_client.hget(f"user:{user_id}:keys", ssh_key)
        if not ssh_key_comment:
            raise HTTPException(status_code=404, detail=f"SSH key not found for user {user_id}: {ssh_key}")
        return {ssh_key: ssh_key_comment}

    ssh_keys = redis_client.hgetall(f"user:{user_id}:keys")
    return ssh_keys

@app.post("/api/v1/users", dependencies=[Security(azure_scheme)])
async def add_user_entry(user: User = Depends(azure_scheme)):
    """
    Add a new user entry.
    """
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_id = redis_client.get(f"email:{email}")
    if not user_id:
        user_id = add_user(email)

@app.put("/api/v1/users/{user_id}", dependencies=[Security(azure_scheme)])
async def add_ssh_key(user_id: int, request: SSHKeyPutRequest, user: User = Depends(azure_scheme)):
    """
    Add an SSH key and comment for a user.
    """
    email = user.claims.get("preferred_username") or user.claims.get("email")
    mail = redis_client.hget(f"user:{user_id}", "email")
    if email != mail:
        raise HTTPException(status_code=401, detail=f"User {email} is not authorized to access user {user_id}'s data.")

    redis_client.hset(f"user:{user_id}:keys", request.ssh_key, request.comment)
    print(f"Added SSH key for user {user_id}: {request.ssh_key} -> {request.comment}")


@app.delete("/api/v1/users/{user_id}", dependencies=[Security(azure_scheme)])
async def delete_ssh_key(user_id: int, request: SSHKeyDeleteRequest, user: User = Depends(azure_scheme)):
    """
    Delete a specific SSH key for a user.
    """
    email = user.claims.get("preferred_username") or user.claims.get("email")
    mail = redis_client.hget(f"user:{user_id}", "email")
    if email != mail:
        raise HTTPException(status_code=401, detail=f"User {email} is not authorized to access user {user_id}'s data.")

    user_keys_key = f"user:{user_id}:keys"
    if redis_client.hexists(user_keys_key, request.ssh_key):
        redis_client.hdel(user_keys_key, request.ssh_key)
    else:
        raise HTTPException(status_code=404, detail=f"SSH key not found for user {user_id}: {request.ssh_key}")

@app.get("/api/v1/keys/by-email/{email}", response_class=PlainTextResponse, dependencies=[Security(api_key_auth)])
async def get_ssh_keys_by_mail(email: str):
    """
    Get all registered keys for a given mail address
    """
    user_id = redis_client.get(f"email:{email}")
    if not user_id:
        return ""
    user_keys_key = f"user:{user_id}:keys"
    ssh_keys = redis_client.hgetall(user_keys_key)

    # Return keys as a plain text response
    return "\n".join([f"{key}" for key, comment in ssh_keys.items()])

if __name__ == '__main__':
    uvicorn.run('main:app', reload=True)
