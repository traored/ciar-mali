"""Calculs des moyennes, crédits, compensations et statistiques de notes."""
import json
import re
import unicodedata
from datetime import date, datetime

from sqlalchemy.orm import Session, joinedload, selectinload

from .models import (
    ECUE,
    Etudiant,
    Evaluation,
    Groupe,
    Inscription,
    MENTIONS,
    Niveau,
    Note,
    Parametre,
    PointJuryECUE,
    PointJuryUE,
    ResultatSemestre,
    Seance,
    Semestre,
    UE,
)

COMPENSATION_ECUE = "compensation_ecue"
COMPENSATION_INTER_UE = "compensation_inter_ue"
PONDERATION_ECUE = "ponderation_ecue"
COEFFICIENT_DEVOIR = "coefficient_devoir"
COEFFICIENT_EXAMEN = "coefficient_examen"
SESSION2_MODE = "session2_mode"

MODES_SESSION2 = ("examen_remplace", "meilleure_note", "meilleure_moyenne")
MODE_SESSION2_DEFAUT = "meilleure_moyenne"
SIGNATAIRES_CLES = {
    "releve": "signataire_releve",
    "pv": "signataire_pv",
    "attestation": "signataire_attestation",
}
SIGNATAIRE_VIDE = {"prenom_nom": "", "grade": "", "fonction": ""}
GRADES_SIGNATAIRE = ("Professeur", "Maître de Conférences", "Maître Assistant", "Assistant")
FONCTIONS_SIGNATAIRE = (
    "Le Chef du Département de la formation",
    "La Directrice Générale",
    "Le Directeur Général",
    "Le Directeur Général Adjoint",
    "Le Président du jury",
)


def compensation_ecue(db: Session) -> bool:
    """Indique si la compensation entre ECUE d'une même UE est autorisée.

    Par défaut la compensation est activée : seule l'UE porte alors la mention
    « Validée », les ECUE ne sont pas validés individuellement.
    """
    parametre = db.get(Parametre, COMPENSATION_ECUE)
    if parametre is None:
        return True
    return parametre.actif


def definir_compensation_ecue(db: Session, actif: bool) -> bool:
    parametre = db.get(Parametre, COMPENSATION_ECUE)
    if parametre is None:
        parametre = Parametre(cle=COMPENSATION_ECUE)
        db.add(parametre)
    parametre.valeur = "1" if actif else "0"
    db.commit()
    return actif


def compensation_inter_ue(db: Session) -> bool:
    """Indique si la compensation entre UE est appliquée au semestre.

    Par défaut la compensation est activée : le semestre est validé dès que la
    moyenne pondérée des UE atteint 10. Lorsqu'elle est désactivée, chaque UE
    doit être validée individuellement pour valider le semestre.
    """
    parametre = db.get(Parametre, COMPENSATION_INTER_UE)
    if parametre is None:
        return True
    return parametre.actif


def definir_compensation_inter_ue(db: Session, actif: bool) -> bool:
    parametre = db.get(Parametre, COMPENSATION_INTER_UE)
    if parametre is None:
        parametre = Parametre(cle=COMPENSATION_INTER_UE)
        db.add(parametre)
    parametre.valeur = "1" if actif else "0"
    db.commit()
    return actif


def ponderation_ecue(db: Session) -> bool:
    """Indique si la moyenne des UE pondère les ECUE par leurs crédits.

    Par défaut la pondération est désactivée : la moyenne d'une UE est alors
    la moyenne simple des moyennes de ses ECUE, sans coefficient.
    """
    parametre = db.get(Parametre, PONDERATION_ECUE)
    if parametre is None:
        return False
    return parametre.actif


def definir_ponderation_ecue(db: Session, actif: bool) -> bool:
    parametre = db.get(Parametre, PONDERATION_ECUE)
    if parametre is None:
        parametre = Parametre(cle=PONDERATION_ECUE)
        db.add(parametre)
    parametre.valeur = "1" if actif else "0"
    db.commit()
    return actif


def coefficient_devoir(db: Session) -> float:
    """Coefficient appliqué aux devoirs et contrôles continus (1 par défaut)."""
    parametre = db.get(Parametre, COEFFICIENT_DEVOIR)
    if parametre is None:
        return 1.0
    try:
        return max(0.0, float(parametre.valeur))
    except (TypeError, ValueError):
        return 1.0


def definir_coefficient_devoir(db: Session, valeur: float) -> float:
    coefficient = round(max(0.0, float(valeur)), 2)
    parametre = db.get(Parametre, COEFFICIENT_DEVOIR)
    if parametre is None:
        parametre = Parametre(cle=COEFFICIENT_DEVOIR)
        db.add(parametre)
    parametre.valeur = str(coefficient)
    db.commit()
    return coefficient


def coefficient_examen(db: Session) -> float:
    """Coefficient appliqué aux examens (2 par défaut)."""
    parametre = db.get(Parametre, COEFFICIENT_EXAMEN)
    if parametre is None:
        return 2.0
    try:
        return max(0.0, float(parametre.valeur))
    except (TypeError, ValueError):
        return 2.0


def definir_coefficient_examen(db: Session, valeur: float) -> float:
    coefficient = round(max(0.0, float(valeur)), 2)
    parametre = db.get(Parametre, COEFFICIENT_EXAMEN)
    if parametre is None:
        parametre = Parametre(cle=COEFFICIENT_EXAMEN)
        db.add(parametre)
    parametre.valeur = str(coefficient)
    db.commit()
    return coefficient


def mode_session_2(db: Session) -> str:
    """Mode de calcul de la note finale d'un ECUE en session 2."""
    parametre = db.get(Parametre, SESSION2_MODE)
    if parametre is None or parametre.valeur not in MODES_SESSION2:
        return MODE_SESSION2_DEFAUT
    return parametre.valeur


def definir_mode_session_2(db: Session, mode: str) -> str:
    if mode not in MODES_SESSION2:
        raise ValueError("Mode de session 2 invalide")
    parametre = db.get(Parametre, SESSION2_MODE)
    if parametre is None:
        parametre = Parametre(cle=SESSION2_MODE)
        db.add(parametre)
    parametre.valeur = mode
    db.commit()
    return mode


class DonneesCalcul:
    """Instantané des données nécessaires aux calculs de notes.

    Le calcul d'un relevé enchaîne beaucoup de petites lectures (UE, ECUE,
    évaluations, notes, points jury). Sur une base distante comme Neon, chaque
    aller-retour coûte cher : cette classe charge tout en quelques requêtes et
    sert ensuite de cache pendant le calcul d'une année entière.
    """

    def __init__(self) -> None:
        self.compensation_ecue = True
        self.compensation_inter_ue = True
        self.ponderation_ecue = False
        self.coefficient_devoir = 1.0
        self.coefficient_examen = 2.0
        self.mode_session_2 = MODE_SESSION2_DEFAUT
        self.ues_par_semestre: dict[int, list[UE]] = {}
        self.ecues_par_ue: dict[int, list[ECUE]] = {}
        self.evaluations_par_ecue: dict[int, list[Evaluation]] = {}
        self.notes_par_inscription_ecue: dict[tuple[int, int], list[Note]] = {}
        self.points_jury_ue: dict[int, dict[int, float]] = {}
        self.points_jury_ecue: dict[int, dict[int, float]] = {}
        self.resultats: dict[tuple[int, int, int], ResultatSemestre] = {}


def precharger_donnees(
    db: Session,
    inscription_ids: list[int],
    semestre_ids: list[int],
) -> DonneesCalcul:
    """Charge en quelques requêtes tout ce qu'il faut pour calculer des résultats.

    Sans ce préchargement, un passage en classe supérieure déclenche plusieurs
    milliers de requêtes (une par ECUE et par note), ce qui dépasse largement
    le délai d'attente de l'interface sur une base distante.
    """
    donnees = DonneesCalcul()
    donnees.compensation_ecue = compensation_ecue(db)
    donnees.compensation_inter_ue = compensation_inter_ue(db)
    donnees.ponderation_ecue = ponderation_ecue(db)
    donnees.coefficient_devoir = coefficient_devoir(db)
    donnees.coefficient_examen = coefficient_examen(db)
    donnees.mode_session_2 = mode_session_2(db)

    semestres = sorted({int(sid) for sid in semestre_ids if sid is not None})
    ues: list[UE] = []
    if semestres:
        ues = (
            db.query(UE)
            .options(selectinload(UE.niveaux))
            .filter(UE.semestre_id.in_(semestres))
            .order_by(UE.code)
            .all()
        )
        for ue in ues:
            donnees.ues_par_semestre.setdefault(ue.semestre_id, []).append(ue)

    ecues: list[ECUE] = []
    if ues:
        ecues = (
            db.query(ECUE)
            .filter(ECUE.ue_id.in_([ue.id for ue in ues]))
            .order_by(ECUE.code)
            .all()
        )
        for ecue in ecues:
            donnees.ecues_par_ue.setdefault(ecue.ue_id, []).append(ecue)

    evaluations: list[Evaluation] = []
    if ecues:
        evaluations = (
            db.query(Evaluation)
            .filter(Evaluation.ecue_id.in_([ecue.id for ecue in ecues]))
            .order_by(Evaluation.session, Evaluation.nom)
            .all()
        )
        for evaluation in evaluations:
            donnees.evaluations_par_ecue.setdefault(evaluation.ecue_id, []).append(
                evaluation
            )

    if inscription_ids and evaluations:
        notes = (
            db.query(Note)
            .filter(
                Note.inscription_id.in_(inscription_ids),
                Note.evaluation_id.in_([evaluation.id for evaluation in evaluations]),
            )
            .all()
        )
        ecue_par_evaluation = {
            evaluation.id: evaluation.ecue_id for evaluation in evaluations
        }
        for note in notes:
            ecue_id = ecue_par_evaluation.get(note.evaluation_id)
            if ecue_id is None:
                continue
            donnees.notes_par_inscription_ecue.setdefault(
                (note.inscription_id, ecue_id), []
            ).append(note)

    if inscription_ids:
        for ligne in (
            db.query(PointJuryUE)
            .filter(PointJuryUE.inscription_id.in_(inscription_ids))
            .all()
        ):
            donnees.points_jury_ue.setdefault(ligne.inscription_id, {})[
                ligne.ue_id
            ] = float(ligne.points or 0)
        for ligne in (
            db.query(PointJuryECUE)
            .filter(PointJuryECUE.inscription_id.in_(inscription_ids))
            .all()
        ):
            donnees.points_jury_ecue.setdefault(ligne.inscription_id, {})[
                ligne.ecue_id
            ] = float(ligne.points or 0)
        if semestres:
            for resultat in (
                db.query(ResultatSemestre)
                .filter(
                    ResultatSemestre.inscription_id.in_(inscription_ids),
                    ResultatSemestre.semestre_id.in_(semestres),
                )
                .all()
            ):
                donnees.resultats[
                    (resultat.inscription_id, resultat.semestre_id, resultat.session)
                ] = resultat

    return donnees


def _lire_signataire(db: Session, cle: str) -> dict:
    parametre = db.get(Parametre, cle)
    resultat = dict(SIGNATAIRE_VIDE)
    if parametre is None or not parametre.valeur:
        return resultat
    try:
        donnees = json.loads(parametre.valeur)
    except (TypeError, ValueError):
        return resultat
    if isinstance(donnees, dict):
        for champ in SIGNATAIRE_VIDE:
            valeur = donnees.get(champ)
            resultat[champ] = str(valeur).strip() if valeur else ""
    return resultat


def lire_signataires(db: Session) -> dict:
    return {type_doc: _lire_signataire(db, cle) for type_doc, cle in SIGNATAIRES_CLES.items()}


def enregistrer_signataires(db: Session, donnees: dict) -> dict:
    for type_doc, cle in SIGNATAIRES_CLES.items():
        bloc = donnees.get(type_doc) if isinstance(donnees, dict) else None
        if bloc is None:
            continue
        if hasattr(bloc, "model_dump"):
            bloc = bloc.model_dump()
        propre = {champ: str(bloc.get(champ) or "").strip() for champ in SIGNATAIRE_VIDE}
        parametre = db.get(Parametre, cle)
        if parametre is None:
            parametre = Parametre(cle=cle)
            db.add(parametre)
        parametre.valeur = json.dumps(propre, ensure_ascii=False)
    db.commit()
    return lire_signataires(db)


def abreviation_grade(grade: str | None) -> str:
    grade = (grade or "").strip()
    if grade == "Professeur":
        return "Pr"
    if grade in ("Maître de Conférences", "Maître Assistant"):
        return "Dr"
    return ""


def libelle_signataire(signataire: dict | None) -> str:
    """Assemble « Prénom Nom » précédé de l'abréviation de grade."""
    if not signataire:
        return ""
    nom = (signataire.get("prenom_nom") or "").strip()
    if not nom:
        return ""
    abreviation = abreviation_grade(signataire.get("grade"))
    return f"{abreviation} {nom}".strip()


def mention_pour(moyenne: float | None) -> str:
    if moyenne is None:
        return ""
    for seuil, libelle in MENTIONS:
        if moyenne >= seuil:
            return libelle
    return "Insuffisant"


def statut_ecue(moyenne: float | None) -> str:
    if moyenne is None:
        return "En attente"
    return "Validé" if moyenne >= 10 else "Non validé"


def _appliquer_points_jury(moyenne: float | None, points: float | None) -> float | None:
    """Ajoute les points complémentaires du jury, dans la limite de 20/20."""
    if moyenne is None:
        return None
    return round(min(20.0, max(0.0, float(moyenne) + float(points or 0))), 2)


def _note_sur_20(note: Note | None) -> float | None:
    if note is None or note.absent or note.valeur is None:
        return None
    bareme = (note.evaluation.note_max if note.evaluation else 20) or 20
    return round(float(note.valeur) / bareme * 20, 2)


def notes_evaluation(db: Session, inscription_id: int, evaluation_id: int) -> Note | None:
    return (
        db.query(Note)
        .filter(Note.inscription_id == inscription_id, Note.evaluation_id == evaluation_id)
        .first()
    )


def _est_examen(evaluation: Evaluation | None) -> bool:
    return bool(evaluation) and (evaluation.type_evaluation or "").strip().lower() == "examen"


def _moyenne_ponderee(items: list[tuple[float, float, int, Note]]) -> float | None:
    total = sum(item[1] for item in items)
    if not total:
        return None
    return round(sum(item[0] * item[1] for item in items) / total, 2)


def _coefficient_evaluation(
    evaluation: Evaluation, coef_devoir: float, coef_examen: float
) -> float:
    """Coefficient appliqué à une évaluation selon son type."""
    type_evaluation = (evaluation.type_evaluation or "").strip().lower()
    if type_evaluation == "examen":
        return coef_examen
    if type_evaluation in ("devoir", "cc", "controle continu", "contrôle continu"):
        return coef_devoir
    return float(evaluation.coefficient or 1)


def _elements_notes(
    evaluations: list[Evaluation],
    notes_par_evaluation: dict[int, Note],
    coef_devoir: float,
    coef_examen: float,
) -> list[tuple[float, float, int, Note]]:
    elements = []
    for evaluation in evaluations:
        note = notes_par_evaluation.get(evaluation.id)
        sur_20 = _note_sur_20(note)
        if sur_20 is None:
            continue
        elements.append(
            (
                sur_20,
                _coefficient_evaluation(evaluation, coef_devoir, coef_examen),
                evaluation.id,
                note,
            )
        )
    return elements


def _cle_evaluation(note: Note) -> str:
    evaluation = note.evaluation
    return (evaluation.nom or "").strip().lower() if evaluation else ""


def moyenne_ecue(
    db: Session,
    inscription_id: int,
    ecue_id: int,
    semestre_id: int,
    session: int = 1,
    donnees: DonneesCalcul | None = None,
) -> dict:
    """Moyenne d'un ECUE, avec prise en compte de la session de rattrapage.

    La note de contrôle continu de la session 1 est conservée. La note finale
    de la session 2 dépend du paramétrage ``session2_mode``.

    Lorsque [donnees] est fourni, les évaluations, notes et paramètres sont
    lus dans ce cache au lieu d'interroger la base.
    """
    if donnees is None:
        evaluations = (
            db.query(Evaluation)
            .filter(Evaluation.ecue_id == ecue_id)
            .order_by(Evaluation.session, Evaluation.nom)
            .all()
        )
        notes = (
            db.query(Note)
            .join(Evaluation, Note.evaluation_id == Evaluation.id)
            .filter(Note.inscription_id == inscription_id, Evaluation.ecue_id == ecue_id)
            .all()
        )
        coef_devoir = coefficient_devoir(db)
        coef_examen = coefficient_examen(db)
    else:
        evaluations = donnees.evaluations_par_ecue.get(ecue_id, [])
        notes = donnees.notes_par_inscription_ecue.get((inscription_id, ecue_id), [])
        coef_devoir = donnees.coefficient_devoir
        coef_examen = donnees.coefficient_examen
    notes_par_evaluation = {note.evaluation_id: note for note in notes}

    evaluations_session1 = [e for e in evaluations if e.session == 1]
    elements_session1 = _elements_notes(
        evaluations_session1, notes_par_evaluation, coef_devoir, coef_examen
    )

    if session == 1:
        retenues = elements_session1
    else:
        evaluations_session2 = [e for e in evaluations if e.session == 2]
        elements_session2 = _elements_notes(
            evaluations_session2, notes_par_evaluation, coef_devoir, coef_examen
        )
        if not elements_session2:
            retenues = elements_session1
        else:
            cc = [
                element
                for element in elements_session1
                if not _est_examen(element[3].evaluation)
            ]
            if not cc:
                # Le contrôle continu de la session 2 sert de repli.
                cc = [
                    element
                    for element in elements_session2
                    if not _est_examen(element[3].evaluation)
                ]
            examens_session1 = [
                element
                for element in elements_session1
                if _est_examen(element[3].evaluation)
            ]
            examens_session2 = [
                element
                for element in elements_session2
                if _est_examen(element[3].evaluation)
            ]
            mode = donnees.mode_session_2 if donnees is not None else mode_session_2(db)
            if not examens_session2:
                retenues = elements_session1 or elements_session2
            elif mode == "examen_remplace":
                # Le rattrapage remplace la note d'examen initiale.
                retenues = cc + examens_session2
            elif mode == "meilleure_note":
                # La meilleure note d'examen est conservée, le CC est maintenu.
                meilleurs: dict[str, tuple[float, float, int, Note]] = {}
                for element in examens_session1 + examens_session2:
                    cle = _cle_evaluation(element[3])
                    actuel = meilleurs.get(cle)
                    if actuel is None or element[0] > actuel[0]:
                        meilleurs[cle] = element
                retenues = cc + list(meilleurs.values())
            else:
                # Meilleure moyenne générale entre la session 1 et le rattrapage.
                # La note de session 2 remplace à la fois le CC et l'examen :
                # seules les évaluations de session 2 sont retenues.
                moyenne_session1 = _moyenne_ponderee(elements_session1)
                rattrapage = elements_session2
                moyenne_rattrapage = _moyenne_ponderee(rattrapage)
                if moyenne_session1 is not None and (
                    moyenne_rattrapage is None
                    or moyenne_session1 >= moyenne_rattrapage
                ):
                    retenues = elements_session1
                else:
                    retenues = rattrapage

    total_coefficients = sum(item[1] for item in retenues)
    moyenne = _moyenne_ponderee(retenues)
    moyenne_cc = _moyenne_ponderee(
        [item for item in retenues if not _est_examen(item[3].evaluation)]
    )
    moyenne_examen = _moyenne_ponderee(
        [item for item in retenues if _est_examen(item[3].evaluation)]
    )

    detail_notes = []
    for sur_20, coefficient, evaluation_id, note in sorted(
        retenues, key=lambda item: item[2]
    ):
        evaluation = note.evaluation
        detail_notes.append(
            {
                "evaluation_id": evaluation_id,
                "nom": evaluation.nom if evaluation else "",
                "type_evaluation": evaluation.type_evaluation if evaluation else "",
                "session": evaluation.session if evaluation else 1,
                "coefficient": coefficient,
                "note_max": evaluation.note_max if evaluation else 20,
                "valeur": note.valeur,
                "sur_20": sur_20,
                "absent": note.absent,
                "commentaire": note.commentaire or "",
            }
        )

    return {
        "moyenne": moyenne,
        "cc": moyenne_cc,
        "examen": moyenne_examen,
        "coefficient": total_coefficients,
        "notes": detail_notes,
    }


def resultat_inscription(
    db: Session,
    inscription: Inscription,
    semestre_id: int,
    session: int = 1,
    donnees: DonneesCalcul | None = None,
) -> dict:
    """Calcule le résultat complet d'un étudiant pour un semestre.

    Lorsque [donnees] est fourni, les référentiels et notes sont lus dans ce
    cache afin d'éviter des milliers de requêtes sur une base distante.
    """
    if donnees is None:
        ues = [
            ue
            for ue in db.query(UE)
            .filter(UE.semestre_id == semestre_id)
            .order_by(UE.code)
            .all()
            if inscription.niveau_id in ue.niveau_ids
        ]
        resultat_existant = (
            db.query(ResultatSemestre)
            .filter(
                ResultatSemestre.inscription_id == inscription.id,
                ResultatSemestre.semestre_id == semestre_id,
                ResultatSemestre.session == session,
            )
            .first()
        )
        points_jury_ue_etudiant = {
            ligne.ue_id: float(ligne.points or 0)
            for ligne in db.query(PointJuryUE)
            .filter(PointJuryUE.inscription_id == inscription.id)
            .all()
        }
        points_jury_ecue_etudiant = {
            ligne.ecue_id: float(ligne.points or 0)
            for ligne in db.query(PointJuryECUE)
            .filter(PointJuryECUE.inscription_id == inscription.id)
            .all()
        }
        compensation_entre_ecues = compensation_ecue(db)
        compensation_entre_ues = compensation_inter_ue(db)
        ponderer_ecue = ponderation_ecue(db)
    else:
        ues = [
            ue
            for ue in donnees.ues_par_semestre.get(semestre_id, [])
            if inscription.niveau_id in ue.niveau_ids
        ]
        resultat_existant = donnees.resultats.get(
            (inscription.id, semestre_id, session)
        )
        points_jury_ue_etudiant = donnees.points_jury_ue.get(inscription.id, {})
        points_jury_ecue_etudiant = donnees.points_jury_ecue.get(inscription.id, {})
        compensation_entre_ecues = donnees.compensation_ecue
        compensation_entre_ues = donnees.compensation_inter_ue
        ponderer_ecue = donnees.ponderation_ecue

    points_jury_semestre = (
        float(resultat_existant.points_jury or 0) if resultat_existant else 0.0
    )

    details_ues = []
    total_credits = 0
    points_semestre_brut = 0.0
    points_semestre_jury = 0.0
    total_coefficients = 0

    for ue in ues:
        total_credits += ue.credits or 0
        if donnees is None:
            ecues = (
                db.query(ECUE).filter(ECUE.ue_id == ue.id).order_by(ECUE.code).all()
            )
        else:
            ecues = donnees.ecues_par_ue.get(ue.id, [])
        details_ecues = []
        # La moyenne affichée de l'UE est calculée uniquement avec les notes
        # réelles des ECUE ; les points jury servent au calcul interne.
        points_ue_brute = 0.0
        coefficients_ue_brute = 0
        points_ue_jury = 0.0
        coefficients_ue_note_jury = 0
        coefficients_ue_jury = 0
        points_cc = 0.0
        poids_cc = 0
        points_examen = 0.0
        poids_examen = 0
        for ecue in ecues:
            calcul = moyenne_ecue(
                db, inscription.id, ecue.id, semestre_id, session, donnees
            )
            poids_credit = ecue.credits if (ecue.credits or 0) > 0 else 1
            # Sans pondération, chaque ECUE compte pour 1 dans la moyenne de l'UE.
            poids_note = poids_credit if ponderer_ecue else 1
            points_jury_ecue = points_jury_ecue_etudiant.get(ecue.id, 0.0)
            moyenne_ecue_finale = _appliquer_points_jury(
                calcul["moyenne"], points_jury_ecue
            )
            details_ecues.append(
                {
                    "ecue_id": ecue.id,
                    "code": ecue.code,
                    "nom": ecue.nom,
                    "credits": ecue.credits or 0,
                    # La note affichée reste la note réelle, sans points jury.
                    "moyenne": calcul["moyenne"],
                    "moyenne_brute": calcul["moyenne"],
                    # Note interne utilisée pour la validation et le calcul du semestre.
                    "moyenne_jury": moyenne_ecue_finale,
                    "points_jury": round(points_jury_ecue, 2),
                    "cc": calcul["cc"],
                    "examen": calcul["examen"],
                    "statut": statut_ecue(moyenne_ecue_finale),
                    "coefficient": poids_credit,
                    "notes": calcul["notes"],
                }
            )
            if calcul["moyenne"] is not None:
                points_ue_brute += calcul["moyenne"] * poids_note
                coefficients_ue_brute += poids_note
            if moyenne_ecue_finale is not None:
                points_ue_jury += moyenne_ecue_finale * poids_note
                coefficients_ue_note_jury += poids_note
                # Coefficient de l'UE pour la moyenne du semestre et le relevé.
                coefficients_ue_jury += poids_credit
            if calcul["cc"] is not None:
                points_cc += calcul["cc"] * poids_note
                poids_cc += poids_note
            if calcul["examen"] is not None:
                points_examen += calcul["examen"] * poids_note
                poids_examen += poids_note

        moyenne_ue_brute = (
            round(points_ue_brute / coefficients_ue_brute, 2)
            if coefficients_ue_brute
            else None
        )
        moyenne_ue_avant_jury = (
            round(points_ue_jury / coefficients_ue_note_jury, 2)
            if coefficients_ue_note_jury
            else None
        )
        points_jury_ue = points_jury_ue_etudiant.get(ue.id, 0.0)
        moyenne_ue = _appliquer_points_jury(moyenne_ue_avant_jury, points_jury_ue)
        details_ues.append(
            {
                "ue_id": ue.id,
                "code": ue.code,
                "nom": ue.nom,
                "credits": ue.credits or 0,
                # La note affichée reste la note réelle, sans points jury.
                "moyenne": moyenne_ue_brute,
                "moyenne_brute": moyenne_ue_brute,
                # Note interne utilisée pour la validation et le calcul du semestre.
                "moyenne_jury": moyenne_ue,
                "points_jury": round(points_jury_ue, 2),
                "cc": round(points_cc / poids_cc, 2) if poids_cc else None,
                "examen": round(points_examen / poids_examen, 2)
                if poids_examen
                else None,
                "coefficient": coefficients_ue_jury,
                "statut": "En attente" if moyenne_ue is None else "",
                "ecues": details_ecues,
            }
        )
        if coefficients_ue_jury:
            if moyenne_ue_brute is not None:
                points_semestre_brut += moyenne_ue_brute * coefficients_ue_jury
            if moyenne_ue is not None:
                points_semestre_jury += moyenne_ue * coefficients_ue_jury
                total_coefficients += coefficients_ue_jury

    moyenne_semestre_brute = (
        round(points_semestre_brut / total_coefficients, 2)
        if total_coefficients
        else None
    )
    moyenne_semestre_jury_avant = (
        round(points_semestre_jury / total_coefficients, 2)
        if total_coefficients
        else None
    )
    moyenne_semestre_jury = _appliquer_points_jury(
        moyenne_semestre_jury_avant, points_jury_semestre
    )
    # La validation du semestre s'appuie sur la moyenne jury ; la moyenne
    # affichée reste la moyenne réelle, sans points jury.
    compensation = moyenne_semestre_jury is not None and moyenne_semestre_jury >= 10

    credits_obtenus = 0
    for detail in details_ues:
        # La validation tient compte des points jury, contrairement à la note affichée.
        moyenne_ue_jury = detail["moyenne_jury"]
        if moyenne_ue_jury is None:
            detail["statut"] = "En attente"
            continue
        validee = moyenne_ue_jury >= 10
        if validee and not compensation_entre_ecues:
            # Sans compensation entre ECUE, chaque ECUE doit être validé.
            validee = bool(detail["ecues"]) and all(
                ecue["moyenne_jury"] is not None and ecue["moyenne_jury"] >= 10
                for ecue in detail["ecues"]
            )
        detail["statut"] = "Validée" if validee else "Non validée"
        if validee:
            credits_obtenus += detail["credits"]

    toutes_ues_validees = bool(details_ues) and all(
        detail["statut"] == "Validée" for detail in details_ues
    )
    if total_coefficients == 0:
        statut = "En attente"
    elif compensation_entre_ues:
        if moyenne_semestre_jury >= 10:
            statut = "Validé"
        elif credits_obtenus > 0:
            statut = "Partiellement validé"
        elif moyenne_semestre_jury >= 8:
            statut = "Rattrapage"
        else:
            statut = "Ajourné"
    elif toutes_ues_validees:
        statut = "Validé"
    elif credits_obtenus > 0:
        statut = "Partiellement validé"
    elif moyenne_semestre_jury >= 8:
        statut = "Rattrapage"
    else:
        statut = "Ajourné"

    return {
        "inscription_id": inscription.id,
        "semestre_id": semestre_id,
        "session": session,
        "moyenne": moyenne_semestre_brute if moyenne_semestre_brute is not None else 0.0,
        "moyenne_brute": moyenne_semestre_brute,
        "moyenne_jury": moyenne_semestre_jury,
        "credits_obtenus": credits_obtenus,
        "credits_total": total_credits,
        "points_jury": round(points_jury_semestre, 2),
        "statut": statut,
        "mention": mention_pour(moyenne_semestre_brute) if total_coefficients else "",
        "compensation": compensation,
        "compensation_ecue": compensation_entre_ecues,
        "compensation_inter_ue": compensation_entre_ues,
        "ponderation_ecue": ponderer_ecue,
        "session2_mode": donnees.mode_session_2
        if donnees is not None
        else mode_session_2(db),
        "ues": details_ues,
    }


def calculer_et_enregistrer(
    db: Session,
    inscription: Inscription,
    semestre_id: int,
    session: int = 1,
    donnees: DonneesCalcul | None = None,
) -> tuple[ResultatSemestre | None, bool]:
    """Persiste le résultat calculé. Un résultat délibéré n'est jamais recalculé.

    [donnees] permet de réutiliser un préchargement commun à plusieurs
    étudiants : sans lui, un calcul de masse déclenche des milliers de
    requêtes et dépasse le délai d'attente de l'interface.
    """
    existant = (
        donnees.resultats.get((inscription.id, semestre_id, session))
        if donnees is not None
        else None
    )
    if existant is None:
        existant = (
            db.query(ResultatSemestre)
            .filter(
                ResultatSemestre.inscription_id == inscription.id,
                ResultatSemestre.semestre_id == semestre_id,
                ResultatSemestre.session == session,
            )
            .first()
        )
    if existant and existant.verrouille:
        return existant, False

    calcul = resultat_inscription(db, inscription, semestre_id, session, donnees)
    if not calcul["ues"]:
        return None, False

    resultat = existant
    if resultat is None:
        resultat = ResultatSemestre(
            inscription_id=inscription.id, semestre_id=semestre_id, session=session
        )
        db.add(resultat)
    resultat.moyenne = calcul["moyenne"]
    resultat.credits_obtenus = calcul["credits_obtenus"]
    resultat.credits_total = calcul["credits_total"]
    resultat.statut = calcul["statut"]
    resultat.mention = calcul["mention"]
    resultat.detail = json.dumps(calcul, ensure_ascii=False)
    resultat.calcule_le = datetime.utcnow()
    if not resultat.decision:
        resultat.decision = ""
    return resultat, True


def inscriptions_du_semestre(
    db: Session, semestre_id: int, niveau_id: int | None = None
) -> list[Inscription]:
    ids_niveaux: set[int] = set()
    for ue in db.query(UE).filter(UE.semestre_id == semestre_id).all():
        ids_niveaux.update(ue.niveau_ids)
    if not ids_niveaux:
        return []
    requete = db.query(Inscription).filter(Inscription.niveau_id.in_(ids_niveaux))
    if niveau_id is not None:
        requete = requete.filter(Inscription.niveau_id == niveau_id)
    return requete.order_by(Inscription.etudiant_id).all()


def calculer_semestre(
    db: Session,
    semestre_id: int,
    session: int = 1,
    niveau_id: int | None = None,
) -> list[ResultatSemestre]:
    inscriptions = inscriptions_du_semestre(db, semestre_id, niveau_id)
    donnees = (
        precharger_donnees(db, [i.id for i in inscriptions], [semestre_id])
        if inscriptions
        else None
    )
    resultats = []
    for inscription in inscriptions:
        resultat, _ = calculer_et_enregistrer(
            db, inscription, semestre_id, session, donnees
        )
        if resultat is not None:
            resultats.append(resultat)
    db.commit()
    for resultat in resultats:
        db.refresh(resultat)
    return resultats


def _prefixe_et_numero_semestre(nom: str | None) -> tuple[str, int] | None:
    """Décompose un semestre en (parcours, numéro).

    « Semestre 3 » donne ("", 3) ; « Master 1 - Semestre 1 » donne
    ("master 1", 1). Le parcours permet d'apparier les deux semestres d'une
    même filière sans confondre « Semestre 4 » et « Master 1 - Semestre 2 »,
    qui se déroulent pourtant sur la même période.
    """
    if not nom:
        return None
    correspondance = re.search(r"semestre\s*(\d+)", nom, re.IGNORECASE)
    if correspondance is None:
        return None
    try:
        numero = int(correspondance.group(1))
    except ValueError:
        return None
    prefixe = nom[: correspondance.start()]
    prefixe = unicodedata.normalize("NFKD", prefixe)
    prefixe = "".join(
        caractere
        for caractere in prefixe
        if not unicodedata.combining(caractere)
    )
    prefixe = re.sub(r"[^a-z0-9]+", " ", prefixe.lower()).strip()
    return prefixe, numero


def _completer_semestres(
    disponibles: list[Semestre], trouves: list[Semestre], maximum: int = 2
) -> list[Semestre]:
    """Complète un parcours avec le second semestre de la même année.

    Plusieurs niveaux n'ont pas encore d'UE pour leur second semestre : le
    relevé annuel doit malgré tout présenter les deux semestres de l'année
    (par exemple Semestre 3 et Semestre 4 pour une inscription en 2026-2027).
    Le semestre ajouté reste « En attente » tant qu'aucune note n'existe.
    """
    liste = list(trouves)
    if len(liste) >= maximum:
        liste.sort(key=lambda semestre: (semestre.date_debut or date.min, semestre.id))
        return liste[:maximum]

    for semestre in list(liste):
        if len(liste) >= maximum:
            break
        decompose = _prefixe_et_numero_semestre(semestre.nom)
        if decompose is None:
            continue
        prefixe, numero = decompose
        cible = numero + 1 if numero % 2 else numero - 1
        candidat = next(
            (
                autre
                for autre in disponibles
                if _prefixe_et_numero_semestre(autre.nom) == (prefixe, cible)
                and all(existant.id != autre.id for existant in liste)
            ),
            None,
        )
        if candidat is not None:
            liste.append(candidat)

    liste.sort(key=lambda semestre: (semestre.date_debut or date.min, semestre.id))
    return liste[:maximum]


def _semestres_du_parcours(db: Session, inscription: Inscription) -> list[Semestre]:
    """Les semestres de la classe suivie par l'étudiant pour son année."""
    semestres = (
        db.query(Semestre)
        .filter(Semestre.annee == inscription.annee)
        .order_by(Semestre.date_debut, Semestre.id)
        .all()
    )
    return [
        semestre
        for semestre in semestres
        if any(inscription.niveau_id in ue.niveau_ids for ue in semestre.ues)
    ]


def _niveau_suivant(db: Session, niveau: Niveau | None) -> Niveau | None:
    if niveau is None:
        return None
    return (
        db.query(Niveau)
        .filter(
            Niveau.filiere_id == niveau.filiere_id,
            Niveau.ordre > niveau.ordre,
        )
        .order_by(Niveau.ordre, Niveau.id)
        .first()
    )


def _niveau_suivant_depuis(
    niveaux_par_filiere: dict[int, list[Niveau]], niveau: Niveau | None
) -> Niveau | None:
    """Variante en mémoire de [_niveau_suivant] pour les calculs en masse."""
    if niveau is None:
        return None
    for candidat in niveaux_par_filiere.get(niveau.filiere_id, []):
        if (candidat.ordre or 0) > (niveau.ordre or 0):
            return candidat
    return None


def resultats_passage(
    db: Session,
    annee: str,
    session: int = 1,
    mode: str = "10",
    seuil_dettes: float = 80,
    moyenne_passage: float = 10,
    niveau_id: int | None = None,
    inscription_id: int | None = None,
) -> list[dict]:
    """Résultats de passage en classe supérieure pour une année universitaire.

    Une classe correspond aux deux semestres de l'année. Les résultats sont
    calculés à partir des notes réelles afin de toujours refléter les réglages
    de compensation en vigueur.
    """
    seuil = max(0.0, min(100.0, float(seuil_dettes)))
    seuil_moyenne = 10.0 if float(moyenne_passage or 10) < 12 else 12.0
    requete = (
        db.query(Inscription)
        .options(
            joinedload(Inscription.etudiant),
            joinedload(Inscription.niveau).joinedload(Niveau.filiere),
            joinedload(Inscription.groupe),
        )
        .filter(Inscription.annee == annee)
    )
    if niveau_id is not None:
        requete = requete.filter(Inscription.niveau_id == niveau_id)
    if inscription_id is not None:
        # Un relevé individuel ne doit pas recalculer toute la classe : sur
        # une base distante, cela dépassait le délai d'attente de l'interface.
        requete = requete.filter(Inscription.id == inscription_id)
    inscriptions = requete.order_by(Inscription.etudiant_id).all()
    if not inscriptions:
        return []

    # Les semestres de l'année et leurs UE sont chargés en une fois, puis
    # indexés par niveau : chaque étudiant retrouve ainsi son parcours sans
    # requête supplémentaire.
    semestres_annee = (
        db.query(Semestre)
        .options(selectinload(Semestre.ues).selectinload(UE.niveaux))
        .filter(Semestre.annee == annee)
        .order_by(Semestre.date_debut, Semestre.id)
        .all()
    )
    semestres_par_niveau: dict[int, list[Semestre]] = {}
    for semestre in semestres_annee:
        niveaux_semestre: set[int] = set()
        for ue in semestre.ues:
            niveaux_semestre.update(ue.niveau_ids)
        for identifiant in niveaux_semestre:
            semestres_par_niveau.setdefault(identifiant, []).append(semestre)

    niveaux = (
        db.query(Niveau)
        .options(joinedload(Niveau.filiere))
        .order_by(Niveau.ordre, Niveau.id)
        .all()
    )
    niveaux_par_filiere: dict[int, list[Niveau]] = {}
    for niveau in niveaux:
        niveaux_par_filiere.setdefault(niveau.filiere_id, []).append(niveau)

    inscriptions_ids = [inscription.id for inscription in inscriptions]
    semestres_par_id = {semestre.id: semestre for semestre in semestres_annee}
    semestres_annee_ids = list(semestres_par_id)

    # Repli pour les niveaux sans UE rattachée (Master, cycle ingénieur) :
    # les semestres du parcours sont retrouvés à partir des résultats déjà
    # enregistrés, des notes ou des séances de l'étudiant pour cette année.
    # Sans cela, le relevé de passage et les moyennes annuelles restaient
    # vides alors que les notes existaient.
    semestres_repli: dict[int, list[Semestre]] = {}

    def ajouter_repli(inscription_id: int, semestre: Semestre | None) -> None:
        if semestre is None:
            return
        liste = semestres_repli.setdefault(inscription_id, [])
        if all(existant.id != semestre.id for existant in liste):
            liste.append(semestre)

    resultats_enregistres: list[ResultatSemestre] = []
    if semestres_annee_ids:
        resultats_enregistres = (
            db.query(ResultatSemestre)
            .options(joinedload(ResultatSemestre.semestre))
            .filter(
                ResultatSemestre.inscription_id.in_(inscriptions_ids),
                ResultatSemestre.semestre_id.in_(semestres_annee_ids),
            )
            .all()
        )
        for ligne in resultats_enregistres:
            ajouter_repli(ligne.inscription_id, ligne.semestre)

        lignes_notes = (
            db.query(Note.inscription_id, Evaluation.semestre_id)
            .join(Evaluation, Note.evaluation_id == Evaluation.id)
            .filter(
                Note.inscription_id.in_(inscriptions_ids),
                Evaluation.semestre_id.in_(semestres_annee_ids),
            )
            .distinct()
            .all()
        )
        for inscription_id, semestre_id in lignes_notes:
            ajouter_repli(inscription_id, semestres_par_id.get(semestre_id))

    parcours: dict[int, list[Semestre]] = {}
    for inscription in inscriptions:
        liste = list(semestres_par_niveau.get(inscription.niveau_id, [])[:2])
        if not liste:
            liste = list(semestres_repli.get(inscription.id, [])[:2])
        parcours[inscription.id] = _completer_semestres(semestres_annee, liste)

    # Dernier repli : les séances du groupe de l'étudiant dans l'année.
    for inscription in inscriptions:
        if parcours[inscription.id] or not inscription.groupe_id:
            continue
        identifiants = (
            db.query(Seance.semestre_id)
            .filter(
                Seance.semestre_id.in_(semestres_annee_ids),
                Seance.groupes.any(Groupe.id == inscription.groupe_id),
            )
            .distinct()
            .all()
        )
        parcours[inscription.id] = _completer_semestres(
            semestres_annee,
            [
                semestres_par_id[semestre_id]
                for (semestre_id,) in identifiants
                if semestre_id in semestres_par_id
            ],
        )

    resultats_stockes = {
        (ligne.inscription_id, ligne.semestre_id): ligne
        for ligne in resultats_enregistres
    }
    semestre_ids = {
        semestre.id for liste in parcours.values() for semestre in liste
    }
    donnees_calcul = precharger_donnees(
        db, inscriptions_ids, list(semestre_ids)
    )

    resultats = []
    for inscription in inscriptions:
        semestres = parcours.get(inscription.id, [])
        details_semestres = []
        for semestre in semestres:
            donnees = resultat_inscription(
                db, inscription, semestre.id, session, donnees_calcul
            )
            # Niveau sans UE rattachée : le calcul ne peut pas aboutir, mais
            # un résultat délibéré a peut-être déjà été enregistré.
            stocke = resultats_stockes.get((inscription.id, semestre.id))
            if (
                donnees["statut"] == "En attente"
                and stocke is not None
                and stocke.statut
                and stocke.statut != "En attente"
            ):
                details_semestres.append(
                    {
                        "semestre_id": semestre.id,
                        "semestre": semestre.nom,
                        "annee": semestre.annee,
                        "moyenne": stocke.moyenne,
                        "credits_obtenus": stocke.credits_obtenus,
                        "credits_total": stocke.credits_total,
                        "statut": stocke.statut,
                        "mention": stocke.mention or "",
                    }
                )
                continue
            details_semestres.append(
                {
                    "semestre_id": semestre.id,
                    "semestre": semestre.nom,
                    "annee": semestre.annee,
                    "moyenne": donnees["moyenne"]
                    if donnees["statut"] != "En attente"
                    else None,
                    "credits_obtenus": donnees["credits_obtenus"],
                    "credits_total": donnees["credits_total"],
                    "statut": donnees["statut"],
                    "mention": donnees["mention"],
                }
            )

        moyennes = [
            detail["moyenne"]
            for detail in details_semestres
            if detail["moyenne"] is not None
        ]
        moyenne_annee = (
            round(sum(moyennes) / len(moyennes), 2) if moyennes else None
        )
        credits_total = sum(detail["credits_total"] for detail in details_semestres)
        credits_obtenus = sum(detail["credits_obtenus"] for detail in details_semestres)
        pourcentage_credits = (
            round(credits_obtenus / credits_total * 100, 1) if credits_total else 0.0
        )
        deux_semestres = len(details_semestres) >= 2
        annee_incomplete = not deux_semestres or any(
            detail["statut"] == "En attente" for detail in details_semestres
        )
        valide_deux_semestres = deux_semestres and all(
            detail["statut"] == "Validé" for detail in details_semestres
        )

        if mode == "12":
            admis = (
                valide_deux_semestres
                and moyenne_annee is not None
                and moyenne_annee >= 12
            )
        elif mode == "dettes":
            admis = (
                pourcentage_credits >= seuil
                and moyenne_annee is not None
                and moyenne_annee >= seuil_moyenne
            )
        else:
            admis = valide_deux_semestres

        if admis:
            if mode == "dettes" and credits_obtenus < credits_total:
                decision = "Admis avec dettes"
            else:
                decision = "Admis en classe supérieure"
        elif annee_incomplete:
            decision = "Année incomplète"
        elif mode == "dettes" and pourcentage_credits >= seuil:
            decision = "Moyenne annuelle insuffisante"
        elif mode == "12" and valide_deux_semestres:
            decision = "Moyenne annuelle insuffisante"
        else:
            decision = "Ajourné"

        suivant = _niveau_suivant_depuis(niveaux_par_filiere, inscription.niveau)
        resultats.append(
            {
                "inscription_id": inscription.id,
                "matricule": inscription.matricule,
                "etudiant": inscription.etudiant_nom,
                "niveau_id": inscription.niveau_id,
                "niveau": inscription.niveau_nom,
                "filiere": inscription.filiere_nom,
                "groupe": inscription.groupe_nom,
                "annee": inscription.annee,
                "semestres": details_semestres,
                "moyenne_annee": moyenne_annee,
                "credits_obtenus": credits_obtenus,
                "credits_total": credits_total,
                "pourcentage_credits": pourcentage_credits,
                "valide_deux_semestres": valide_deux_semestres,
                "admis": admis,
                "decision": decision,
                "niveau_suivant_id": suivant.id if suivant else None,
                "niveau_suivant": suivant.nom if suivant else "Fin de cycle",
                "filiere_suivante": suivant.filiere.nom
                if suivant and suivant.filiere
                else "",
            }
        )

    resultats.sort(
        key=lambda item: (
            not item["admis"],
            -(item["moyenne_annee"] or 0),
            item["etudiant"],
        )
    )
    return resultats


def statistiques_semestre(
    db: Session,
    semestre_id: int,
    session: int = 1,
    niveau_id: int | None = None,
    ecue_ids: list[int] | None = None,
) -> dict:
    """Statistiques du semestre, éventuellement restreintes aux ECUE d'un enseignant."""
    filtre_ecues = set(ecue_ids) if ecue_ids is not None else None

    def ecue_autorisee(ecue) -> bool:
        if filtre_ecues is None:
            return True
        return ecue is not None and ecue.id in filtre_ecues

    resultats = (
        db.query(ResultatSemestre)
        .filter(
            ResultatSemestre.semestre_id == semestre_id,
            ResultatSemestre.session == session,
        )
        .all()
    )
    if niveau_id is not None:
        resultats = [
            r for r in resultats if r.inscription and r.inscription.niveau_id == niveau_id
        ]

    evaluations = db.query(Evaluation).filter(Evaluation.semestre_id == semestre_id).all()
    if filtre_ecues is not None:
        evaluations = [e for e in evaluations if e.ecue_id in filtre_ecues]
    ids_evaluations = {e.id for e in evaluations}
    notes_saisies = (
        db.query(Note).filter(Note.evaluation_id.in_(ids_evaluations)).count()
        if ids_evaluations
        else 0
    )
    inscriptions = inscriptions_du_semestre(db, semestre_id, niveau_id)
    effectifs_par_niveau = {}
    for inscription in inscriptions:
        effectifs_par_niveau[inscription.niveau_id] = (
            effectifs_par_niveau.get(inscription.niveau_id, 0) + 1
        )
    attendues = 0
    for evaluation in evaluations:
        ecue = evaluation.ecue
        if ecue is None or ecue.ue is None:
            continue
        ids_niveaux_ue = ecue.ue.niveau_ids
        if niveau_id is not None and niveau_id not in ids_niveaux_ue:
            continue
        attendues += sum(effectifs_par_niveau.get(nid, 0) for nid in ids_niveaux_ue)

    valides = [r for r in resultats if r.statut in ("Validé", "Partiellement validé")]
    admis = [r for r in resultats if r.decision == "ADMIS"]
    notes = [r.moyenne for r in resultats if r.statut != "En attente"]
    moyenne_generale = round(sum(notes) / len(notes), 2) if notes else 0.0

    mentions = {}
    for resultat in resultats:
        if resultat.mention:
            mentions[resultat.mention] = mentions.get(resultat.mention, 0) + 1

    stats_ues = []
    for ue in (
        db.query(UE).filter(UE.semestre_id == semestre_id).order_by(UE.code).all()
    ):
        if niveau_id is not None and niveau_id not in ue.niveau_ids:
            continue
        if filtre_ecues is not None and not any(ecue_autorisee(e) for e in ue.ecues):
            continue
        moyennes = []
        for resultat in resultats:
            try:
                detail = json.loads(resultat.detail or "{}")
            except ValueError:
                continue
            for bloc in detail.get("ues", []):
                if bloc.get("ue_id") != ue.id:
                    continue
                # On privilégie la note réelle : les anciens résultats peuvent
                # encore contenir une moyenne déjà augmentée par les points jury.
                valeur = bloc.get("moyenne_brute")
                if valeur is None:
                    valeur = bloc.get("moyenne")
                if valeur is not None:
                    moyennes.append(valeur)
        stats_ues.append(
            {
                "ue_id": ue.id,
                "code": ue.code,
                "nom": ue.nom,
                "credits": ue.credits,
                "inscrits": len(moyennes),
                "moyenne": round(sum(moyennes) / len(moyennes), 2) if moyennes else 0.0,
                "taux_reussite": round(
                    len([m for m in moyennes if m >= 10]) / len(moyennes) * 100, 1
                )
                if moyennes
                else 0.0,
            }
        )

    stats_ecues = []
    for ecue in (
        db.query(ECUE)
        .join(UE, ECUE.ue_id == UE.id)
        .filter(UE.semestre_id == semestre_id)
        .order_by(UE.code, ECUE.code)
        .all()
    ):
        if niveau_id is not None and (
            ecue.ue is None or niveau_id not in ecue.ue.niveau_ids
        ):
            continue
        if not ecue_autorisee(ecue):
            continue
        moyennes = []
        for resultat in resultats:
            try:
                detail = json.loads(resultat.detail or "{}")
            except ValueError:
                continue
            for bloc_ue in detail.get("ues", []):
                for bloc_ecue in bloc_ue.get("ecues", []):
                    if bloc_ecue.get("ecue_id") != ecue.id:
                        continue
                    valeur = bloc_ecue.get("moyenne_brute")
                    if valeur is None:
                        valeur = bloc_ecue.get("moyenne")
                    if valeur is not None:
                        moyennes.append(valeur)
        stats_ecues.append(
            {
                "ecue_id": ecue.id,
                "code": ecue.code,
                "nom": ecue.nom,
                "ue_code": ecue.ue.code if ecue.ue else "",
                "credits": ecue.credits or 0,
                "inscrits": len(moyennes),
                "moyenne": round(sum(moyennes) / len(moyennes), 2) if moyennes else 0.0,
                "taux_reussite": round(
                    len([m for m in moyennes if m >= 10]) / len(moyennes) * 100, 1
                )
                if moyennes
                else 0.0,
            }
        )

    return {
        "semestre_id": semestre_id,
        "session": session,
        "etudiants": len(inscriptions),
        "resultats": len(resultats),
        "evaluations": len(evaluations),
        "notes_saisies": notes_saisies,
        "notes_attendues": attendues,
        "taux_saisie": round(notes_saisies / attendues * 100, 1) if attendues else 0.0,
        "moyenne_generale": moyenne_generale,
        "taux_reussite": round(len(valides) / len(resultats) * 100, 1)
        if resultats
        else 0.0,
        "admis": len(admis),
        "mentions": mentions,
        "ues": stats_ues,
        "ecues": stats_ecues,
    }


# ============================================== Diplômes et attestations de réussite
CYCLES_DIPLOMES = {
    "licence": {"diplome": "Licence", "semestres": 6, "niveaux": 3},
    "master": {"diplome": "Master", "semestres": 4, "niveaux": 2},
    "ingenieur": {"diplome": "Grade d’ingénieur", "semestres": 10, "niveaux": 5},
}


def _sans_accents(texte: str) -> str:
    texte = unicodedata.normalize("NFKD", texte or "")
    return "".join(c for c in texte if not unicodedata.combining(c)).lower()


def cycle_diplome(niveau: Niveau | None) -> str | None:
    """Déduit le cycle de diplôme à partir du nom du niveau."""
    if niveau is None:
        return None
    texte = _sans_accents(
        f"{niveau.nom or ''} {niveau.filiere.code if niveau.filiere else ''}"
    )
    if "licence" in texte:
        return "licence"
    if "master" in texte:
        return "master"
    if any(mot in texte for mot in ("ingenieur", "mpsi", "prepa", "cycle d")):
        return "ingenieur"
    return None


def _resultats_valides(db: Session, etudiant_id: int) -> dict[str, dict[int, dict]]:
    """Semestres validés par cycle, pour un étudiant."""
    lignes = (
        db.query(ResultatSemestre, Inscription)
        .join(Inscription, ResultatSemestre.inscription_id == Inscription.id)
        .filter(
            Inscription.etudiant_id == etudiant_id,
            ResultatSemestre.statut == "Validé",
        )
        .all()
    )
    valides: dict[str, dict[int, dict]] = {}
    for resultat, inscription in lignes:
        cycle = cycle_diplome(inscription.niveau)
        if cycle is None:
            continue
        semestre = resultat.semestre
        valides.setdefault(cycle, {})[resultat.semestre_id] = {
            "semestre_id": resultat.semestre_id,
            "semestre": semestre.nom if semestre else "",
            "annee": semestre.annee if semestre else inscription.annee,
            "niveau": inscription.niveau_nom,
        }
    return valides


def diplome_etudiant(db: Session, etudiant_id: int) -> list[dict]:
    """Détermine les diplômes obtenus par un étudiant.

    Licence : six semestres validés ou niveau Licence 3 validé.
    Master : quatre semestres validés.
    Grade d’ingénieur : dix semestres validés.
    """
    etudiant = db.get(Etudiant, etudiant_id)
    if etudiant is None:
        return []
    inscriptions = (
        db.query(Inscription).filter(Inscription.etudiant_id == etudiant_id).all()
    )
    valides = _resultats_valides(db, etudiant_id)
    diplomes = []
    for cycle, infos in CYCLES_DIPLOMES.items():
        blocs = valides.get(cycle, {})
        nombre_valides = len(blocs)
        niveau_final_valide = False
        annee_validation = ""
        niveau_final = ""

        for inscription in inscriptions:
            if cycle_diplome(inscription.niveau) != cycle:
                continue
            if inscription.niveau and inscription.niveau.ordre >= infos["niveaux"]:
                semestres = _semestres_du_parcours(db, inscription)
                if semestres and all(
                    semestre.id in blocs for semestre in semestres
                ):
                    niveau_final_valide = True
                    niveau_final = inscription.niveau_nom
                    annee_validation = inscription.annee
                    break

        annees = [bloc["annee"] for bloc in blocs.values() if bloc["annee"]]
        if not annee_validation and annees:
            annee_validation = sorted(annees)[-1]

        eligible = nombre_valides >= infos["semestres"] or niveau_final_valide
        diplomes.append(
            {
                "etudiant_id": etudiant_id,
                "matricule": etudiant.matricule,
                "etudiant": etudiant.nom_complet,
                "date_naissance": etudiant.date_naissance,
                "cycle": cycle,
                "diplome": infos["diplome"],
                "eligible": eligible,
                "semestres_valides": nombre_valides,
                "semestres_requis": infos["semestres"],
                "annee_validation": annee_validation,
                "niveau_final": niveau_final
                or (inscriptions[-1].niveau_nom if inscriptions else ""),
            }
        )
    return diplomes


def diplomes_eligibles(
    db: Session, annee: str | None = None, niveau_id: int | None = None
) -> list[dict]:
    """Liste des étudiants remplissant les conditions d'un diplôme."""
    requete = db.query(Etudiant)
    if niveau_id is not None:
        requete = requete.filter(
            Etudiant.id.in_(
                db.query(Inscription.etudiant_id).filter(
                    Inscription.niveau_id == niveau_id
                )
            )
        )
    if annee:
        requete = requete.filter(
            Etudiant.id.in_(
                db.query(Inscription.etudiant_id).filter(Inscription.annee == annee)
            )
        )
    resultats = []
    for etudiant in requete.order_by(Etudiant.nom, Etudiant.prenom).all():
        for diplome in diplome_etudiant(db, etudiant.id):
            if diplome["eligible"]:
                resultats.append(diplome)
    return resultats
