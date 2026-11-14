"""Authentification et profil utilisateur."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Utilisateur
from ..schemas import LoginRequest, TokenResponse, UtilisateurOut
from ..security import (
    creer_jeton,
    hacher_mot_de_passe,
    utilisateur_courant,
    verifier_mot_de_passe,
)

router = APIRouter(prefix="/api/auth", tags=["authentification"])


@router.post("/connexion", response_model=TokenResponse)
def connexion(payload: LoginRequest, db: Session = Depends(get_db)):
    utilisateur = (
        db.query(Utilisateur).filter(Utilisateur.identifiant == payload.identifiant.strip()).first()
    )
    if not utilisateur or not verifier_mot_de_passe(payload.mot_de_passe, utilisateur.mot_de_passe_hash):
        raise HTTPException(401, "Identifiant ou mot de passe incorrect")
    if not utilisateur.actif:
        raise HTTPException(403, "Ce compte est désactivé")
    return TokenResponse(
        access_token=creer_jeton(utilisateur),
        utilisateur=UtilisateurOut.model_validate(utilisateur),
    )


@router.get("/moi", response_model=UtilisateurOut)
def profil(utilisateur: Utilisateur = Depends(utilisateur_courant)):
    return utilisateur


@router.post("/mot-de-passe")
def changer_mot_de_passe(
    payload: dict,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    ancien = str(payload.get("ancien", ""))
    nouveau = str(payload.get("nouveau", ""))
    if not verifier_mot_de_passe(ancien, utilisateur.mot_de_passe_hash):
        raise HTTPException(400, "Ancien mot de passe incorrect")
    if len(nouveau) < 4:
        raise HTTPException(400, "Le nouveau mot de passe doit contenir au moins 4 caractères")
    utilisateur.mot_de_passe_hash = hacher_mot_de_passe(nouveau)
    db.commit()
    return {"ok": True, "message": "Mot de passe modifié"}
