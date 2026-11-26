"""Suivi des heures effectuées et planifiées par enseignant."""
import re
from calendar import monthrange
from datetime import date, timedelta
from io import BytesIO
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
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


def annee_universitaire_courante() -> str:
    """Année universitaire en cours (septembre à août)."""
    aujourdhui = date.today()
    debut = aujourdhui.year if aujourdhui.month >= 9 else aujourdhui.year - 1
    return f"{debut}-{debut + 1}"


def _semestres_annee(db: Session, annee: Optional[str]) -> list[Semestre]:
    """Semestres d'une année universitaire, dans l'ordre chronologique."""
    annee_cible = annee or annee_universitaire_courante()
    return (
        db.query(Semestre)
        .filter(Semestre.annee == annee_cible)
        .order_by(Semestre.date_debut, Semestre.nom)
        .all()
    )


def semestres_periode(
    db: Session, annee: Optional[str], parite: str
) -> list[Semestre]:
    """Semestres impairs ou pairs d'une année universitaire.

    ``parite`` vaut « impairs » (1, 3, 5, 7, 9) ou « pairs » (2, 4, 6, 8,
    10). Sans année explicite, l'année universitaire courante est utilisée.
    """
    periode = (parite or "").strip().lower()
    if periode not in ("impairs", "pairs"):
        return []
    return [
        semestre
        for semestre in _semestres_annee(db, annee)
        if _numero_semestre(semestre.nom) is not None
        and (_numero_semestre(semestre.nom) % 2 == 1) == (periode == "impairs")
    ]


def semestres_numero(
    db: Session, annee: Optional[str], numero: int
) -> list[Semestre]:
    """Semestres portant le numéro ``numero`` pour une année universitaire.

    Plusieurs semestres peuvent partager un numéro (« Semestre 1 »,
    « Ingénieur 1 - Semestre 1 », « Master 1 - Semestre 1 ») : ils sont tous
    agrégés, comme la parité.
    """
    return [
        semestre
        for semestre in _semestres_annee(db, annee)
        if _numero_semestre(semestre.nom) == numero
    ]


def libelle_periode(
    annee: Optional[str],
    parite: Optional[str] = None,
    numero: Optional[int] = None,
) -> str:
    """Libellé lisible d'une période.

    Un numéro donne « Semestre 5 2026-2027 » ; une parité donne
    « Semestres impairs 2026-2027 ».
    """
    annee_cible = annee or annee_universitaire_courante()
    if numero is not None:
        return f"Semestre {numero} {annee_cible}"
    libelle = "impairs" if (parite or "").strip().lower() == "impairs" else "pairs"
    return f"Semestres {libelle} {annee_cible}"


def _rapport_vide(
    annee: Optional[str],
    *,
    parite: Optional[str] = None,
    numero: Optional[int] = None,
) -> dict:
    """Rapport sans ligne lorsqu'aucun semestre ne correspond aux filtres."""
    return {
        "semestre": None,
        "semestres": [],
        "annee": annee or annee_universitaire_courante(),
        "parite": parite,
        "semestre_numero": numero,
        "lignes": [],
        "totaux": {
            "enseignants": 0,
            "planifiees": 0,
            "effectuees": 0,
            "reste_a_faire": 0,
            "taux": 0,
        },
    }


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


def _annee_element(element) -> Optional[str]:
    """Année universitaire d'une séance ou d'une affectation.

    Le semestre de l'élément fait foi ; à défaut, on retombe sur celui de
    l'ECUE, comme le reste du calcul.
    """
    semestre = element.semestre or (element.ecue.semestre if element.ecue else None)
    return semestre.annee if semestre else None


@router.get("/global")
def rapport_heures_global(
    annee: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Totaux de tous les ECUE de l'enseignant.

    « Suivi global » répond à la question : sur l'ensemble de mes ECUE, combien
    d'heures sont planifiées, effectuées et restantes ? Contrairement à
    `/api/heures`, aucun semestre n'est sélectionné : les séances de toutes les
    années sont agrégées. Le paramètre `annee` limite le rapport à une seule
    année universitaire (par exemple « 2026-2027 »).
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

    # Restriction éventuelle à l'année universitaire courante : le suivi
    # global ne doit compter que les heures de cette année.
    if annee:
        seances = [s for s in seances if _annee_element(s) == annee]
        affectations = [a for a in affectations if _annee_element(a) == annee]

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
        annee_semestre = agregat.get("annee") or ""
        entree = parites.setdefault(
            annee_semestre,
            {
                "annee": annee_semestre,
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
    for annee_parite in sorted(parites, reverse=True):
        entree = parites[annee_parite]
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
        "annee": annee,
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


def lignes_heures(
    db: Session,
    semestres_cibles: list[Semestre],
    *,
    enseignant_id: Optional[int] = None,
) -> list[dict]:
    """Lignes du rapport d'heures, une par enseignant.

    Les heures planifiées viennent des volumes déclarés par les affectations
    (source de vérité, même sans séance générée) ; les heures effectuées des
    séances marquées « effectuée ». C'est le calcul partagé par l'API, les
    exports PDF/CSV et le tableau de bord, afin que tous affichent les mêmes
    volumes.
    """
    ids_semestres = [s.id for s in semestres_cibles]
    requete_affectations = (
        db.query(Affectation)
        .options(
            joinedload(Affectation.ecue).joinedload(ECUE.ue),
            joinedload(Affectation.semestre),
            joinedload(Affectation.groupe),
        )
        .filter(Affectation.semestre_id.in_(ids_semestres))
    )
    if enseignant_id:
        requete_affectations = requete_affectations.filter(
            Affectation.enseignant_id == enseignant_id
        )
    affectations = requete_affectations.all()

    requete = db.query(Seance).filter(
        Seance.semestre_id.in_(ids_semestres), Seance.statut != "annulee"
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
                "matricule": enseignant.matricule or "",
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
    return lignes


@router.get("")
def rapport_heures(
    semestre_id: Optional[int] = Query(None),
    semestre_numero: Optional[int] = Query(None, ge=1, le=10),
    enseignant_id: Optional[int] = Query(None),
    annee: Optional[str] = Query(None),
    parite: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Heures par enseignant, sur un semestre ou une période de semestres.

    ``semestre_numero=5`` agrège les semestres numéro 5 de ``annee`` (année
    universitaire courante par défaut). ``parite=impairs`` (ou ``pairs``)
    agrège tous les semestres de cette parité. Sans ``parite`` ni numéro, le
    comportement historique reste inchangé : un seul semestre. Priorité :
    ``semestre_id`` puis ``semestre_numero`` puis ``parite``.
    """
    periode = (parite or "").strip().lower()
    parite_demandee = periode in ("impairs", "pairs")
    numero_demande = semestre_numero

    if semestre_id is not None:
        semestre = db.get(Semestre, semestre_id) or db.query(Semestre).first()
        if not semestre:
            raise HTTPException(404, "Aucun semestre configuré")
        semestres_cibles = [semestre]
    elif numero_demande is not None:
        semestres_cibles = semestres_numero(db, annee, numero_demande)
        if not semestres_cibles:
            return _rapport_vide(annee, numero=numero_demande)
        semestre = semestres_cibles[0]
    elif parite_demandee:
        semestres_cibles = semestres_periode(db, annee, periode)
        if not semestres_cibles:
            return _rapport_vide(annee, parite=periode)
        semestre = semestres_cibles[0]
    else:
        semestre = (
            db.query(Semestre).filter(Semestre.actif.is_(True)).first()
            or db.query(Semestre).first()
        )
        if not semestre:
            raise HTTPException(404, "Aucun semestre configuré")
        semestres_cibles = [semestre]

    description_semestres = [
        {"id": s.id, "nom": s.nom, "annee": s.annee} for s in semestres_cibles
    ]
    annee_reponse = annee or semestre.annee

    if utilisateur.role == ROLE_ENSEIGNANT:
        if not utilisateur.enseignant_id:
            return {
                "semestre": {
                    "id": semestre.id,
                    "nom": semestre.nom,
                    "annee": semestre.annee,
                },
                "semestres": description_semestres,
                "annee": annee_reponse,
                "parite": periode if parite_demandee else None,
                "semestre_numero": numero_demande,
                "lignes": [],
                "totaux": {},
            }
        enseignant_id = utilisateur.enseignant_id

    lignes = lignes_heures(db, semestres_cibles, enseignant_id=enseignant_id)

    total_planifiees = round(sum(l["planifiees"] for l in lignes), 1)
    total_effectuees = round(sum(l["effectuees"] for l in lignes), 1)
    return {
        "semestre": {"id": semestre.id, "nom": semestre.nom, "annee": semestre.annee},
        "semestres": description_semestres,
        "annee": annee_reponse,
        "parite": periode if parite_demandee else None,
        "semestre_numero": numero_demande,
        "lignes": lignes,
        "totaux": {
            "enseignants": len(lignes),
            "planifiees": total_planifiees,
            "effectuees": total_effectuees,
            "reste_a_faire": round(max(0, total_planifiees - total_effectuees), 1),
            "taux": round(total_effectuees / total_planifiees * 100, 1) if total_planifiees else 0,
        },
    }


def _date_reelle_seance(seance: Seance) -> date | None:
    semestre = seance.semestre
    creneau = seance.creneau
    if semestre is None or creneau is None or semestre.date_debut is None:
        return None
    semaine = max(1, seance.semaine or 1)
    jour = creneau.jour or 0
    return semestre.date_debut + timedelta(days=(semaine - 1) * 7 + jour)


def _mois_libelle(mois: int) -> str:
    noms = [
        "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
        "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre",
    ]
    return noms[mois - 1] if 1 <= mois <= 12 else str(mois)


def _lignes_mensuelles(db: Session, mois: int, annee: int, enseignant_id: int | None = None) -> list[dict]:
    requete = (
        db.query(Seance)
        .options(
            joinedload(Seance.semestre),
            joinedload(Seance.creneau),
            joinedload(Seance.ecue).joinedload(ECUE.ue),
            joinedload(Seance.enseignant),
        )
        .filter(Seance.statut != "annulee")
    )
    if enseignant_id:
        requete = requete.filter(Seance.enseignant_id == enseignant_id)
    seances = requete.all()

    par_enseignant: dict[int, dict] = {}
    for seance in seances:
        date_seance = _date_reelle_seance(seance)
        if date_seance is None or date_seance.year != annee or date_seance.month != mois:
            continue
        enseignant = seance.enseignant
        if enseignant is None:
            continue
        entree = par_enseignant.setdefault(
            enseignant.id,
            {
                "enseignant_id": enseignant.id,
                "matricule": enseignant.matricule or "",
                "nom": enseignant.nom or "",
                "prenom": enseignant.prenom or "",
                "nom_complet": enseignant.nom_affichage,
                "email": enseignant.email or "",
                "departement": enseignant.departement_nom,
                "heures_max": enseignant.heures_max,
                "planifiees": 0.0,
                "effectuees": 0.0,
                "ecues": {},
            },
        )
        duree = float(seance.duree or 0)
        entree["planifiees"] += duree
        if seance.statut == "effectuee":
            entree["effectuees"] += duree
        ecue = seance.ecue
        if ecue is not None:
            detail = entree["ecues"].setdefault(
                ecue.id,
                {
                    "ecue_id": ecue.id,
                    "code": ecue.code,
                    "nom": ecue.nom,
                    "ue": ecue.ue_code,
                    "planifiees": 0.0,
                    "effectuees": 0.0,
                },
            )
            detail["planifiees"] += duree
            if seance.statut == "effectuee":
                detail["effectuees"] += duree

    # Inclure les enseignants sans séance dans le mois pour l'admin/liste
    if enseignant_id is None:
        enseignants = db.query(Enseignant).order_by(Enseignant.nom, Enseignant.prenom).all()
        for enseignant in enseignants:
            par_enseignant.setdefault(
                enseignant.id,
                {
                    "enseignant_id": enseignant.id,
                    "matricule": enseignant.matricule or "",
                    "nom": enseignant.nom or "",
                    "prenom": enseignant.prenom or "",
                    "nom_complet": enseignant.nom_affichage,
                    "email": enseignant.email or "",
                    "departement": enseignant.departement_nom,
                    "heures_max": enseignant.heures_max,
                    "planifiees": 0.0,
                    "effectuees": 0.0,
                    "ecues": {},
                },
            )
    elif enseignant_id not in par_enseignant:
        enseignant = db.get(Enseignant, enseignant_id)
        if enseignant is not None:
            par_enseignant[enseignant_id] = {
                "enseignant_id": enseignant.id,
                "matricule": enseignant.matricule or "",
                "nom": enseignant.nom or "",
                "prenom": enseignant.prenom or "",
                "nom_complet": enseignant.nom_affichage,
                "email": enseignant.email or "",
                "departement": enseignant.departement_nom,
                "heures_max": enseignant.heures_max,
                "planifiees": 0.0,
                "effectuees": 0.0,
                "ecues": {},
            }

    lignes = []
    for entree in par_enseignant.values():
        ecues = []
        for detail in entree["ecues"].values():
            detail["planifiees"] = round(detail["planifiees"], 1)
            detail["effectuees"] = round(detail["effectuees"], 1)
            detail["restantes"] = round(max(0.0, detail["planifiees"] - detail["effectuees"]), 1)
            ecues.append(detail)
        ecues.sort(key=lambda e: e["code"])
        planifiees = round(entree["planifiees"], 1)
        effectuees = round(entree["effectuees"], 1)
        lignes.append(
            {
                "enseignant_id": entree["enseignant_id"],
                "matricule": entree["matricule"],
                "nom": entree["nom"],
                "prenom": entree["prenom"],
                "nom_complet": entree["nom_complet"],
                "email": entree["email"],
                "departement": entree["departement"],
                "heures_max": entree["heures_max"],
                "planifiees": planifiees,
                "effectuees": effectuees,
                "reste_a_faire": round(max(0.0, planifiees - effectuees), 1),
                "taux": round(effectuees / planifiees * 100, 1) if planifiees else 0,
                "ecues": ecues,
            }
        )
    lignes.sort(key=lambda l: (l["nom"].lower(), l["prenom"].lower(), l["matricule"]))
    return lignes


@router.get("/mensuel")
def rapport_mensuel_heures(
    mois: int = Query(..., ge=1, le=12),
    annee: int = Query(..., ge=2000, le=2100),
    enseignant_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if utilisateur.role == ROLE_ENSEIGNANT:
        if not utilisateur.enseignant_id:
            raise HTTPException(403, "Compte enseignant non lié.")
        enseignant_id = utilisateur.enseignant_id
    elif utilisateur.role not in ("admin", "gestionnaire"):
        raise HTTPException(403, "Accès réservé à l'administration et aux enseignants.")

    lignes = _lignes_mensuelles(db, mois, annee, enseignant_id)
    total_planifiees = round(sum(l["planifiees"] for l in lignes), 1)
    total_effectuees = round(sum(l["effectuees"] for l in lignes), 1)
    return {
        "mois": mois,
        "annee": annee,
        "libelle_mois": _mois_libelle(mois),
        "lignes": lignes,
        "totaux": {
            "enseignants": len(lignes),
            "planifiees": total_planifiees,
            "effectuees": total_effectuees,
            "reste_a_faire": round(max(0.0, total_planifiees - total_effectuees), 1),
            "taux": round(total_effectuees / total_planifiees * 100, 1) if total_planifiees else 0,
        },
    }


@router.get("/mensuel/export")
def export_mensuel_heures(
    mois: int = Query(..., ge=1, le=12),
    annee: int = Query(..., ge=2000, le=2100),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if utilisateur.role not in ("admin", "gestionnaire"):
        raise HTTPException(403, "Accès réservé à l'administration.")
    lignes = _lignes_mensuelles(db, mois, annee, None)
    libelle_mois = _mois_libelle(mois)

    classeur = Workbook()
    feuille = classeur.active
    feuille.title = "Relevé mensuel"
    entetes = [
        "Matricule", "Prénom", "Nom", "Département",
        "Heures totales", "Heures effectuées", "Heures restantes", "Taux (%)",
    ]
    feuille.append(entetes)
    header_fill = PatternFill("solid", fgColor="1E3A8A")
    header_font = Font(bold=True, color="FFFFFF")
    for cell in feuille[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")
    for ligne in lignes:
        feuille.append([
            ligne["matricule"],
            ligne["prenom"],
            ligne["nom"],
            ligne["departement"],
            ligne["planifiees"],
            ligne["effectuees"],
            ligne["reste_a_faire"],
            ligne["taux"],
        ])
    for col in ["A", "B", "C", "D", "E", "F", "G", "H"]:
        feuille.column_dimensions[col].width = 18
    feuille.column_dimensions["D"].width = 28
    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    nom = f"releve_mensuel_heures_{annee}_{mois:02d}.xlsx"
    return StreamingResponse(
        flux,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )
