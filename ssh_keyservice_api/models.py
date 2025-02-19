from pydantic import BaseModel

class UserModel(BaseModel):
    id: str
    user_data: dict[str, str]
    ssh_keys: dict[str, str]

class SSHKeyPutRequest(BaseModel):
    ssh_key: str
    comment: str

class SSHKeyDeleteRequest(BaseModel):
    ssh_key: str
