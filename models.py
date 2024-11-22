from pydantic import BaseModel

class SSHKeyPutRequest(BaseModel):
    ssh_key: str
    comment: str

class SSHKeyDeleteRequest(BaseModel):
    ssh_key: str
