"""Configuration de l'application (MySQL ou SQLite pour la démo)."""
import os
from pathlib import Path
from urllib.parse import quote_plus

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.getenv("SECRET_KEY", "edt-universitaire-secret-a-changer-en-production")
ALGORITHM = "HS256"
TOKEN_EXPIRATION_MINUTES = int(os.getenv("TOKEN_EXPIRATION_MINUTES", "480"))

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()

# Les hébergeurs (Render, Neon, Supabase, Heroku…) fournissent des URL
# « postgres:// » ou « postgresql:// ». SQLAlchemy a besoin du pilote explicite.
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = "postgresql+psycopg://" + DATABASE_URL[len("postgres://") :]
elif DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = "postgresql+psycopg://" + DATABASE_URL[len("postgresql://") :]
elif DATABASE_URL.startswith("mysql://"):
    DATABASE_URL = "mysql+pymysql://" + DATABASE_URL[len("mysql://") :]

if not DATABASE_URL:
    mysql_host = os.getenv("MYSQL_HOST", "").strip()
    if mysql_host:
        user = quote_plus(os.getenv("MYSQL_USER", "root"))
        password = quote_plus(os.getenv("MYSQL_PASSWORD", ""))
        port = os.getenv("MYSQL_PORT", "3306")
        name = os.getenv("MYSQL_DATABASE", "edt_universitaire")
        DATABASE_URL = (
            f"mysql+pymysql://{user}:{password}@{mysql_host}:{port}/{name}?charset=utf8mb4"
        )
    else:
        DATABASE_URL = f"sqlite:///{(BASE_DIR / 'edt.db').as_posix()}"


# Origines autorisées pour l'interface Flutter Web
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS",
        (
            "http://localhost:8080,"
            "http://127.0.0.1:8080,"
            "http://localhost:8000,"
            "http://127.0.0.1:8000,"
            "http://localhost:5000,"
            "http://127.0.0.1:5000,"
            "http://localhost:3000,"
            "http://127.0.0.1:3000,"
            "http://localhost:61660,"
            "http://127.0.0.1:61660"
        ),
    ).split(",")
    if origin.strip()
]