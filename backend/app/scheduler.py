"""Générateur automatique d'emplois du temps et contrôle des conflits."""
import math
from collections import defaultdict
from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from .models import Affectation, Creneau, Enseignant, Groupe, Salle, Seance, Semestre

JOURS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
TYPES_HEURES = {"CM": "heures_cm", "TD": "heures_td", "TP": "heures_tp"}


def _occupations(db: Session, semestre_id: int):
    enseignant = defaultdict(set)
    salle = defaultdict(set)
    groupe = defaultdict(set)
    seances = db.query(Seance).filter(Seance.semestre_id == semestre_id).all()
    for seance in seances:
        cle = (seance.semaine, seance.creneau_id)
        enseignant[cle].add(seance.enseignant_id)
        if seance.salle_id:
            salle[cle].add(seance.salle_id)
        for g in seance.groupes:
            groupe[cle].add(g.id)
    return enseignant, salle, groupe, seances


def conflits(
    db: Session,
    *,
    semestre_id: int,
    semaine: int,
    creneau_id: int,
    enseignant_id: int,
    salle_id: Optional[int],
    groupe_ids: list[int],
    ignorer_id: Optional[int] = None,
) -> list[str]:
    """Retourne la liste des conflits détectés pour une séance."""
    if not groupe_ids:
        return ["Au moins un groupe doit être sélectionné."]

    requete = db.query(Seance).filter(
        Seance.semestre_id == semestre_id,
        Seance.semaine == semaine,
        Seance.creneau_id == creneau_id,
    )
    if ignorer_id:
        requete = requete.filter(Seance.id != ignorer_id)

    messages: list[str] = []
    for autre in requete.all():
        if autre.enseignant_id == enseignant_id:
            messages.append("L'enseignant a déjà une séance sur ce créneau.")
        if salle_id and autre.salle_id == salle_id:
            messages.append("La salle est déjà occupée sur ce créneau.")
        communes = set(groupe_ids) & {g.id for g in autre.groupes}
        if communes:
            noms = ", ".join(
                g.nom for g in db.query(Groupe).filter(Groupe.id.in_(communes)).all()
            )
            messages.append(f"Conflit de groupe : {noms} ont déjà cours sur ce créneau.")
    return sorted(set(messages))


def verifier_conflits(db: Session, **kwargs):
    messages = conflits(db, **kwargs)
    if messages:
        raise HTTPException(409, " ".join(messages))


def _heures_affectation(affectation: Affectation, type_seance: str) -> int:
    champ = TYPES_HEURES[type_seance]
    valeur = getattr(affectation, champ) or 0
    total = (affectation.heures_cm or 0) + (affectation.heures_td or 0) + (affectation.heures_tp or 0)
    if total == 0 and affectation.ecue:
        return getattr(affectation.ecue, champ) or 0
    return valeur


def _salles_disponibles(db: Session, effectif: int, type_seance: str) -> list[Salle]:
    salles = db.query(Salle).filter(Salle.capacite >= effectif).all()
    if not salles:
        salles = db.query(Salle).all()

    def priorite(salle: Salle):
        if type_seance == "TP":
            prefere = "labo" in (salle.type_salle or "").lower()
        elif type_seance == "CM":
            prefere = "amphi" in (salle.type_salle or "").lower()
        else:
            prefere = "td" in (salle.type_salle or "").lower()
        return (0 if prefere else 1, abs((salle.capacite or 0) - effectif), salle.nom)

    return sorted(salles, key=priorite)


def generer_planning(db: Session, semestre_id: int, remplacer: bool = True) -> dict:
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise HTTPException(404, "Semestre introuvable")

    if remplacer:
        db.query(Seance).filter(
            Seance.semestre_id == semestre_id, Seance.verrouillee.is_(False)
        ).delete(synchronize_session=False)
        db.commit()

    occupations_enseignant, occupations_salle, occupations_groupe, _ = _occupations(db, semestre_id)
    creneaux = db.query(Creneau).order_by(Creneau.jour, Creneau.debut).all()
    if not creneaux:
        raise HTTPException(400, "Aucun créneau n'est défini. Ajoutez des créneaux avant de générer.")

    affectations = [
        a
        for a in db.query(Affectation)
        .filter(Affectation.semestre_id == semestre_id)
        .all()
        if a.ecue and a.enseignant
    ]
    if not affectations:
        return {
            "crees": 0,
            "non_placees": [],
            "message": "Aucune affectation pour ce semestre. Ajoutez des affectations enseignant / ECUE / groupe.",
        }

    taches: list[dict] = []
    cm_communs: dict[tuple[int, int], list[Affectation]] = defaultdict(list)
    for affectation in affectations:
        if affectation.cm_commun and affectation.ecue and affectation.groupe:
            cm_communs[(affectation.ecue_id, affectation.groupe.niveau_id)].append(affectation)

    deja_traitees: set[int] = set()
    for (ecue_id, _niveau_id), groupe_affectations in cm_communs.items():
        heures = max(_heures_affectation(a, "CM") for a in groupe_affectations)
        if heures <= 0:
            continue
        ids = [a.id for a in groupe_affectations]
        deja_traitees.update(ids)
        taches.append(
            {
                "affectation": groupe_affectations[0],
                "ecue_id": ecue_id,
                "enseignant_id": groupe_affectations[0].enseignant_id,
                "groupes": [a.groupe for a in groupe_affectations],
                "type": "CM",
                "heures": heures,
                "commun": True,
            }
        )

    for affectation in affectations:
        if affectation.id in deja_traitees:
            continue
        for type_seance in ("CM", "TD", "TP"):
            if affectation.cm_commun and type_seance == "CM":
                continue
            heures = _heures_affectation(affectation, type_seance)
            if heures <= 0:
                continue
            taches.append(
                {
                    "affectation": affectation,
                    "ecue_id": affectation.ecue_id,
                    "enseignant_id": affectation.enseignant_id,
                    "groupes": [affectation.groupe],
                    "type": type_seance,
                    "heures": heures,
                    "commun": False,
                }
            )

    # Les tâches les plus lourdes d'abord, puis les CM communs.
    taches.sort(key=lambda t: (t["type"] != "CM", -t["heures"]))

    crees = 0
    non_placees: list[dict] = []
    semaine_depart = 0

    for index_tache, tache in enumerate(taches):
        affectation: Affectation = tache["affectation"]
        effectif = max((g.effectif or 0) for g in tache["groupes"]) if tache["groupes"] else 0
        salles = _salles_disponibles(db, effectif, tache["type"])
        if not salles:
            non_placees.append(
                {
                    "ecue": affectation.ecue.code if affectation.ecue else "?",
                    "groupes": ", ".join(g.nom for g in tache["groupes"]),
                    "type": tache["type"],
                    "heures": tache["heures"],
                    "raison": "Aucune salle disponible",
                }
            )
            continue

        duree = 2.0
        nb_seances = max(1, math.ceil(tache["heures"] / duree))
        placees = 0
        tentatives = 0
        max_tentatives = semestre.semaines * len(creneaux) * 2 + 50

        while placees < nb_seances and tentatives < max_tentatives:
            semaine = (semaine_depart + tentatives // len(creneaux)) % semestre.semaines + 1
            creneau = creneaux[(index_tache + tentatives) % len(creneaux)]
            tentatives += 1
            cle = (semaine, creneau.id)

            if tache["enseignant_id"] in occupations_enseignant[cle]:
                continue
            if any(g.id in occupations_groupe[cle] for g in tache["groupes"]):
                continue

            salle_choisie = next((s for s in salles if s.id not in occupations_salle[cle]), None)
            if not salle_choisie:
                continue

            seance = Seance(
                semestre_id=semestre_id,
                semaine=semaine,
                creneau_id=creneau.id,
                salle_id=salle_choisie.id,
                enseignant_id=tache["enseignant_id"],
                ecue_id=tache["ecue_id"],
                affectation_id=None if tache["commun"] else affectation.id,
                type_seance=tache["type"],
                statut="planifiee",
                verrouillee=False,
                notes="CM commun" if tache["commun"] else "",
                groupes=list(tache["groupes"]),
            )
            db.add(seance)
            occupations_enseignant[cle].add(tache["enseignant_id"])
            occupations_salle[cle].add(salle_choisie.id)
            for g in tache["groupes"]:
                occupations_groupe[cle].add(g.id)
            crees += 1
            placees += 1

        if placees < nb_seances:
            non_placees.append(
                {
                    "ecue": affectation.ecue.code if affectation.ecue else "?",
                    "groupes": ", ".join(g.nom for g in tache["groupes"]),
                    "type": tache["type"],
                    "heures": tache["heures"],
                    "raison": f"{nb_seances - placees} séance(s) non placée(s) faute de créneau libre",
                }
            )
        semaine_depart = (semaine_depart + 1) % max(1, semestre.semaines)

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise

    message = f"{crees} séance(s) générée(s)."
    if non_placees:
        message += f" {len(non_placees)} affectation(s) partiellement ou non placée(s)."
    return {"crees": crees, "non_placees": non_placees, "message": message}
