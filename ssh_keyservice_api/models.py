from pydantic import BaseModel

class UserModel(BaseModel):
    email: str
    ssh_keys: dict[str, dict[str, str]]

class SSHKeyPutRequest(BaseModel):
    ssh_key: str
    comment: str

class SSHKeyDeleteRequest(BaseModel):
    ssh_key: str
