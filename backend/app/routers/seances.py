"""Gestion des séances : consultation, création manuelle, verrouillage, statut."""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload, selectinload

from ..database import get_db
from ..models import Creneau, ECUE, Enseignant, Groupe, Niveau, Salle, Seance, Semestre, UE, Utilisateur
from ..models import Affectation
from ..schemas import (
    SeanceCreate,
    SeanceOut,
    SeanceReguliereCreate,
    SeanceReguliereOut,
    SeanceUpdate,
    StatutUpdate,
)
from ..scheduler import conflits, verifier_conflits
from ..security import (
    ROLE_ADMIN,
    ROLE_ENSEIGNANT,
    ROLE_GESTIONNAIRE,
    ROLE_LECTEUR,
    admin_ou_gestionnaire,
    utilisateur_courant,
)

router = APIRouter(prefix="/api/seances", tags=["séances"])

STATUTS = {"planifiee", "effectuee", "annulee"}
TYPES = {"CM", "TD", "TP"}


def _groupes_effectifs(db: Session, payload) -> list[int]:
    """Groupes réellement concernés par la séance.

    Un CM mutualisé (CM commun) est dispensé à tous les groupes des niveaux
    concernés, même si le client n'en a envoyé qu'une partie. On complète donc
    systématiquement la sélection pour que l'emploi du temps affiche tous les
    groupes.
    """
    ids = list(dict.fromkeys(payload.groupe_ids or []))
    if payload.type_seance != "CM":
        return ids

    affectations = (
        db.query(Affectation)
        .filter(
            Affectation.ecue_id == payload.ecue_id,
            Affectation.enseignant_id == payload.enseignant_id,
            Affectation.semestre_id == payload.semestre_id,
            Affectation.cm_commun.is_(True),
        )
        .all()
    )
    if not affectations:
        return ids

    niveaux = {
        affectation.groupe.niveau_id
        for affectation in affectations
        if affectation.groupe and affectation.groupe.niveau_id
    }
    if not niveaux:
        ecue = db.get(ECUE, payload.ecue_id)
        if ecue and ecue.ue:
            niveaux.update(ecue.ue.niveau_ids)

    if niveaux:
        for groupe in db.query(Groupe).filter(Groupe.niveau_id.in_(niveaux)).all():
            if groupe.id not in ids:
                ids.append(groupe.id)
    return ids


def _valider_references(db: Session, payload):
    semestre = db.get(Semestre, payload.semestre_id)
    if not semestre:
        raise HTTPException(404, "Semestre introuvable")
    if payload.semaine < 1 or payload.semaine > semestre.semaines:
        raise HTTPException(400, f"La semaine doit être comprise entre 1 et {semestre.semaines}.")
    if not db.get(Creneau, payload.creneau_id):
        raise HTTPException(404, "Créneau introuvable")
    if not db.get(Enseignant, payload.enseignant_id):
        raise HTTPException(404, "Enseignant introuvable")
    if not db.get(ECUE, payload.ecue_id):
        raise HTTPException(404, "ECUE introuvable")
    if payload.salle_id and not db.get(Salle, payload.salle_id):
        raise HTTPException(404, "Salle introuvable")
    if payload.type_seance not in TYPES:
        raise HTTPException(400, "Type de séance invalide")
    if payload.statut not in STATUTS:
        raise HTTPException(400, "Statut invalide")
    ids = _groupes_effectifs(db, payload)
    groupes = db.query(Groupe).filter(Groupe.id.in_(ids)).all() if ids else []
    if len(groupes) != len(ids):
        raise HTTPException(400, "Un ou plusieurs groupes sont introuvables")
    return semestre, groupes


def _verifier_references(db: Session, payload, seance_id: Optional[int] = None):
    _, groupes = _valider_references(db, payload)
    verifier_conflits(
        db,
        semestre_id=payload.semestre_id,
        semaine=payload.semaine,
        creneau_id=payload.creneau_id,
        enseignant_id=payload.enseignant_id,
        salle_id=payload.salle_id,
        groupe_ids=[groupe.id for groupe in groupes],
        ignorer_id=seance_id,
    )
    return groupes


def _appliquer_groupes(seance: Seance, groupes: list[Groupe]):
    seance.groupes = groupes


def _restreindre_perimetre(
    requete,
    db: Session,
    utilisateur: Utilisateur,
    groupe_id: Optional[int] = None,
):
    """Limite une requête de séances au périmètre de l'utilisateur.

    Renvoie ``None`` lorsque l'utilisateur n'a accès à aucune séance.
    """
    if utilisateur.role == ROLE_ENSEIGNANT and utilisateur.enseignant_id:
        return requete.filter(Seance.enseignant_id == utilisateur.enseignant_id)
    if utilisateur.role == ROLE_LECTEUR:
        from sqlalchemy import and_, or_

        from ..models import Inscription, Niveau, UE

        inscriptions = (
            db.query(Inscription)
            .filter(Inscription.etudiant_id == utilisateur.etudiant_id)
            .all()
            if utilisateur.etudiant_id
            else []
        )
        if not inscriptions:
            return None
        groupes = {i.groupe_id for i in inscriptions if i.groupe_id}
        if groupe_id and groupe_id not in groupes:
            return None

        # Chaque inscription ne donne accès qu'aux séances de son année : un
        # étudiant qui change de groupe ou de niveau ne doit pas revoir les
        # séances de ses anciennes inscriptions dans les semestres récents.
        conditions = []
        for inscription in inscriptions:
            if inscription.groupe_id:
                conditions.append(
                    and_(
                        Semestre.annee == inscription.annee,
                        Seance.groupes.any(Groupe.id == inscription.groupe_id),
                    )
                )
            elif inscription.niveau_id:
                conditions.append(
                    and_(
                        Semestre.annee == inscription.annee,
                        Seance.ecue.has(
                            ECUE.ue.has(
                                UE.niveaux.any(Niveau.id == inscription.niveau_id)
                            )
                        ),
                    )
                )
        if not conditions:
            return None
        return requete.join(Semestre, Seance.semestre_id == Semestre.id).filter(
            or_(*conditions)
        )
    return requete


@router.get("", response_model=list[SeanceOut])
def lister_seances(
    semestre_id: Optional[int] = Query(None),
    semaine: Optional[int] = Query(None),
    groupe_id: Optional[int] = Query(None),
    enseignant_id: Optional[int] = Query(None),
    salle_id: Optional[int] = Query(None),
    statut: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    requete = db.query(Seance).options(
        selectinload(Seance.groupes)
        .joinedload(Groupe.niveau)
        .joinedload(Niveau.filiere),
        joinedload(Seance.ecue)
        .joinedload(ECUE.ue)
        .joinedload(UE.niveau)
        .joinedload(Niveau.filiere),
        joinedload(Seance.creneau),
        joinedload(Seance.salle),
        joinedload(Seance.enseignant),
    )
    if semestre_id:
        requete = requete.filter(Seance.semestre_id == semestre_id)
    if semaine:
        requete = requete.filter(Seance.semaine == semaine)
    if enseignant_id:
        requete = requete.filter(Seance.enseignant_id == enseignant_id)
    if salle_id:
        requete = requete.filter(Seance.salle_id == salle_id)
    if statut:
        requete = requete.filter(Seance.statut == statut)
    if groupe_id:
        requete = requete.filter(Seance.groupes.any(Groupe.id == groupe_id))
    requete = _restreindre_perimetre(requete, db, utilisateur, groupe_id)
    if requete is None:
        return []
    return requete.order_by(Seance.semaine, Seance.creneau_id).all()


@router.get("/semaines")
def semaines_avec_seances(
    semestre_id: int = Query(...),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Semaines du semestre qui contiennent au moins une séance accessible.

    L'interface s'en sert pour ouvrir l'application sur la semaine courante
    qui contient réellement des données.
    """
    requete = db.query(Seance.semaine).filter(Seance.semestre_id == semestre_id)
    requete = _restreindre_perimetre(requete, db, utilisateur)
    if requete is None:
        return {"semaines": []}
    semaines = sorted({semaine for (semaine,) in requete.distinct().all()})
    return {"semaines": semaines}


@router.get("/semestres")
def semestres_avec_seances(
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Semestres où l'utilisateur a au moins une séance accessible.

    Un enseignant peut se retrouver avec des séances dans un semestre où il
    n'a pas d'affectation (séance créée par un administrateur). L'interface
    s'en sert pour rendre ce semestre sélectionnable, faute de quoi son
    emploi du temps paraît vide.
    """
    requete = db.query(Seance.semestre_id).filter(Seance.semestre_id.isnot(None))
    requete = _restreindre_perimetre(requete, db, utilisateur)
    if requete is None:
        return {"semestres": []}
    semestres = sorted(
        {semestre for (semestre,) in requete.distinct().all() if semestre}
    )
    return {"semestres": semestres}


@router.get("/{seance_id}", response_model=SeanceOut)
def detail_seance(
    seance_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    seance = db.get(Seance, seance_id)
    if not seance:
        raise HTTPException(404, "Séance introuvable")
    if utilisateur.role == ROLE_LECTEUR:
        from ..models import Inscription

        inscriptions = (
            db.query(Inscription)
            .filter(Inscription.etudiant_id == utilisateur.etudiant_id)
            .all()
            if utilisateur.etudiant_id
            else []
        )
        groupes = {i.groupe_id for i in inscriptions if i.groupe_id}
        if not groupes.intersection(seance.groupe_ids):
            raise HTTPException(403, "Cette séance ne concerne pas votre groupe.")
    elif utilisateur.role == ROLE_ENSEIGNANT and utilisateur.enseignant_id:
        if seance.enseignant_id != utilisateur.enseignant_id:
            raise HTTPException(403, "Cette séance ne vous est pas affectée.")
    return seance


@router.post("", response_model=SeanceOut, status_code=201)
def creer_seance(
    payload: SeanceCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    groupes = _verifier_references(db, payload)
    seance = Seance(**payload.model_dump(exclude={"groupe_ids"}))
    _appliquer_groupes(seance, groupes)
    db.add(seance)
    db.commit()
    db.refresh(seance)
    return seance


@router.post("/reguliere", response_model=SeanceReguliereOut, status_code=201)
def creer_seances_regulieres(
    payload: SeanceReguliereCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Crée la même séance sur plusieurs semaines consécutives.

    Chaque semaine est matérialisée par une séance indépendante : supprimer ou
    annuler la séance d'une semaine ne touche pas aux autres semaines.
    """
    semestre, groupes = _valider_references(db, payload)
    if payload.semaine_fin is not None and payload.semaine_fin < payload.semaine:
        raise HTTPException(400, "La semaine de fin doit être postérieure à la semaine de début.")
    fin = min(payload.semaine_fin or semestre.semaines, semestre.semaines)

    donnees = payload.model_dump(exclude={"groupe_ids", "semaine_fin"})
    semaines_creees: list[int] = []
    conflits_semaines: list[dict] = []

    for semaine in range(payload.semaine, fin + 1):
        messages = conflits(
            db,
            semestre_id=payload.semestre_id,
            semaine=semaine,
            creneau_id=payload.creneau_id,
            enseignant_id=payload.enseignant_id,
            salle_id=payload.salle_id,
            groupe_ids=[groupe.id for groupe in groupes],
        )
        if messages:
            conflits_semaines.append({"semaine": semaine, "messages": messages})
            continue
        seance = Seance(**{**donnees, "semaine": semaine})
        _appliquer_groupes(seance, groupes)
        db.add(seance)
        semaines_creees.append(semaine)

    if not semaines_creees:
        db.rollback()
        details = " ".join(
            f"Semaine {conflit['semaine']} : {' '.join(conflit['messages'])}"
            for conflit in conflits_semaines[:3]
        )
        raise HTTPException(409, f"Aucune séance n'a pu être créée. {details}".strip())

    db.commit()
    message = (
        f"{len(semaines_creees)} séance(s) créée(s) de la semaine {semaines_creees[0]} "
        f"à {semaines_creees[-1]}."
    )
    if conflits_semaines:
        message += f" {len(conflits_semaines)} semaine(s) ignorée(s) pour cause de conflit."
    return {
        "creees": len(semaines_creees),
        "semaines": semaines_creees,
        "conflits": conflits_semaines,
        "message": message,
    }


@router.put("/{seance_id}", response_model=SeanceOut)
def modifier_seance(
    seance_id: int,
    payload: SeanceUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    seance = db.get(Seance, seance_id)
    if not seance:
        raise HTTPException(404, "Séance introuvable")
    if seance.verrouillee:
        raise HTTPException(400, "Cette séance est verrouillée. Déverrouillez-la pour la modifier.")
    if seance.statut == "effectuee":
        raise HTTPException(
            400,
            "Une séance effectuée ne peut plus être modifiée. Repassez-la en « planifiée » pour la corriger.",
        )

    donnees = payload.model_dump(exclude_unset=True)
    donnees.pop("groupe_ids", None)
    fusion = {
        "semestre_id": seance.semestre_id,
        "semaine": seance.semaine,
        "creneau_id": seance.creneau_id,
        "salle_id": seance.salle_id,
        "enseignant_id": seance.enseignant_id,
        "ecue_id": seance.ecue_id,
        "affectation_id": seance.affectation_id,
        "type_seance": seance.type_seance,
        "statut": seance.statut,
        "verrouillee": seance.verrouillee,
        "notes": seance.notes or "",
        "groupe_ids": [g.id for g in seance.groupes],
        **donnees,
    }
    if payload.groupe_ids is not None:
        fusion["groupe_ids"] = payload.groupe_ids
    from ..schemas import SeanceCreate

    groupes = _verifier_references(db, SeanceCreate(**fusion), seance_id=seance_id)
    for cle, valeur in donnees.items():
        setattr(seance, cle, valeur)
    # Les groupes effectifs incluent tous ceux d'un CM mutualisé, y compris
    # lorsque seul le type de séance a été modifié.
    _appliquer_groupes(seance, groupes)
    db.commit()
    db.refresh(seance)
    return seance


@router.delete("/{seance_id}")
def supprimer_seance(
    seance_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    seance = db.get(Seance, seance_id)
    if not seance:
        raise HTTPException(404, "Séance introuvable")
    if seance.verrouillee:
        raise HTTPException(400, "Cette séance est verrouillée. Déverrouillez-la pour la supprimer.")
    if seance.statut == "effectuee":
        raise HTTPException(
            400,
            "Une séance effectuée ne peut pas être supprimée. Repassez-la en « planifiée » pour la supprimer.",
        )
    db.delete(seance)
    db.commit()
    return {"ok": True, "message": "Séance supprimée"}


@router.post("/{seance_id}/verrouiller", response_model=SeanceOut)
def verrouiller_seance(
    seance_id: int,
    payload: dict,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    seance = db.get(Seance, seance_id)
    if not seance:
        raise HTTPException(404, "Séance introuvable")
    seance.verrouillee = bool(payload.get("verrouillee", True))
    db.commit()
    db.refresh(seance)
    return seance


@router.post("/{seance_id}/statut", response_model=SeanceOut)
def changer_statut(
    seance_id: int,
    payload: StatutUpdate,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    seance = db.get(Seance, seance_id)
    if not seance:
        raise HTTPException(404, "Séance introuvable")
    if payload.statut not in STATUTS:
        raise HTTPException(400, "Statut invalide")
    if utilisateur.role == ROLE_ENSEIGNANT:
        if utilisateur.enseignant_id != seance.enseignant_id:
            raise HTTPException(403, "Vous ne pouvez modifier que vos propres séances")
    elif utilisateur.role not in (ROLE_ADMIN, ROLE_GESTIONNAIRE):
        raise HTTPException(403, "Action non autorisée")
    seance.statut = payload.statut
    db.commit()
    db.refresh(seance)
    return seance
