from app.routers import admin
from contextlib import asynccontextmanager

from fastapi import FastAPI


from app.database import check_database, engine
from app.models.user import Base
from app.database import AsyncSessionLocal
from app.routers.auth import router as auth_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create tables for local development.
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

from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://unnati-636c6.web.app",
        "https://unnati-636c6.firebaseapp.com",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(admin.router)


@app.get("/")
async def root():
    return {"message": "Unnati API is running", "status": "healthy"}


@app.get("/health")
async def health():
    try:
        await check_database()
        return {"status": "healthy", "database": "connected"}
    except Exception:
        return {"status": "unhealthy", "database": "disconnected"}
