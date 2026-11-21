"""Génération automatique de l'emploi du temps."""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..database import get_db
from ..schemas import GenerationRequest, GenerationResult
from ..scheduler import generer_planning
from ..security import admin_ou_gestionnaire

router = APIRouter(prefix="/api/generer", tags=["génération"])


@router.post("", response_model=GenerationResult)
def generer(
    payload: GenerationRequest,
    db: Session = Depends(get_db),
    _=Depends(admin_ou_gestionnaire),
):
    return generer_planning(db, payload.semestre_id, payload.remplacer)
