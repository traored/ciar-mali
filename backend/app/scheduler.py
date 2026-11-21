"""Générateur automatique d'emplois du temps et contrôle des conflits."""
import math
from collections import Counter, defaultdict
from datetime import date, timedelta
from typing import Optional

from fastapi import HTTPException
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session, joinedload, selectinload

from .models import Affectation, Creneau, Enseignant, Groupe, Salle, Seance, Semestre

JOURS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
TYPES_HEURES = {"CM": "heures_cm", "TD": "heures_td", "TP": "heures_tp"}


def lundi_semaine(semestre: Semestre, semaine: int) -> date:
    """Lundi de la semaine ``semaine`` du semestre (1 = première semaine).

    Les semestres ne démarrent pas tous le même jour (le semestre 7 commence
    par exemple cinq semaines après le semestre 1). Ramener chaque semaine à
    son lundi permet de comparer deux semestres sur la même semaine civile :
    deux séances sont simultanées si elles tombent sur le même lundi et le
    même créneau.
    """
    debut = semestre.date_debut or date.today()
    lundi_debut = debut - timedelta(days=debut.weekday())
    return lundi_debut + timedelta(weeks=max(0, int(semaine or 1) - 1))


def _semaines_par_lundi(
    db: Session, lundi_cible: date, semestres: Optional[list[Semestre]] = None
) -> dict[int, int]:
    """Numéro de semaine de chaque semestre pour ce lundi civil."""
    if semestres is None:
        semestres = db.query(Semestre).all()
    correspondances: dict[int, int] = {}
    for semestre in semestres:
        delta = (lundi_cible - lundi_semaine(semestre, 1)).days
        if delta < 0 or delta % 7:
            continue
        numero = delta // 7 + 1
        if 1 <= numero <= (semestre.semaines or 0):
            correspondances[semestre.id] = numero
    return correspondances


def _seances_meme_moment(
    db: Session,
    semestre: Semestre,
    semaine: int,
    creneau_id: int,
    *,
    ignorer_id: Optional[int] = None,
) -> list[Seance]:
    """Séances de tous les semestres occupant le même créneau la même semaine.

    La comparaison se fait sur la semaine civile (lundi + numéro de semaine),
    pas sur le seul ``semestre_id`` : deux niveaux différents suivent deux
    semestres différents mais peuvent se retrouver dans la même salle au même
    moment.
    """
    lundi_cible = lundi_semaine(semestre, semaine)
    correspondances = _semaines_par_lundi(db, lundi_cible)
    if not correspondances:
        return []
    conditions = [
        and_(Seance.semestre_id == semestre_id, Seance.semaine == numero)
        for semestre_id, numero in correspondances.items()
    ]
    requete = (
        db.query(Seance)
        .options(
            joinedload(Seance.salle),
            joinedload(Seance.enseignant),
            joinedload(Seance.ecue),
            selectinload(Seance.groupes),
        )
        .filter(
            Seance.creneau_id == creneau_id,
            Seance.statut != "annulee",
            or_(*conditions),
        )
    )
    if ignorer_id:
        requete = requete.filter(Seance.id != ignorer_id)
    return requete.all()


def _occupations(db: Session, semestre_id: Optional[int] = None):
    """Occupation des enseignants, salles et groupes par semaine civile.

    Tous les semestres sont pris en compte : une salle occupée par un niveau
    ne peut pas accueillir un autre niveau au même moment, même si les deux
    suivent des semestres distincts.
    """
    enseignant = defaultdict(set)
    salle = defaultdict(set)
    groupe = defaultdict(set)
    semestres = {s.id: s for s in db.query(Semestre).all()}
    seances = (
        db.query(Seance)
        .options(selectinload(Seance.groupes))
        .filter(Seance.statut != "annulee")
        .all()
    )
    for seance in seances:
        semestre = semestres.get(seance.semestre_id)
        if not semestre:
            continue
        cle = (lundi_semaine(semestre, seance.semaine), seance.creneau_id)
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
    """Retourne la liste des conflits détectés pour une séance.

    Le contrôle couvre tous les semestres dont la semaine civile recouvre
    celle de la séance : une salle, un enseignant ou un groupe ne peut pas
    être mobilisé deux fois au même moment, même dans deux niveaux différents.
    """
    if not groupe_ids:
        return ["Au moins un groupe doit être sélectionné."]

    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        return ["Semestre introuvable."]

    autres = _seances_meme_moment(
        db, semestre, semaine, creneau_id, ignorer_id=ignorer_id
    )
    semestres = {s.id: s for s in db.query(Semestre).all()}
    creneau = db.get(Creneau, creneau_id)
    moment = ""
    if creneau:
        moment = f"{JOURS[creneau.jour]} {creneau.debut} - {creneau.fin}"

    messages: list[str] = []
    for autre in autres:
        semestre_autre = semestres.get(autre.semestre_id)
        contexte = (
            f"{semestre_autre.nom} · {semestre_autre.annee}"
            if semestre_autre
            else "un autre semestre"
        )
        ecue = autre.ecue.code if autre.ecue else ""
        enseignant = autre.enseignant.nom_affichage if autre.enseignant else ""
        salle = autre.salle.nom if autre.salle else ""
        if autre.enseignant_id == enseignant_id:
            messages.append(
                f"L'enseignant a déjà une séance dans {contexte} sur ce créneau"
                + (f" ({ecue}, {salle})." if ecue or salle else ".")
            )
        if salle_id and autre.salle_id == salle_id:
            messages.append(
                f"La salle {salle or 'sélectionnée'} est déjà occupée par "
                f"{contexte} sur ce créneau"
                + (f" ({ecue}, {enseignant})." if ecue or enseignant else ".")
            )
        communes = set(groupe_ids) & {g.id for g in autre.groupes}
        if communes:
            noms = ", ".join(
                g.nom for g in db.query(Groupe).filter(Groupe.id.in_(communes)).all()
            )
            messages.append(
                f"Conflit de groupe : {noms} ont déjà cours dans {contexte} "
                f"sur ce créneau" + (f" ({moment})." if moment else ".")
            )
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


def _salles_disponibles(
    db: Session,
    effectif: int,
    type_seance: str,
    salles: Optional[list[Salle]] = None,
) -> list[Salle]:
    if salles is None:
        salles = db.query(Salle).all()
    candidates = [s for s in salles if (s.capacite or 0) >= effectif] or list(salles)

    def priorite(salle: Salle):
        if type_seance == "TP":
            prefere = "labo" in (salle.type_salle or "").lower()
        elif type_seance == "CM":
            prefere = "amphi" in (salle.type_salle or "").lower()
        else:
            prefere = "td" in (salle.type_salle or "").lower()
        return (0 if prefere else 1, abs((salle.capacite or 0) - effectif), salle.nom)

    return sorted(candidates, key=priorite)


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
            cle = (lundi_semaine(semestre, semaine), creneau.id)

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


def _resume_seance(
    seance: Seance,
    semestres: dict[int, Semestre],
    creneaux: dict[int, Creneau],
) -> dict:
    """Version courte d'une séance pour les rapports de conflits."""
    semestre = semestres.get(seance.semestre_id)
    creneau = creneaux.get(seance.creneau_id)
    return {
        "id": seance.id,
        "semestre_id": seance.semestre_id,
        "semestre": f"{semestre.nom} · {semestre.annee}" if semestre else "",
        "semaine": seance.semaine,
        "creneau_id": seance.creneau_id,
        "creneau": (
            f"{JOURS[creneau.jour]} {creneau.debut} - {creneau.fin}" if creneau else ""
        ),
        "salle_id": seance.salle_id,
        "salle": seance.salle.nom if seance.salle else "",
        "enseignant_id": seance.enseignant_id,
        "enseignant": seance.enseignant.nom_affichage if seance.enseignant else "",
        "ecue": seance.ecue.code if seance.ecue else "",
        "ecue_nom": seance.ecue.nom if seance.ecue else "",
        "type_seance": seance.type_seance,
        "statut": seance.statut,
        "verrouillee": bool(seance.verrouillee),
        "deplacable": seance.statut == "planifiee" and not seance.verrouillee,
    }


def conflits_existants(
    db: Session, *, semestre_id: Optional[int] = None
) -> list[dict]:
    """Conflits actuellement présents, tous semestres confondus.

    Un conflit est signalé par ressource (salle, enseignant, groupe) et par
    semaine civile : deux séances de deux semestres différents qui tombent le
    même lundi au même créneau sont bien en conflit.
    """
    semestres = {s.id: s for s in db.query(Semestre).all()}
    creneaux = {c.id: c for c in db.query(Creneau).all()}
    groupes = {g.id: g for g in db.query(Groupe).all()}
    seances = (
        db.query(Seance)
        .options(
            selectinload(Seance.groupes),
            joinedload(Seance.salle),
            joinedload(Seance.enseignant),
            joinedload(Seance.ecue),
        )
        .filter(Seance.statut != "annulee")
        .all()
    )
    if semestre_id:
        seances = [s for s in seances if s.semestre_id == semestre_id]

    par_moment: dict[tuple[date, int], list[Seance]] = defaultdict(list)
    for seance in seances:
        semestre = semestres.get(seance.semestre_id)
        if semestre:
            par_moment[
                (lundi_semaine(semestre, seance.semaine), seance.creneau_id)
            ].append(seance)

    resultats: list[dict] = []
    for (lundi, creneau_id), lot in sorted(par_moment.items()):
        ressources: dict[str, dict[int, list[Seance]]] = {
            "salle": defaultdict(list),
            "enseignant": defaultdict(list),
            "groupe": defaultdict(list),
        }
        for seance in lot:
            if seance.salle_id:
                ressources["salle"][seance.salle_id].append(seance)
            ressources["enseignant"][seance.enseignant_id].append(seance)
            for groupe in seance.groupes:
                ressources["groupe"][groupe.id].append(seance)

        creneau = creneaux.get(creneau_id)
        moment = (
            f"{JOURS[creneau.jour]} {creneau.debut} - {creneau.fin}"
            if creneau
            else ""
        )
        for type_ressource, par_ressource in ressources.items():
            for ressource_id, groupe in par_ressource.items():
                if len(groupe) < 2:
                    continue
                if type_ressource == "salle":
                    nom = groupe[0].salle.nom if groupe[0].salle else str(ressource_id)
                elif type_ressource == "enseignant":
                    nom = (
                        groupe[0].enseignant.nom_affichage
                        if groupe[0].enseignant
                        else str(ressource_id)
                    )
                else:
                    nom = (
                        groupes[ressource_id].nom
                        if ressource_id in groupes
                        else str(ressource_id)
                    )
                resultats.append(
                    {
                        "type": type_ressource,
                        "ressource_id": ressource_id,
                        "ressource": nom,
                        "lundi": lundi.isoformat(),
                        "creneau_id": creneau_id,
                        "creneau": moment,
                        "seances": [
                            _resume_seance(seance, semestres, creneaux)
                            for seance in sorted(groupe, key=lambda s: s.id)
                        ],
                    }
                )
    return resultats


def reparer_conflits(
    db: Session, *, semestre_id: Optional[int] = None
) -> dict:
    """Déplace les séances planifiées en conflit vers une ressource libre.

    Une séance est d'abord déplacée vers une autre salle du même créneau,
    puis vers un autre créneau de la même semaine, et en dernier recours vers
    une autre semaine du semestre. Chaque cible est contrôlée avant la
    modification. Les séances verrouillées, effectuées ou annulées ne sont
    jamais déplacées.
    """
    semestres = {s.id: s for s in db.query(Semestre).all()}
    creneaux = {
        c.id: c
        for c in db.query(Creneau).order_by(Creneau.jour, Creneau.debut).all()
    }
    toutes_salles = db.query(Salle).all()
    seances = (
        db.query(Seance)
        .options(selectinload(Seance.groupes))
        .filter(Seance.statut != "annulee")
        .all()
    )
    if semestre_id:
        seances = [s for s in seances if s.semestre_id == semestre_id]

    compteurs: Counter = Counter()
    cles: dict[int, tuple[date, int]] = {}

    def ajouter(seance: Seance) -> None:
        semestre = semestres.get(seance.semestre_id)
        if not semestre:
            return
        cle = (lundi_semaine(semestre, seance.semaine), seance.creneau_id)
        cles[seance.id] = cle
        compteurs[(cle, "enseignant", seance.enseignant_id)] += 1
        if seance.salle_id:
            compteurs[(cle, "salle", seance.salle_id)] += 1
        for groupe in seance.groupes:
            compteurs[(cle, "groupe", groupe.id)] += 1

    def retirer(seance: Seance) -> None:
        cle = cles.get(seance.id)
        if not cle:
            return
        compteurs[(cle, "enseignant", seance.enseignant_id)] -= 1
        if seance.salle_id:
            compteurs[(cle, "salle", seance.salle_id)] -= 1
        for groupe in seance.groupes:
            compteurs[(cle, "groupe", groupe.id)] -= 1

    def libre(seance: Seance, cle: tuple[date, int], salle_id: Optional[int]) -> bool:
        if compteurs[(cle, "enseignant", seance.enseignant_id)]:
            return False
        if salle_id and compteurs[(cle, "salle", salle_id)]:
            return False
        return all(
            not compteurs[(cle, "groupe", groupe.id)] for groupe in seance.groupes
        )

    for seance in seances:
        ajouter(seance)

    deplacees: list[dict] = []
    non_reparables: list[dict] = []

    # Les séances les plus récentes sont déplacées en premier : les plus
    # anciennes (souvent verrouillées ou déjà effectuées) restent en place.
    ordre = sorted(
        [s for s in seances if s.statut == "planifiee" and not s.verrouillee],
        key=lambda s: s.id,
        reverse=True,
    )
    for seance in ordre:
        semestre = semestres.get(seance.semestre_id)
        if not semestre:
            continue
        retirer(seance)
        cle_actuelle = cles.get(seance.id)
        if cle_actuelle and libre(seance, cle_actuelle, seance.salle_id):
            ajouter(seance)
            continue

        effectif = (
            max((g.effectif or 0) for g in seance.groupes) if seance.groupes else 0
        )
        salles = _salles_disponibles(
            db, effectif, seance.type_seance, salles=toutes_salles
        )
        # Salles réellement dimensionnées pour l'effectif : on évite de
        # déplacer une promotion entière dans une salle trop petite. Si aucune
        # ne convient, on se rabat sur l'ensemble des salles.
        adaptees = [s for s in salles if not effectif or (s.capacite or 0) >= effectif]
        candidates = adaptees or salles
        # À créneau égal, on privilégie la salle habituelle de la séance.
        par_preference = sorted(
            candidates, key=lambda s: 0 if s.id == seance.salle_id else 1
        )
        trouve: Optional[tuple[int, int, int, str]] = None

        # 1) Même semaine et même créneau : changer de salle.
        for salle in adaptees:
            if salle.id == seance.salle_id:
                continue
            if cle_actuelle and libre(seance, cle_actuelle, salle.id):
                trouve = (seance.semaine, seance.creneau_id, salle.id, "salle")
                break

        # 2) Même semaine : changer de créneau, de préférence dans la même
        # salle pour ne pas déplacer aussi les étudiants.
        if not trouve:
            for creneau in creneaux.values():
                if creneau.id == seance.creneau_id:
                    continue
                cle = (lundi_semaine(semestre, seance.semaine), creneau.id)
                for salle in par_preference:
                    if libre(seance, cle, salle.id):
                        trouve = (seance.semaine, creneau.id, salle.id, "creneau")
                        break
                if trouve:
                    break

        # 3) Dernier recours : une autre semaine du semestre, la plus proche.
        if not trouve:
            semaines = sorted(
                [
                    numero
                    for numero in range(1, (semestre.semaines or 0) + 1)
                    if numero != seance.semaine
                ],
                key=lambda numero: (abs(numero - seance.semaine), numero),
            )
            for numero in semaines:
                lundi = lundi_semaine(semestre, numero)
                for creneau in creneaux.values():
                    cle = (lundi, creneau.id)
                    for salle in par_preference:
                        if libre(seance, cle, salle.id):
                            trouve = (numero, creneau.id, salle.id, "semaine")
                            break
                    if trouve:
                        break
                if trouve:
                    break

        if not trouve:
            ajouter(seance)
            non_reparables.append(_resume_seance(seance, semestres, creneaux))
            continue

        nouvelle_semaine, nouveau_creneau, nouvelle_salle, raison = trouve
        avant = _resume_seance(seance, semestres, creneaux)
        seance.semaine = nouvelle_semaine
        seance.creneau_id = nouveau_creneau
        seance.salle_id = nouvelle_salle
        # Les relations salle/créneau ont pu être chargées pour le rapport
        # « avant » : on les expire pour que le rapport « après » reflète la
        # nouvelle affectation et non l'ancienne encore en cache.
        db.flush()
        db.expire(seance, ["salle", "creneau"])
        ajouter(seance)
        deplacees.append(
            {
                "raison": raison,
                "avant": avant,
                "apres": _resume_seance(seance, semestres, creneaux),
            }
        )

    db.commit()
    restants = conflits_existants(db, semestre_id=semestre_id)
    return {
        "deplacees": len(deplacees),
        "non_reparables": non_reparables,
        "restants": len(restants),
        "details": deplacees,
        "conflits_restants": restants,
    }
