
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import (
    create_async_engine,
    async_sessionmaker,
    AsyncSession,
)

env_path = Path(__file__).resolve().parents[1] / ".env"
load_dotenv(dotenv_path=env_path, override=True)

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is missing. Set it in the environment."
    )

# Convert the URL to SQLAlchemy's asyncpg dialect.
if DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace(
        "postgresql://", "postgresql+asyncpg://", 1
    )

# Neon URLs may contain parameters asyncpg doesn't accept.
db_url = make_url(DATABASE_URL)
query_params = dict(db_url.query)
query_params.pop("sslmode", None)
query_params.pop("channel_binding", None)
db_url = db_url.set(query=query_params)

engine = create_async_engine(
    db_url,
    echo=False,
    pool_pre_ping=True,
    connect_args={"ssl": "require"},
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session


async def check_database() -> bool:
    async with engine.connect() as connection:
        await connection.execute(text("SELECT 1"))
    return True
