import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import check_database, engine
from app.models.user import Base
from app.routers import admin, guidance
from app.routers.auth import router as auth_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Auto-create tables on startup if they don't already exist
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    yield
    await engine.dispose()


app = FastAPI(
    title="Unnati API",
    description="AI-based vocational career counselling for students and parents",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS setup for both local development and hosted domains
cors_origins_env = os.getenv("CORS_ORIGINS", "*")
custom_origins = [o.strip() for o in cors_origins_env.split(",") if o.strip()]

default_origins = [
    "https://unnati-eta.vercel.app",
    "https://unnati-636c6.web.app",
    "https://unnati-636c6.firebaseapp.com",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
]

is_wildcard = "*" in custom_origins or cors_origins_env == "*"

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if is_wildcard else list(set(default_origins + custom_origins)),
    allow_origin_regex=r"^https?://.*" if is_wildcard else r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(admin.router)
app.include_router(guidance.router)


@app.get("/")
async def root():
    return {
        "message": "Unnati Career Guidance API is running",
        "status": "healthy",
        "version": "1.0.0",
    }


@app.get("/health")
async def health():
    try:
        await check_database()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": "disconnected", "error": str(e)}
