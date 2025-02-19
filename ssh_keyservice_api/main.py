#!/usr/bin/env python3
import os
import secrets
import hashlib
import logging

import uvicorn

import valkey as redis

from fastapi import FastAPI, Security, Depends, HTTPException
from fastapi.responses import PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi_azure_auth import SingleTenantAzureAuthorizationCodeBearer
from fastapi_azure_auth.user import User
from fastapi.security.api_key import APIKeyHeader

from contextlib import asynccontextmanager
from typing import AsyncGenerator
from datetime import datetime

from cachetools import TTLCache

from models import UserModel, SSHKeyPutRequest, SSHKeyDeleteRequest

from dotenv import load_dotenv

#from azure.identity import DefaultAzureCredential
#from azure.keyvault.secrets import SecretClient
# Configure Azure Key Vault
#KEY_VAULT_URL = os.getenv("AZURE_KEY_VAULT_URL", "https://your-keyvault-name.vault.azure.net")
#credential = DefaultAzureCredential()
#client = SecretClient(vault_url=KEY_VAULT_URL, credential=credential)
#
#def get_secret(secret_name: str) -> str:
#    try:
#        return client.get_secret(secret_name).value
#    except Exception as e:
#        raise HTTPException(status_code=500, detail=f"Error retrieving secret {secret_name}: {str(e)}")

# Load secrets from .env file
def get_secret(secret_name: str) -> str:
    try:
        return os.getenv(secret_name)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving secret {secret_name}: {str(e)}")

load_dotenv()

# Load secrets
VALID_API_KEYS = get_secret("VALID_API_KEYS")
OPENAPI_CLIENT_ID = get_secret("OPENAPI_CLIENT_ID")
TRUSTED_CORS_ORIGINS = get_secret("TRUSTED_CORS_ORIGINS").split(',')
APP_CLIENT_ID = get_secret("APP_CLIENT_ID")
TENANT_ID = get_secret("TENANT_ID")
DB_HOST = get_secret("DB_HOST")
SCOPE = { f'api://{APP_CLIENT_ID}/user.read.profile' : 'user.read.profile' }

# Cache API keys for 10 minutes (600 seconds)
api_key_cache = TTLCache(maxsize=1, ttl=600)

api_key_header_auth = APIKeyHeader(name="x-api-key", auto_error=True)

def get_api_keys():
    """Retrieve API keys with caching to reduce Key Vault requests."""
    if "api_keys" not in api_key_cache:
        api_key_cache["api_keys"] = get_secret("VALID_API_KEYS").split(',')
    return api_key_cache["api_keys"]

async def api_key_auth(api_key_header: str = Security(api_key_header_auth)):
    valid_api_keys = get_api_keys()
    if not any(secrets.compare_digest(api_key_header, key.strip()) for key in valid_api_keys):
        raise HTTPException(status_code=401, detail="Invalid API Key")

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("SSHKeyAPI")

# Redis connection
redis_client = redis.Redis(host=DB_HOST, port=6379, decode_responses=True)

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
        'clientId': OPENAPI_CLIENT_ID,
    },
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[str(origin) for origin in TRUSTED_CORS_ORIGINS],
    allow_credentials=True,
    allow_methods=["GET", "PUT", "POST", "DELETE"],
    allow_headers=['*'], # TODO: This needs to be restricted to the required headers
)

azure_scheme = SingleTenantAzureAuthorizationCodeBearer(
    app_client_id=APP_CLIENT_ID,
    tenant_id=TENANT_ID,
    scopes=SCOPE,
)

def generate_user_key(email: str) -> str:
    return f"user:{hashlib.sha256(email.encode()).hexdigest()}"

@app.get("/api/v1/users/me", dependencies=[Security(azure_scheme)])
async def get_user_info(user: User = Depends(azure_scheme)) -> UserModel:
    """Retrieve SSH keys for authenticated user."""
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_key = generate_user_key(email)
    stored_keys = redis_client.hgetall(f"{user_key}:keys")
    # Parse stored data into a structured format
    ssh_keys = {
        key: {"comment": value.split("|")[0], "timestamp": value.split("|")[1]} 
        for key, value in stored_keys.items()
    }
    return {"email": email, "ssh_keys": ssh_keys}

@app.put("/api/v1/users/me/keys", dependencies=[Security(azure_scheme)])
async def add_ssh_key(request: SSHKeyPutRequest, user: User = Depends(azure_scheme)) -> dict[str, str]:
    """Add an SSH key for the authenticated user."""
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_key = generate_user_key(email)
    timestamp = datetime.utcnow().isoformat()
    redis_client.hset(f"{user_key}:keys", request.ssh_key, f"{request.comment}|{timestamp}")
    return {"message": "SSH key added."}

@app.delete("/api/v1/users/me/keys", dependencies=[Security(azure_scheme)])
async def delete_ssh_key(request: SSHKeyDeleteRequest, user: User = Depends(azure_scheme)) -> dict[str, str]:
    """Delete a specific SSH key for the authenticated user."""
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_key = generate_user_key(email)
    if not redis_client.hexists(f"{user_key}:keys", request.ssh_key):
        raise HTTPException(status_code=404, detail="SSH key not found.")
    redis_client.hdel(f"{user_key}:keys", request.ssh_key)
    return {"message": "SSH key deleted."}

@app.get("/api/v1/users/{email}/keys", response_class=PlainTextResponse, dependencies=[Security(api_key_auth)])
async def get_ssh_keys_by_mail(email: str) -> str:
    """Get registered SSH keys for a given email."""
    user_key = generate_user_key(email)
    ssh_keys = redis_client.hgetall(f"{user_key}:keys")
    return "\n".join(ssh_keys.keys()) if ssh_keys else ""

if __name__ == '__main__':
    uvicorn.run('main:app', reload=True)
