"""Suivi des heures effectuées et planifiées par enseignant."""
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload

from ..database import get_db
from ..models import Affectation, ECUE, Enseignant, Seance, Semestre, Utilisateur
from ..security import ROLE_ENSEIGNANT, utilisateur_courant
from ..volumes import volumes_declares

router = APIRouter(prefix="/api/heures", tags=["heures enseignants"])


def _numero_semestre(nom: Optional[str]) -> Optional[int]:
    """Numéro d'un semestre d'après son nom (« Semestre 3 » → 3)."""
    if not nom:
        return None
    correspondance = re.search(r"semestre\s*(\d+)", nom, re.IGNORECASE)
    if correspondance is None:
        return None
    try:
        return int(correspondance.group(1))
    except ValueError:
        return None


def _entree_ecue(ecue: ECUE, semestre: Optional[Semestre]) -> dict:
    """Ligne de détail d'un ECUE, initialisée à zéro."""
    return {
        "ecue_id": ecue.id,
        "code": ecue.code,
        "nom": ecue.nom,
        "ue": ecue.ue_code,
        "semestre_id": semestre.id if semestre else None,
        "semestre": semestre.nom if semestre else "",
        "annee": semestre.annee if semestre else "",
        "cm": 0.0,
        "td": 0.0,
        "tp": 0.0,
        "planifiees": 0.0,
        "effectuees": 0.0,
        "_declare": False,
    }


def _ajouter_volumes_declares(entree: dict, affectations: list[Affectation]) -> None:
    """Renseigne les volumes CM/TD/TP déclarés d'un ECUE.

    Les affectations font foi : les séances générées (ou importées) peuvent
    toutes porter le type « CM » par défaut, ce qui faussait la répartition.
    """
    volumes = volumes_declares(affectations)
    entree["cm"] = volumes["cm"]
    entree["td"] = volumes["td"]
    entree["tp"] = volumes["tp"]
    entree["planifiees"] = round(volumes["cm"] + volumes["td"] + volumes["tp"], 1)
    entree["_declare"] = True


def _ajouter_seance_sans_affectation(entree: dict, seance: Seance) -> None:
    """Repli lorsqu'aucun volume n'est déclaré : les séances font foi."""
    if entree["_declare"]:
        return
    entree["planifiees"] = round(entree["planifiees"] + seance.duree, 1)
    type_seance = (seance.type_seance or "CM").lower()
    if type_seance in ("cm", "td", "tp"):
        entree[type_seance] = round(entree[type_seance] + seance.duree, 1)


@router.get("/global")
def rapport_heures_global(
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Totaux de tous les ECUE de l'enseignant, tous semestres confondus.

    « Suivi global » répond à la question : sur l'ensemble de mes ECUE, combien
    d'heures sont planifiées, effectuées et restantes ? Contrairement à
    `/api/heures`, aucun semestre n'est sélectionné : les séances de toutes les
    années sont agrégées.
    """
    if not utilisateur.enseignant_id:
        raise HTTPException(403, "Espace réservé aux enseignants.")
    enseignant = db.get(Enseignant, utilisateur.enseignant_id)
    if enseignant is None:
        raise HTTPException(404, "Enseignant introuvable")

    seances = (
        db.query(Seance)
        .options(
            joinedload(Seance.ecue).joinedload(ECUE.ue),
            joinedload(Seance.semestre),
            joinedload(Seance.creneau),
        )
        .filter(
            Seance.enseignant_id == utilisateur.enseignant_id,
            Seance.statut != "annulee",
        )
        .all()
    )

    # Tous les ECUE affectés à l'enseignant, même ceux dont les séances ne sont
    # pas encore générées : le suivi global doit rester exhaustif.
    affectations = (
        db.query(Affectation)
        .options(
            joinedload(Affectation.ecue).joinedload(ECUE.ue),
            joinedload(Affectation.semestre),
            joinedload(Affectation.groupe),
        )
        .filter(Affectation.enseignant_id == utilisateur.enseignant_id)
        .all()
    )

    # Les volumes déclarés (affectations) priment sur le type des séances.
    par_ecue: dict[tuple[int, Optional[int]], dict] = {}
    affectations_par_ecue: dict[tuple[int, Optional[int]], list[Affectation]] = {}
    semestres_vus: dict[int, Semestre] = {}
    for affectation in affectations:
        ecue = affectation.ecue
        if ecue is None:
            continue
        semestre = affectation.semestre or ecue.semestre
        cle = (ecue.id, semestre.id if semestre else None)
        par_ecue.setdefault(cle, _entree_ecue(ecue, semestre))
        affectations_par_ecue.setdefault(cle, []).append(affectation)
        if semestre is not None:
            semestres_vus[semestre.id] = semestre

    for cle, groupe_affectations in affectations_par_ecue.items():
        _ajouter_volumes_declares(par_ecue[cle], groupe_affectations)

    for seance in seances:
        ecue = seance.ecue
        if ecue is None:
            continue
        semestre = seance.semestre or ecue.semestre
        cle = (ecue.id, semestre.id if semestre else None)
        entree = par_ecue.setdefault(cle, _entree_ecue(ecue, semestre))
        _ajouter_seance_sans_affectation(entree, seance)
        if semestre is not None:
            # Le semestre de la séance fait foi : une affectation ancienne ne
            # doit pas faire apparaître l'ECUE dans la mauvaise année.
            entree["semestre_id"] = semestre.id
            entree["semestre"] = semestre.nom
            entree["annee"] = semestre.annee
            semestres_vus[semestre.id] = semestre
        if seance.statut == "effectuee":
            entree["effectuees"] += seance.duree

    ecues = []
    for entree in par_ecue.values():
        entree.pop("_declare", None)
        entree["cm"] = round(entree["cm"], 1)
        entree["td"] = round(entree["td"], 1)
        entree["tp"] = round(entree["tp"], 1)
        entree["planifiees"] = round(entree["planifiees"], 1)
        entree["effectuees"] = round(entree["effectuees"], 1)
        entree["totales"] = entree["planifiees"]
        entree["restantes"] = round(
            max(0.0, entree["planifiees"] - entree["effectuees"]), 1
        )
        ecues.append(entree)
    ecues.sort(
        key=lambda e: (
            e["annee"],
            e["semestre"] or "",
            e["code"],
        )
    )

    # Agrégat par semestre : les volumes déclarés des ECUE, pas la durée des
    # séances (une séance peut être un CM mutualisé ou un type par défaut).
    par_semestre: dict[int, dict] = {}
    for semestre_id, semestre in semestres_vus.items():
        par_semestre[semestre_id] = {
            "semestre_id": semestre.id,
            "nom": semestre.nom,
            "annee": semestre.annee,
            "date_debut": semestre.date_debut,
            "planifiees": 0.0,
            "effectuees": 0.0,
        }
    for entree in ecues:
        agregat = par_semestre.get(entree["semestre_id"])
        if agregat is None:
            continue
        agregat["planifiees"] += entree["planifiees"]
        agregat["effectuees"] += entree["effectuees"]

    semestres = []
    for agregat in par_semestre.values():
        agregat["planifiees"] = round(agregat["planifiees"], 1)
        agregat["effectuees"] = round(agregat["effectuees"], 1)
        agregat["restantes"] = round(
            max(0.0, agregat["planifiees"] - agregat["effectuees"]), 1
        )
        semestres.append(agregat)
    semestres.sort(key=lambda s: (s["annee"], s["date_debut"] or s["semestre_id"]))
    for agregat in semestres:
        agregat.pop("date_debut", None)

    # Répartition par année universitaire, semestres impairs et pairs.
    parites: dict[str, dict] = {}
    for agregat in semestres:
        numero = _numero_semestre(agregat.get("nom"))
        if numero is None:
            continue
        parite = "impairs" if numero % 2 else "pairs"
        annee = agregat.get("annee") or ""
        entree = parites.setdefault(
            annee,
            {
                "annee": annee,
                "impairs": {
                    "semestres": 0,
                    "planifiees": 0.0,
                    "effectuees": 0.0,
                },
                "pairs": {
                    "semestres": 0,
                    "planifiees": 0.0,
                    "effectuees": 0.0,
                },
            },
        )
        groupe = entree[parite]
        groupe["semestres"] += 1
        groupe["planifiees"] += agregat["planifiees"]
        groupe["effectuees"] += agregat["effectuees"]
    annees_parite = []
    for annee in sorted(parites, reverse=True):
        entree = parites[annee]
        for parite in ("impairs", "pairs"):
            groupe = entree[parite]
            groupe["planifiees"] = round(groupe["planifiees"], 1)
            groupe["effectuees"] = round(groupe["effectuees"], 1)
            groupe["restantes"] = round(
                max(0.0, groupe["planifiees"] - groupe["effectuees"]), 1
            )
        annees_parite.append(entree)

    total_planifiees = round(sum(e["planifiees"] for e in ecues), 1)
    total_effectuees = round(sum(e["effectuees"] for e in ecues), 1)
    total_restantes = round(max(0.0, total_planifiees - total_effectuees), 1)
    return {
        "enseignant": {
            "id": enseignant.id,
            "nom": enseignant.nom_affichage,
            "email": enseignant.email,
            "heures_max": enseignant.heures_max,
        },
        "totaux": {
            "ecues": len(ecues),
            "semestres": len(semestres),
            "planifiees": total_planifiees,
            "effectuees": total_effectuees,
            "restantes": total_restantes,
            "taux": round(total_effectuees / total_planifiees * 100, 1)
            if total_planifiees
            else 0,
        },
        "semestres": semestres,
        "parites": annees_parite,
        "ecues": ecues,
    }


@router.get("")
def rapport_heures(
    semestre_id: Optional[int] = Query(None),
    enseignant_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    semestre = db.get(Semestre, semestre_id) if semestre_id else db.query(Semestre).filter(Semestre.actif.is_(True)).first()
    if not semestre:
        semestre = db.query(Semestre).first()
    if not semestre:
        raise HTTPException(404, "Aucun semestre configuré")

    if utilisateur.role == ROLE_ENSEIGNANT:
        if not utilisateur.enseignant_id:
            return {"semestre": semestre.nom, "lignes": [], "totaux": {}}
        enseignant_id = utilisateur.enseignant_id

    requete_affectations = (
        db.query(Affectation)
        .options(
            joinedload(Affectation.ecue).joinedload(ECUE.ue),
            joinedload(Affectation.semestre),
            joinedload(Affectation.groupe),
        )
        .filter(Affectation.semestre_id == semestre.id)
    )
    if enseignant_id:
        requete_affectations = requete_affectations.filter(
            Affectation.enseignant_id == enseignant_id
        )
    affectations = requete_affectations.all()

    requete = db.query(Seance).filter(
        Seance.semestre_id == semestre.id, Seance.statut != "annulee"
    )
    if enseignant_id:
        requete = requete.filter(Seance.enseignant_id == enseignant_id)
    seances = requete.all()

    ids_enseignants = {s.enseignant_id for s in seances}
    ids_enseignants.update(a.enseignant_id for a in affectations)
    if enseignant_id:
        ids_enseignants.add(enseignant_id)
    enseignants = (
        db.query(Enseignant)
        .filter(Enseignant.id.in_(ids_enseignants))
        .order_by(Enseignant.nom, Enseignant.prenom)
        .all()
        if ids_enseignants
        else []
    )

    par_enseignant: dict[int, list[Seance]] = {}
    for seance in seances:
        par_enseignant.setdefault(seance.enseignant_id, []).append(seance)

    affectations_par_enseignant: dict[int, list[Affectation]] = {}
    for affectation in affectations:
        affectations_par_enseignant.setdefault(affectation.enseignant_id, []).append(
            affectation
        )

    lignes = []
    for enseignant in enseignants:
        ses_seances = par_enseignant.get(enseignant.id, [])
        ses_affectations = affectations_par_enseignant.get(enseignant.id, [])

        par_ecue: dict[int, dict] = {}

        def entree_ecue(ecue: ECUE) -> dict:
            return par_ecue.setdefault(
                ecue.id,
                {
                    "ecue_id": ecue.id,
                    "code": ecue.code,
                    "nom": ecue.nom,
                    "ue": ecue.ue_code,
                    "planifiees": 0.0,
                    "effectuees": 0.0,
                    "totales": 0.0,
                    "restantes": 0.0,
                    "cm": 0.0,
                    "td": 0.0,
                    "tp": 0.0,
                    "_declare": False,
                },
            )

        # 1) Volumes déclarés par les affectations (même sans séance générée).
        affectations_par_ecue: dict[int, list[Affectation]] = {}
        for affectation in ses_affectations:
            if affectation.ecue is None:
                continue
            affectations_par_ecue.setdefault(affectation.ecue_id, []).append(
                affectation
            )
        for groupe_affectations in affectations_par_ecue.values():
            entree = entree_ecue(groupe_affectations[0].ecue)
            _ajouter_volumes_declares(entree, groupe_affectations)

        # 2) Séances : heures effectuées, et volumes de repli sans affectation.
        for seance in ses_seances:
            ecue = seance.ecue
            if not ecue:
                continue
            entree = entree_ecue(ecue)
            _ajouter_seance_sans_affectation(entree, seance)
            if seance.statut == "effectuee":
                entree["effectuees"] += seance.duree

        detail = []
        for entree in sorted(par_ecue.values(), key=lambda e: e["code"]):
            entree.pop("_declare", None)
            entree["planifiees"] = round(entree["planifiees"], 1)
            entree["effectuees"] = round(entree["effectuees"], 1)
            # Pour un ECUE, les heures totales correspondent au volume planifié
            # pour cet enseignant ; les heures restantes sont celles qui restent
            # à effectuer.
            entree["totales"] = entree["planifiees"]
            entree["restantes"] = round(
                max(0.0, entree["planifiees"] - entree["effectuees"]), 1
            )
            detail.append(entree)

        planifiees = round(sum(e["planifiees"] for e in detail), 1)
        effectuees = round(sum(e["effectuees"] for e in detail), 1)

        lignes.append(
            {
                "enseignant_id": enseignant.id,
                "nom": enseignant.nom_affichage,
                "email": enseignant.email,
                "departement": enseignant.departement_nom,
                "heures_max": enseignant.heures_max,
                "planifiees": planifiees,
                "effectuees": effectuees,
                "reste_a_faire": round(max(0, planifiees - effectuees), 1),
                "marge": round(enseignant.heures_max - planifiees, 1),
                "taux": round(effectuees / planifiees * 100, 1) if planifiees else 0,
                "ecues": detail,
            }
        )

    total_planifiees = round(sum(l["planifiees"] for l in lignes), 1)
    total_effectuees = round(sum(l["effectuees"] for l in lignes), 1)
    return {
        "semestre": {"id": semestre.id, "nom": semestre.nom, "annee": semestre.annee},
        "lignes": lignes,
        "totaux": {
            "enseignants": len(lignes),
            "planifiees": total_planifiees,
            "effectuees": total_effectuees,
            "reste_a_faire": round(max(0, total_planifiees - total_effectuees), 1),
            "taux": round(total_effectuees / total_planifiees * 100, 1) if total_planifiees else 0,
        },
    }
