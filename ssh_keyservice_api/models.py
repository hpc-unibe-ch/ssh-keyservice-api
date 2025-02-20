import logging
import os
import typing
from urllib.parse import quote_plus

from dotenv import load_dotenv
from sqlmodel import Field, SQLModel, create_engine

from pydantic import BaseModel

logger = logging.getLogger("app")
logger.setLevel(logging.INFO)

sql_url = ""
if os.getenv("WEBSITE_HOSTNAME"):
    logger.info("Connecting to Azure PostgreSQL Flexible server based on AZURE_POSTGRESQL_CONNECTIONSTRING...")
    env_connection_string = os.getenv("AZURE_POSTGRESQL_CONNECTIONSTRING")
    if env_connection_string is None:
        logger.info("Missing environment variable AZURE_POSTGRESQL_CONNECTIONSTRING")
    else:
        # Parse the connection string
        details = dict(item.split('=') for item in env_connection_string.split())

        # Properly format the URL for SQLAlchemy
        sql_url = (
            f"postgresql://{quote_plus(details['user'])}:{quote_plus(details['password'])}"
            f"@{details['host']}:{details['port']}/{details['dbname']}?sslmode={details['sslmode']}"
        )

else:
    logger.info("Connecting to local PostgreSQL server based on .env file...")
    load_dotenv()
    POSTGRES_USERNAME = os.environ.get("DBUSER")
    POSTGRES_PASSWORD = os.environ.get("DBPASS")
    POSTGRES_HOST = os.environ.get("DBHOST")
    POSTGRES_DATABASE = os.environ.get("DBNAME")
    POSTGRES_PORT = os.environ.get("DBPORT", 5432)

    sql_url = f"postgresql://{POSTGRES_USERNAME}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DATABASE}"

engine = create_engine(sql_url)

def create_db_and_tables():
    return SQLModel.metadata.create_all(engine)

class UserModel(BaseModel):
    email: str
    ssh_keys: dict[str, dict[str, str]] = {}

class SSHKeyPutRequest(BaseModel):
    ssh_key: str
    comment: str

class SSHKeyDeleteRequest(BaseModel):
    ssh_key: str

class SSHKey(SQLModel, table=True):
    ssh_key: typing.Optional[str] = Field(default=None, primary_key=True)
    user_hash: str = Field(max_length=250)
    comment: str = Field(max_length=50)
    timestamp: str = Field(max_length=50)

    def __str__(self):
        return f"{self.ssh_key}"
