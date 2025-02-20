#!/usr/bin/env python3
import os
import secrets
import hashlib
import logging

import uvicorn

from fastapi import FastAPI, Security, Depends, HTTPException
from fastapi.responses import PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi_azure_auth import SingleTenantAzureAuthorizationCodeBearer
from fastapi_azure_auth.user import User
from fastapi.security.api_key import APIKeyHeader

from contextlib import asynccontextmanager
from typing import AsyncGenerator
from datetime import datetime

from sqlmodel import Session, select

from cachetools import TTLCache

from models import UserModel, SSHKeyPutRequest, SSHKeyDeleteRequest, engine, SSHKey

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.monitor.opentelemetry import configure_azure_monitor

# Setup logger and Azure Monitor:
logger = logging.getLogger("ssh_keyservice_api")
logger.setLevel(logging.INFO)
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    configure_azure_monitor()

# Configure Azure Key Vault
KEY_VAULT_URL = os.getenv("AZURE_KEY_VAULT_URL", "https://your-keyvault-name.vault.azure.net")
credential = DefaultAzureCredential()
client = SecretClient(vault_url=KEY_VAULT_URL, credential=credential)

def get_secret(secret_name: str) -> str:
    try:
        return client.get_secret(secret_name).value
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving secret {secret_name}: {str(e)}")

# Load secrets
VALID_API_KEYS = get_secret("VALID-API-KEYS")
TRUSTED_CORS_ORIGINS = get_secret("TRUSTED-CORS-ORIGINS").split(',')
APP_CLIENT_ID = get_secret("APP-CLIENT-ID")
TENANT_ID = get_secret("TENANT-ID")
SCOPE = { f'api://{APP_CLIENT_ID}/user.read.profile' : 'user.read.profile' }

# Dependency to get the database session
def get_db_session():
    with Session(engine) as session:
        yield session

# Cache API keys for 10 minutes (600 seconds)
api_key_cache = TTLCache(maxsize=1, ttl=600)
api_key_header_auth = APIKeyHeader(name="x-api-key", auto_error=True)

def get_api_keys():
    """Retrieve API keys with caching to reduce Key Vault requests."""
    if "api_keys" not in api_key_cache:
        api_key_cache["api_keys"] = get_secret("VALID-API-KEYS").split(',')
    return api_key_cache["api_keys"]

async def api_key_auth(api_key_header: str = Security(api_key_header_auth)):
    valid_api_keys = get_api_keys()
    if not any(secrets.compare_digest(api_key_header, key.strip()) for key in valid_api_keys):
        raise HTTPException(status_code=401, detail="Invalid API Key")

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
        'clientId': APP_CLIENT_ID,
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

def generate_user_hash(email: str) -> str:
    return f"{hashlib.sha256(email.encode()).hexdigest()}"

@app.get("/api/v1/users/me", dependencies=[Security(azure_scheme)])
async def get_user_info(user: User = Depends(azure_scheme), session: Session = Depends(get_db_session)) -> UserModel:
    """Retrieve SSH keys for authenticated user."""
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_hash = generate_user_hash(email)

    # Fetch SSH keys from the database
    results = session.exec(select(SSHKey).filter(SSHKey.user_hash == user_hash)).all()

    ssh_keys = {}
    for key in results:
        ssh_keys.update({key.ssh_key: {"comment": key.comment, "timestamp": key.timestamp}})

    return {"email": email, "ssh_keys": ssh_keys}

@app.put("/api/v1/users/me/keys", dependencies=[Security(azure_scheme)])
async def add_ssh_key( request: SSHKeyPutRequest, user: User = Depends(azure_scheme), session: Session = Depends(get_db_session)) -> dict[str, str]:
    """Add an SSH key for the authenticated user."""
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_hash = generate_user_hash(email)
    timestamp = datetime.utcnow().isoformat()

    ssh_key = SSHKey()
    ssh_key.ssh_key = request.ssh_key
    ssh_key.user_hash = user_hash
    ssh_key.comment = request.comment
    ssh_key.timestamp = timestamp
    session.add(ssh_key)
    session.commit()
    session.refresh(ssh_key)

    return {"message": "SSH key added."}

@app.delete("/api/v1/users/me/keys", dependencies=[Security(azure_scheme)])
async def delete_ssh_key(request: SSHKeyDeleteRequest, user: User = Depends(azure_scheme), session: Session = Depends(get_db_session)) -> dict[str, str]:
    """Delete a specific SSH key for the authenticated user."""
    email = user.claims.get("preferred_username") or user.claims.get("email")
    user_hash = generate_user_hash(email)

    ssh_key = session.exec(select(SSHKey).filter(SSHKey.user_hash == user_hash, SSHKey.ssh_key == request.ssh_key)).first()
    if not ssh_key:
        raise HTTPException(status_code=404, detail="SSH key not found.")
    session.delete(ssh_key)
    session.commit()

    return {"message": "SSH key deleted."}

@app.get("/api/v1/users/{email}/keys", response_class=PlainTextResponse, dependencies=[Security(api_key_auth)])
async def get_ssh_keys_by_mail(email: str, session: Session = Depends(get_db_session)) -> str:
    """Get registered SSH keys for a given email."""
    user_hash = generate_user_hash(email)

    results = session.exec(select(SSHKey).filter(SSHKey.user_hash == user_hash)).all()

    ssh_keys = {}
    for key in results:
        ssh_keys.update({key.ssh_key: {"comment": key.comment, "timestamp": key.timestamp}})

    return "\n".join(ssh_keys.keys()) if ssh_keys else ""

if __name__ == '__main__':
    uvicorn.run('main:app', reload=True)
