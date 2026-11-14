"""Sécurité : mots de passe, jetons JWT et contrôle des rôles."""
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import ALGORITHM, SECRET_KEY, TOKEN_EXPIRATION_MINUTES
from .database import get_db
from .models import Utilisateur

ROLE_ADMIN = "admin"
ROLE_GESTIONNAIRE = "gestionnaire"
ROLE_ENSEIGNANT = "enseignant"
ROLE_LECTEUR = "lecteur"
ROLES = [ROLE_ADMIN, ROLE_GESTIONNAIRE, ROLE_ENSEIGNANT, ROLE_LECTEUR]

bearer = HTTPBearer(auto_error=False)


def hacher_mot_de_passe(mot_de_passe: str) -> str:
    sel = os.urandom(16).hex()
    empreinte = hashlib.pbkdf2_hmac("sha256", mot_de_passe.encode(), sel.encode(), 120_000).hex()
    return f"{sel}${empreinte}"


def verifier_mot_de_passe(mot_de_passe: str, stocke: str) -> bool:
    try:
        sel, empreinte = stocke.split("$", 1)
    except ValueError:
        return False
    calculee = hashlib.pbkdf2_hmac("sha256", mot_de_passe.encode(), sel.encode(), 120_000).hex()
    return hmac.compare_digest(calculee, empreinte)


def creer_jeton(utilisateur: Utilisateur) -> str:
    expiration = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_EXPIRATION_MINUTES)
    payload = {
        "sub": str(utilisateur.id),
        "identifiant": utilisateur.identifiant,
        "role": utilisateur.role,
        "exp": expiration,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def utilisateur_courant(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> Utilisateur:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentification requise",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        utilisateur_id = int(payload.get("sub", 0))
    except (jwt.PyJWTError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session invalide ou expirée",
            headers={"WWW-Authenticate": "Bearer"},
        )
    utilisateur = db.get(Utilisateur, utilisateur_id)
    if not utilisateur or not utilisateur.actif:
        raise HTTPException(status_code=401, detail="Compte inactif ou introuvable")
    return utilisateur


def require_roles(*roles: str):
    """Dépendance FastAPI autorisant uniquement une liste de rôles."""

    def verificateur(utilisateur: Utilisateur = Depends(utilisateur_courant)) -> Utilisateur:
        if utilisateur.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Vous n'avez pas les droits pour cette action",
            )
        return utilisateur

    return verificateur


# Raccourcis
admin_ou_gestionnaire = require_roles(ROLE_ADMIN, ROLE_GESTIONNAIRE)
admin_seul = require_roles(ROLE_ADMIN)
