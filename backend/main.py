from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from slowapi.errors import RateLimitExceeded

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.errors import AppError, app_error_handler
from app.core.limiter import limiter
from app.core.logging import logger, setup_logging
from app.core.middleware import RequestIDMiddleware, SecurityHeadersMiddleware
from app.db.mongodb import close_db, init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    logger.info(f"Starting {settings.APP_NAME} in {settings.APP_ENV} mode...")
    await init_db()
    yield
    logger.info(f"Shutting down {settings.APP_NAME}...")
    await close_db()


app = FastAPI(
    title="AyeKitchen API",
    description="Microservicio de costeo de recetas, ingredientes y pedidos — Ecosistema AyeApps",
    version="1.0.0",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
    lifespan=lifespan,
)

# SlowAPI Rate Limiting State
app.state.limiter = limiter
app.add_exception_handler(AppError, app_error_handler)


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={
            "detail": "Demasiadas peticiones. Por favor inténtalo más tarde.",
            "code": "RATE_LIMIT_EXCEEDED",
        },
    )


# Middlewares (Executed in reverse order of addition)
cors_origins = settings.CORS_ORIGINS if isinstance(settings.CORS_ORIGINS, list) else []
if "*" in cors_origins:
    cors_origins = ["http://localhost:3006", "https://kitchen.ayeapps.com"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=None if settings.is_production else r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestIDMiddleware)


@app.get("/", tags=["Health"], status_code=status.HTTP_200_OK)
async def root():
    return {
        "status": "ok",
        "app": settings.APP_NAME,
        "env": settings.APP_ENV,
        "version": "1.0.0",
    }


@app.get("/robots.txt", response_class=PlainTextResponse, tags=["SEO"])
async def robots():
    return "User-agent: *\nDisallow: /\n"


@app.get("/health", tags=["Health"], status_code=status.HTTP_200_OK)
async def health_check():
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "env": settings.APP_ENV,
        "version": "1.0.0",
    }


# Include Routers
app.include_router(api_router, prefix="/api/v1")
