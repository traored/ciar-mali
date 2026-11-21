"""Registre des surveillants d'évaluations.

Ce registre est indépendant des enseignants : il alimente les propositions de
noms de l'espace « Surveillances » et conserve les coordonnées des personnes
qui assurent la surveillance des épreuves.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Surveillant, SurveillanceSurveillant, Utilisateur
from ..schemas import SurveillantCreate, SurveillantOut, SurveillantUpdate
from ..security import admin_gestionnaire_superviseur

router = APIRouter(prefix="/api/surveillants", tags=["surveillants"])


def _normaliser(payload: dict) -> dict:
    """Nettoie les champs texte et remplace un matricule vide par NULL."""
    for champ in (
        "prenom",
        "nom",
        "lieu_naissance",
        "telephone",
        "email",
        "matricule",
        "fonction",
        "observation",
    ):
        valeur = payload.get(champ)
        if isinstance(valeur, str):
            payload[champ] = valeur.strip()
    if "matricule" in payload and not payload["matricule"]:
        payload["matricule"] = None
    return payload


def _charger(db: Session, surveillant_id: int) -> Surveillant:
    element = db.get(Surveillant, surveillant_id)
    if not element:
        raise HTTPException(404, "Surveillant introuvable")
    return element


@router.get("", response_model=list[SurveillantOut])
def lister(
    q: str = Query(""),
    actif: Optional[bool] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Liste le registre, trié par nom puis prénom."""
    requete = db.query(Surveillant)
    if actif is not None:
        requete = requete.filter(Surveillant.actif.is_(actif))
    if q and q.strip():
        motif = f"%{q.strip()}%"
        requete = requete.filter(
            or_(
                Surveillant.prenom.ilike(motif),
                Surveillant.nom.ilike(motif),
                Surveillant.telephone.ilike(motif),
                Surveillant.email.ilike(motif),
                Surveillant.matricule.ilike(motif),
                Surveillant.lieu_naissance.ilike(motif),
                Surveillant.fonction.ilike(motif),
            )
        )
    return requete.order_by(Surveillant.nom, Surveillant.prenom).all()


@router.get("/{surveillant_id}", response_model=SurveillantOut)
def detail(
    surveillant_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    return _charger(db, surveillant_id)


@router.post("", response_model=SurveillantOut, status_code=201)
def creer(
    payload: SurveillantCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    donnees = _normaliser(payload.model_dump())
    element = Surveillant(**donnees)
    db.add(element)
    db.commit()
    db.refresh(element)
    return element


@router.put("/{surveillant_id}", response_model=SurveillantOut)
def modifier(
    surveillant_id: int,
    payload: SurveillantUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    element = _charger(db, surveillant_id)
    donnees = _normaliser(payload.model_dump(exclude_unset=True))
    for cle, valeur in donnees.items():
        setattr(element, cle, valeur)
    db.commit()
    db.refresh(element)
    return element


@router.delete("/{surveillant_id}")
def supprimer(
    surveillant_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Supprime la fiche sans effacer les surveillances passées.

    Les lignes de surveillance conservent le nom en clair ; seul le lien vers
    la fiche est retiré.
    """
    element = _charger(db, surveillant_id)
    db.query(SurveillanceSurveillant).filter(
        SurveillanceSurveillant.surveillant_id == surveillant_id
    ).update(
        {SurveillanceSurveillant.surveillant_id: None}, synchronize_session=False
    )
    db.delete(element)
    db.commit()
    return {"ok": True, "message": "Surveillant supprimé"}
