"""Point d'entrée de l'API FastAPI."""
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from .config import CORS_ORIGINS
from .routers import (
    auth,
    crud,
    dashboard,
    exports,
    generation,
    heures,
    imports,
    notes,
    seances,
)
from .seed import initialiser_base

RACINE = Path(__file__).resolve().parent.parent
BUILD_WEB = RACINE.parent / "frontend" / "build" / "web"


@asynccontextmanager
async def cycle_de_vie(_app: FastAPI):
    initialiser_base()
    yield


app = FastAPI(
    title="Gestion des emplois du temps universitaires",
    description="API de gestion des enseignants, UE, groupes, salles, séances et heures effectuées.",
    version="1.0.0",
    lifespan=cycle_de_vie,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(crud.router)
app.include_router(seances.router)
app.include_router(dashboard.router)
app.include_router(heures.router)
app.include_router(generation.router)
app.include_router(exports.router)
app.include_router(imports.router)
app.include_router(notes.router)


@app.middleware("http")
async def interface_sans_cache(request, call_next):
    """Évite que le navigateur serve une ancienne version de l'interface Flutter."""
    response = await call_next(request)
    if request.url.path.startswith("/app"):
        response.headers["Cache-Control"] = "no-store, max-age=0"
    return response


@app.get("/api/sante", tags=["système"])
def sante():
    return {"statut": "ok", "application": "Gestion des emplois du temps universitaires"}


if BUILD_WEB.exists():
    app.mount("/app", StaticFiles(directory=str(BUILD_WEB), html=True), name="interface")


@app.get("/", include_in_schema=False)
def accueil():
    if BUILD_WEB.exists():
        return RedirectResponse("/app/")
    return {
        "message": "API opérationnelle. Interface Flutter : lancez `flutter run -d chrome` dans frontend/.",
        "documentation": "/docs",
        "sante": "/api/sante",
    }
