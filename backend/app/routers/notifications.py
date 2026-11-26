"""Notifications envoyées par les administrateurs aux autres comptes."""
from datetime import timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Notification, NotificationLecture, Utilisateur
from ..schemas import NotificationCreate, NotificationOut
from ..security import (
    ROLE_ADMIN,
    ROLE_ENSEIGNANT,
    ROLE_GESTIONNAIRE,
    ROLE_LECTEUR,
    ROLE_SUPERVISEUR,
    admin_seul,
    utilisateur_courant,
)

router = APIRouter(prefix="/api/notifications", tags=["notifications"])

# Le rôle « lecteur » correspond aux comptes étudiants.
COLONNES_DESTINATAIRES = {
    ROLE_ADMIN: "aux_admins",
    ROLE_GESTIONNAIRE: "aux_gestionnaires",
    ROLE_ENSEIGNANT: "aux_enseignants",
    ROLE_LECTEUR: "aux_etudiants",
    ROLE_SUPERVISEUR: "aux_superviseurs",
}


def _colonne_role(role: str) -> str | None:
    return COLONNES_DESTINATAIRES.get(role)


def _destinataires(notification: Notification) -> list[str]:
    return [
        role
        for role, colonne in COLONNES_DESTINATAIRES.items()
        if getattr(notification, colonne)
    ]


def _serialiser(notification: Notification, lu: bool) -> dict:
    cree_le = notification.cree_le
    if cree_le is not None and cree_le.tzinfo is None:
        # Les dates sont enregistrées en UTC sans fuseau : on l'indique pour que
        # l'interface les convertisse dans le fuseau de l'utilisateur.
        cree_le = cree_le.replace(tzinfo=timezone.utc)
    return {
        "id": notification.id,
        "titre": notification.titre,
        "message": notification.message,
        "auteur_id": notification.auteur_id,
        "auteur_nom": notification.auteur.nom_complet if notification.auteur else "",
        "cree_le": cree_le.isoformat() if cree_le else "",
        "lu": lu,
        "destinataires": _destinataires(notification),
    }


def _concerne(utilisateur: Utilisateur, notification: Notification) -> bool:
    """Vrai si la notification est adressée au compte ou envoyée par lui.

    L'expéditeur conserve une copie de son message dans sa propre boîte, même
    s'il n'a pas coché son groupe de rôle parmi les destinataires.
    """
    if notification.auteur_id == utilisateur.id:
        return True
    colonne = _colonne_role(utilisateur.role)
    if colonne is None:
        return False
    return bool(getattr(notification, colonne))


@router.get("", response_model=list[NotificationOut])
def lister_notifications(
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    colonne = _colonne_role(utilisateur.role)
    if colonne is None:
        return []
    notifications = (
        db.query(Notification)
        .filter(
            or_(
                getattr(Notification, colonne).is_(True),
                Notification.auteur_id == utilisateur.id,
            )
        )
        .order_by(Notification.cree_le.desc(), Notification.id.desc())
        .all()
    )
    if not notifications:
        return []
    ids = [notification.id for notification in notifications]
    lues = {
        ligne[0]
        for ligne in db.query(NotificationLecture.notification_id)
        .filter(
            NotificationLecture.utilisateur_id == utilisateur.id,
            NotificationLecture.notification_id.in_(ids),
        )
        .all()
    }
    return [
        _serialiser(notification, notification.id in lues)
        for notification in notifications
    ]


@router.post("")
def creer_notification(
    payload: NotificationCreate,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(admin_seul),
):
    titre = payload.titre.strip()
    message = payload.message.strip()
    if not titre or not message:
        raise HTTPException(400, "Le titre et le message sont obligatoires")

    destinataires: list[str] = []
    for role in payload.destinataires:
        role = role.strip()
        if role not in COLONNES_DESTINATAIRES:
            raise HTTPException(400, f"Groupe de destinataires inconnu : {role}")
        if role not in destinataires:
            destinataires.append(role)
    if not destinataires:
        raise HTTPException(400, "Choisissez au moins un groupe de destinataires")

    destinataires_actifs = {
        identifiant
        for (identifiant,) in db.query(Utilisateur.id)
        .filter(
            Utilisateur.actif.is_(True),
            Utilisateur.role.in_(destinataires),
        )
        .all()
    }
    if not destinataires_actifs:
        raise HTTPException(
            400,
            "Aucun destinataire actif ne correspond aux groupes choisis",
        )
    # L'expéditeur reçoit toujours une copie de son message dans sa boîte.
    destinataires_actifs.add(utilisateur.id)
    nombre = len(destinataires_actifs)

    notification = Notification(
        titre=titre[:180],
        message=message,
        auteur_id=utilisateur.id,
        aux_admins=ROLE_ADMIN in destinataires,
        aux_gestionnaires=ROLE_GESTIONNAIRE in destinataires,
        aux_enseignants=ROLE_ENSEIGNANT in destinataires,
        aux_etudiants=ROLE_LECTEUR in destinataires,
        aux_superviseurs=ROLE_SUPERVISEUR in destinataires,
    )
    db.add(notification)
    db.commit()
    db.refresh(notification)
    return {
        "ok": True,
        "id": notification.id,
        "nombre_destinataires": nombre,
        "destinataires": destinataires,
    }


@router.post("/lu")
def marquer_tout_lu(
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    colonne = _colonne_role(utilisateur.role)
    if colonne is None:
        return {"ok": True, "marquees": 0}
    notifications = (
        db.query(Notification)
        .filter(
            or_(
                getattr(Notification, colonne).is_(True),
                Notification.auteur_id == utilisateur.id,
            )
        )
        .all()
    )
    if not notifications:
        return {"ok": True, "marquees": 0}
    ids = [notification.id for notification in notifications]
    deja_lues = {
        ligne[0]
        for ligne in db.query(NotificationLecture.notification_id)
        .filter(
            NotificationLecture.utilisateur_id == utilisateur.id,
            NotificationLecture.notification_id.in_(ids),
        )
        .all()
    }
    ajouts = [
        NotificationLecture(
            notification_id=notification.id,
            utilisateur_id=utilisateur.id,
        )
        for notification in notifications
        if notification.id not in deja_lues
    ]
    if ajouts:
        db.add_all(ajouts)
        db.commit()
    return {"ok": True, "marquees": len(ajouts)}


@router.post("/{notification_id}/lu")
def marquer_lu(
    notification_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    notification = db.get(Notification, notification_id)
    if notification is None or not _concerne(utilisateur, notification):
        raise HTTPException(404, "Notification introuvable")
    existe = (
        db.query(NotificationLecture)
        .filter(
            NotificationLecture.notification_id == notification.id,
            NotificationLecture.utilisateur_id == utilisateur.id,
        )
        .first()
    )
    if existe is None:
        db.add(
            NotificationLecture(
                notification_id=notification.id,
                utilisateur_id=utilisateur.id,
            )
        )
        db.commit()
    return {"ok": True}


@router.delete("/{notification_id}")
def supprimer_notification(
    notification_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(admin_seul),
):
    """Supprime définitivement un message envoyé par l'administrateur connecté.

    Le retrait vaut pour tous les destinataires : il permet de revenir sur un
    envoi effectué par erreur. Les accusés de lecture sont supprimés en
    cascade avec la notification.
    """
    notification = db.get(Notification, notification_id)
    if notification is None:
        raise HTTPException(404, "Notification introuvable")
    if notification.auteur_id != utilisateur.id:
        raise HTTPException(
            403,
            "Vous ne pouvez supprimer que les messages que vous avez envoyés.",
        )
    db.delete(notification)
    db.commit()
    return {"ok": True, "id": notification_id}
