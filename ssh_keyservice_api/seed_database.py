from sqlmodel import SQLModel

from models import SSHKey, create_db_and_tables, engine

def drop_all():
    # Explicitly remove these tables first to avoid cascade errors
    SQLModel.metadata.remove(SSHKey.__table__)
    SQLModel.metadata.drop_all(engine)

if __name__ == "__main__":
    create_db_and_tables()
