"""Tableau de bord : indicateurs, charge hebdomadaire et alertes."""
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import (
    Affectation,
    ECUE,
    Enseignant,
    Groupe,
    Salle,
    Seance,
    Semestre,
    UE,
    Utilisateur,
)
from ..security import ROLE_ENSEIGNANT, utilisateur_courant
from ..scheduler import JOURS

router = APIRouter(prefix="/api/tableau-de-bord", tags=["tableau de bord"])


def _semaine_courante(semestre: Semestre) -> int:
    if not semestre:
        return 1
    aujourdhui = date.today()
    if aujourdhui < semestre.date_debut:
        return 1
    semaine = ((aujourdhui - semestre.date_debut).days // 7) + 1
    return max(1, min(semaine, semestre.semaines))


@router.get("")
def tableau_de_bord(
    semestre_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    semestre = db.get(Semestre, semestre_id) if semestre_id else db.query(Semestre).filter(Semestre.actif.is_(True)).first()
    if not semestre:
        semestre = db.query(Semestre).first()

    requete = db.query(Seance)
    if semestre:
        requete = requete.filter(Seance.semestre_id == semestre.id)
    if utilisateur.role == ROLE_ENSEIGNANT and utilisateur.enseignant_id:
        requete = requete.filter(Seance.enseignant_id == utilisateur.enseignant_id)
    seances = requete.all()

    heures_planifiees = round(sum(s.duree for s in seances if s.statut != "annulee"), 1)
    heures_effectuees = round(sum(s.duree for s in seances if s.statut == "effectuee"), 1)

    semaine = _semaine_courante(semestre) if semestre else 1
    charge_jours = {jour: 0.0 for jour in JOURS}
    for seance in seances:
        if seance.semaine == semaine and seance.statut != "annulee" and seance.creneau:
            charge_jours[JOURS[seance.creneau.jour]] += seance.duree

    enseignant_filtre = None
    if utilisateur.role == ROLE_ENSEIGNANT and utilisateur.enseignant_id:
        enseignant_filtre = db.get(Enseignant, utilisateur.enseignant_id)

    classes = []
    for seance in sorted(
        [s for s in seances if s.semaine == semaine and s.statut != "annulee"],
        key=lambda s: (s.creneau.jour if s.creneau else 0, s.creneau.debut if s.creneau else ""),
    )[:8]:
        classes.append(
            {
                "id": seance.id,
                "jour": seance.creneau_jour,
                "debut": seance.creneau_debut,
                "fin": seance.creneau_fin,
                "ecue": seance.ecue_code,
                "ecue_nom": seance.ecue_nom,
                "type": seance.type_seance,
                "salle": seance.salle_nom,
                "enseignant": seance.enseignant_nom,
                "groupes": seance.groupes_noms,
                "statut": seance.statut,
            }
        )

    # Alertes
    alertes = []
    if utilisateur.role != ROLE_ENSEIGNANT:
        surcharge = []
        par_enseignant: dict[int, float] = {}
        for seance in seances:
            if seance.statut != "annulee":
                par_enseignant[seance.enseignant_id] = par_enseignant.get(seance.enseignant_id, 0) + seance.duree
        for enseignant in db.query(Enseignant).filter(Enseignant.actif.is_(True)).all():
            total = par_enseignant.get(enseignant.id, 0)
            if total > enseignant.heures_max:
                surcharge.append(
                    {
                        "type": "surcharge",
                        "message": f"{enseignant.nom_complet} dépasse son volume maximum ({total:g} h / {enseignant.heures_max} h)",
                    }
                )
        alertes.extend(surcharge[:5])

        if semestre:
            sans_affectation = (
                db.query(ECUE)
                .join(UE, ECUE.ue_id == UE.id)
                .filter(UE.semestre_id == semestre.id)
                .filter(
                    ~ECUE.id.in_(
                        db.query(Affectation.ecue_id).filter(
                            Affectation.semestre_id == semestre.id
                        )
                    )
                )
                .count()
            )
            if sans_affectation:
                alertes.append(
                    {
                        "type": "affectation",
                        "message": f"{sans_affectation} ECUE sans enseignant affecté",
                    }
                )
            groupes_vides = [
                g for g in db.query(Groupe).all() if not any(g.id in {x.id for x in s.groupes} for s in seances)
            ]
            if groupes_vides:
                alertes.append(
                    {
                        "type": "planning",
                        "message": f"{len(groupes_vides)} groupe(s) sans aucune séance planifiée",
                    }
                )

    return {
        "semestre": {
            "id": semestre.id,
            "nom": semestre.nom,
            "annee": semestre.annee,
            "semaines": semestre.semaines,
        }
        if semestre
        else None,
        "semaine_courante": semaine,
        "indicateurs": {
            "enseignants": db.query(Enseignant).filter(Enseignant.actif.is_(True)).count(),
            "groupes": db.query(Groupe).count(),
            "salles": db.query(Salle).count(),
            "ues": db.query(UE).filter(UE.semestre_id == semestre.id).count() if semestre else db.query(UE).count(),
            "ecues": db.query(ECUE).filter(ECUE.semestre_id == semestre.id).count() if semestre else db.query(ECUE).count(),
            "seances": len([s for s in seances if s.statut != "annulee"]),
            "heures_planifiees": heures_planifiees,
            "heures_effectuees": heures_effectuees,
            "taux_realisation": round(heures_effectuees / heures_planifiees * 100, 1)
            if heures_planifiees
            else 0,
        },
        "charge_jours": charge_jours,
        "prochaines_seances": classes,
        "alertes": alertes,
        "enseignant": {
            "nom": enseignant_filtre.nom_complet,
            "heures_max": enseignant_filtre.heures_max,
        }
        if enseignant_filtre
        else None,
    }
