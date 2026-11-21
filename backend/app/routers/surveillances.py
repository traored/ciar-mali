"""Surveillances d'évaluations : saisie, statistiques, modèle et import Excel."""
import re
import unicodedata
from datetime import date, datetime
from io import BytesIO
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from ..database import get_db
from ..models import (
    ECUE,
    Enseignant,
    Niveau,
    Semestre,
    Surveillant,
    Surveillance,
    SurveillanceSurveillant,
    Utilisateur,
)
from ..schemas import SurveillanceCreate, SurveillanceUpdate
from ..security import admin_gestionnaire_superviseur

router = APIRouter(prefix="/api/surveillances", tags=["surveillances"])

MIME_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

TYPES_EVALUATION = [
    "Examen",
    "Devoir",
    "Contrôle continu",
    "TP",
    "Oral",
    "Projet",
    "Rattrapage",
]

SEPARATEURS_SURVEILLANTS = re.compile(r"[;|/\n\r]+")


# ------------------------------------------------------------------ Utilitaires
def _sans_accents(texte) -> str:
    texte = unicodedata.normalize("NFKD", str(texte or ""))
    return "".join(c for c in texte if not unicodedata.combining(c))


def _cle(texte) -> str:
    """Clé de comparaison : sans accents, sans casse, espaces normalisés."""
    return " ".join(_sans_accents(texte).lower().replace("-", " ").split())


def _cle_nom(texte) -> str:
    return _cle(texte)


def _texte(valeur) -> str:
    if valeur is None:
        return ""
    if isinstance(valeur, float) and valeur.is_integer():
        return str(int(valeur))
    return str(valeur).strip()


def _date_import(valeur) -> Optional[date]:
    """Convertit une cellule Excel ou une chaîne en date (formats français inclus)."""
    if valeur in (None, ""):
        return None
    if isinstance(valeur, datetime):
        return valeur.date()
    if isinstance(valeur, date):
        return valeur
    texte = _texte(valeur)
    for format_ in ("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y", "%d/%m/%y", "%d.%m.%Y"):
        try:
            return datetime.strptime(texte, format_).date()
        except ValueError:
            continue
    raise ValueError(f"Date invalide : {texte}")


def _duree_minutes(valeur, defaut: int = 120) -> int:
    """Convertit « 2h », « 1h30 », « 90 min » ou 90 en minutes."""
    if valeur in (None, ""):
        return defaut
    if isinstance(valeur, (int, float)) and not isinstance(valeur, bool):
        if valeur <= 0:
            raise ValueError(f"Durée invalide : {valeur}")
        # Excel peut stocker une durée en fraction de journée.
        minutes = valeur * 24 * 60 if 0 < valeur < 1 else valeur
        return max(1, int(round(minutes)))
    texte = _texte(valeur).lower().replace(",", ".")
    texte = texte.replace("minutes", "").replace("minute", "")
    texte = texte.replace("mins", "").replace("min", "").replace("mn", "")
    texte = texte.replace("heures", "").replace("heure", "").replace("hrs", "")
    texte = texte.replace("h", " ").replace(":", " ")
    morceaux = [morceau for morceau in texte.split() if morceau]
    try:
        nombres = [float(morceau) for morceau in morceaux]
    except ValueError:
        raise ValueError(f"Durée invalide : {valeur}")
    if not nombres:
        return defaut
    if len(nombres) >= 2:
        minutes = nombres[0] * 60 + nombres[1]
    elif ":" in _texte(valeur) or "h" in _texte(valeur).lower():
        minutes = nombres[0] * 60
    else:
        minutes = nombres[0]
    if minutes <= 0:
        raise ValueError(f"Durée invalide : {valeur}")
    return int(round(minutes))


def _decouper_surveillants(texte) -> list[str]:
    if texte is None:
        return []
    if isinstance(texte, (list, tuple)):
        morceaux = []
        for element in texte:
            morceaux.extend(_decouper_surveillants(element))
        return morceaux
    return [morceau.strip() for morceau in SEPARATEURS_SURVEILLANTS.split(str(texte)) if morceau.strip()]


# ------------------------------------------------------------------ Chargement
def _options_chargement():
    return (
        joinedload(Surveillance.ecue),
        joinedload(Surveillance.semestre),
        joinedload(Surveillance.niveau),
        joinedload(Surveillance.surveillants).joinedload(
            SurveillanceSurveillant.enseignant
        ),
        joinedload(Surveillance.surveillants).joinedload(
            SurveillanceSurveillant.surveillant
        ),
    )


def _requete(
    db: Session,
    semestre_id: Optional[int] = None,
    niveau_id: Optional[int] = None,
    ecue_id: Optional[int] = None,
    date_debut: Optional[date] = None,
    date_fin: Optional[date] = None,
    q: str = "",
):
    requete = db.query(Surveillance).options(*_options_chargement())
    if semestre_id:
        requete = requete.filter(Surveillance.semestre_id == semestre_id)
    if niveau_id:
        requete = requete.filter(Surveillance.niveau_id == niveau_id)
    if ecue_id:
        requete = requete.filter(Surveillance.ecue_id == ecue_id)
    if date_debut:
        requete = requete.filter(Surveillance.date_evaluation >= date_debut)
    if date_fin:
        requete = requete.filter(Surveillance.date_evaluation <= date_fin)
    if q and q.strip():
        motif = f"%{q.strip()}%"
        requete = requete.filter(
            or_(
                Surveillance.ecue.has(
                    or_(ECUE.code.ilike(motif), ECUE.nom.ilike(motif))
                ),
                Surveillance.type_evaluation.ilike(motif),
                Surveillance.salle.ilike(motif),
                Surveillance.surveillants.any(
                    SurveillanceSurveillant.nom.ilike(motif)
                ),
            )
        )
    return requete.order_by(
        Surveillance.date_evaluation.desc(), Surveillance.id.desc()
    )


def _charger(db: Session, surveillance_id: int) -> Surveillance:
    element = (
        db.query(Surveillance)
        .options(*_options_chargement())
        .filter(Surveillance.id == surveillance_id)
        .first()
    )
    if not element:
        raise HTTPException(404, "Surveillance introuvable")
    return element


def _serialiser(element: Surveillance) -> dict:
    return {
        "id": element.id,
        "ecue_id": element.ecue_id,
        "ecue_code": element.ecue_code,
        "ecue_nom": element.ecue_nom,
        "semestre_id": element.semestre_id,
        "semestre_nom": element.semestre_nom,
        "annee": element.annee,
        "niveau_id": element.niveau_id,
        "niveau_nom": element.niveau_nom,
        "type_evaluation": element.type_evaluation,
        "duree_minutes": element.duree_minutes,
        "date_evaluation": element.date_evaluation.isoformat()
        if element.date_evaluation
        else None,
        "session": element.session,
        "salle": element.salle or "",
        "observation": element.observation or "",
        "surveillants": [
            {
                "id": surveillant.id,
                "nom": surveillant.nom,
                "enseignant_id": surveillant.enseignant_id,
                "enseignant_nom": surveillant.enseignant_nom,
                "surveillant_id": surveillant.surveillant_id,
                "surveillant_nom": surveillant.surveillant_nom,
            }
            for surveillant in element.surveillants
        ],
        "surveillants_texte": element.surveillants_texte,
        "cree_le": element.cree_le.isoformat() if element.cree_le else None,
    }


def _ecue(db: Session, ecue_id: int) -> ECUE:
    ecue = db.get(ECUE, ecue_id)
    if not ecue:
        raise HTTPException(400, "ECUE introuvable")
    if not ecue.semestre_id:
        raise HTTPException(
            400,
            "L'ECUE sélectionnée n'est rattachée à aucun semestre.",
        )
    return ecue


def _niveau(db: Session, niveau_id: Optional[int], ecue: ECUE) -> Optional[int]:
    identifiant = niveau_id or ecue.niveau_id
    if not identifiant:
        return None
    if not db.get(Niveau, identifiant):
        raise HTTPException(400, "Niveau introuvable")
    return identifiant


def _remplacer_surveillants(
    db: Session,
    element: Surveillance,
    surveillants,
) -> None:
    """Remplace la liste des surveillants en évitant les doublons de nom."""
    element.surveillants.clear()
    vus: set[str] = set()
    for entree in surveillants or []:
        enseignant = None
        surveillant = None
        if getattr(entree, "surveillant_id", None):
            surveillant = db.get(Surveillant, entree.surveillant_id)
            if not surveillant:
                raise HTTPException(400, "Fiche surveillant introuvable")
        elif getattr(entree, "enseignant_id", None):
            enseignant = db.get(Enseignant, entree.enseignant_id)
            if not enseignant:
                raise HTTPException(400, "Enseignant surveillant introuvable")
        nom = (getattr(entree, "nom", "") or "").strip()
        if not nom and surveillant is not None:
            nom = surveillant.nom_affichage
        if not nom and enseignant is not None:
            nom = enseignant.nom_affichage
        if not nom:
            continue
        cle = _cle_nom(nom)
        if cle in vus:
            continue
        vus.add(cle)
        element.surveillants.append(
            SurveillanceSurveillant(
                nom=nom,
                enseignant_id=enseignant.id if enseignant else None,
                surveillant_id=surveillant.id if surveillant else None,
            )
        )
    if not element.surveillants:
        raise HTTPException(400, "Indiquez au moins un surveillant.")


# ------------------------------------------------------------------ Référentiels
@router.get("/options")
def options(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Listes utiles aux formulaires et à la préparation des imports."""
    semestres = db.query(Semestre).order_by(Semestre.annee.desc(), Semestre.nom).all()
    niveaux = db.query(Niveau).all()
    return {
        "types": TYPES_EVALUATION,
        "semestres": [
            {"id": s.id, "nom": s.nom, "annee": s.annee} for s in semestres
        ],
        "niveaux": [
            {"id": n.id, "nom": n.nom, "filiere_code": n.filiere.code if n.filiere else ""}
            for n in niveaux
        ],
        "annees": sorted({s.annee for s in semestres if s.annee}, reverse=True),
    }


# ------------------------------------------------------------------ CRUD
@router.get("")
def lister(
    semestre_id: Optional[int] = None,
    niveau_id: Optional[int] = None,
    ecue_id: Optional[int] = None,
    date_debut: Optional[date] = None,
    date_fin: Optional[date] = None,
    q: str = Query(""),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    elements = _requete(
        db, semestre_id, niveau_id, ecue_id, date_debut, date_fin, q
    ).all()
    return [_serialiser(element) for element in elements]


@router.post("", status_code=201)
def creer(
    payload: SurveillanceCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    ecue = _ecue(db, payload.ecue_id)
    element = Surveillance(
        ecue_id=ecue.id,
        semestre_id=ecue.semestre_id,
        niveau_id=_niveau(db, payload.niveau_id, ecue),
        type_evaluation=(payload.type_evaluation or "Examen").strip() or "Examen",
        duree_minutes=payload.duree_minutes,
        date_evaluation=payload.date_evaluation,
        session=payload.session or 1,
        salle=(payload.salle or "").strip(),
        observation=(payload.observation or "").strip(),
    )
    _remplacer_surveillants(db, element, payload.surveillants)
    db.add(element)
    db.commit()
    return _serialiser(_charger(db, element.id))


@router.put("/{surveillance_id}")
def modifier(
    surveillance_id: int,
    payload: SurveillanceUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    element = _charger(db, surveillance_id)
    if payload.ecue_id is not None:
        ecue = _ecue(db, payload.ecue_id)
        element.ecue_id = ecue.id
        element.semestre_id = ecue.semestre_id
        if payload.niveau_id is None:
            element.niveau_id = ecue.niveau_id
    if payload.niveau_id is not None:
        element.niveau_id = _niveau(db, payload.niveau_id, element.ecue)
    if payload.type_evaluation is not None:
        element.type_evaluation = payload.type_evaluation.strip() or "Examen"
    if payload.duree_minutes is not None:
        if payload.duree_minutes <= 0:
            raise HTTPException(400, "La durée doit être supérieure à zéro.")
        element.duree_minutes = payload.duree_minutes
    if payload.date_evaluation is not None:
        element.date_evaluation = payload.date_evaluation
    if payload.session is not None:
        element.session = payload.session or 1
    if payload.salle is not None:
        element.salle = payload.salle.strip()
    if payload.observation is not None:
        element.observation = payload.observation.strip()
    if payload.surveillants is not None:
        _remplacer_surveillants(db, element, payload.surveillants)
    db.commit()
    return _serialiser(_charger(db, element.id))


@router.delete("/{surveillance_id}")
def supprimer(
    surveillance_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    element = db.get(Surveillance, surveillance_id)
    if not element:
        raise HTTPException(404, "Surveillance introuvable")
    db.delete(element)
    db.commit()
    return {"ok": True}


# ------------------------------------------------------------------ Statistiques
def _calculer_statistiques(elements: list[Surveillance]) -> dict:
    """Statistiques par surveillant et par semestre (jours = dates distinctes)."""
    par_surveillant: dict[str, dict] = {}
    par_semestre: dict[int, dict] = {}
    jours_globaux: set[date] = set()
    minutes_globales = 0
    dates_globales: list[date] = []

    for element in elements:
        jour = element.date_evaluation
        if jour:
            jours_globaux.add(jour)
            dates_globales.append(jour)
        minutes = element.duree_minutes or 0
        minutes_globales += minutes

        cle_semestre = element.semestre_id
        semestre = par_semestre.setdefault(
            cle_semestre,
            {
                "semestre_id": cle_semestre,
                "semestre_nom": element.semestre_nom or "—",
                "annee": element.annee or "",
                "nombre_surveillances": 0,
                "nombre_jours": 0,
                "nombre_surveillants": 0,
                "duree_minutes": 0,
                "dates": set(),
                "surveillants": {},
            },
        )
        semestre["nombre_surveillances"] += 1
        semestre["duree_minutes"] += minutes
        if jour:
            semestre["dates"].add(jour)

        for surveillant in element.surveillants:
            nom = (surveillant.nom or "").strip()
            if not nom:
                continue
            cle = _cle_nom(nom)
            entree = par_surveillant.setdefault(
                cle,
                {
                    "nom": nom,
                    "nombre_surveillances": 0,
                    "duree_minutes": 0,
                    "dates": set(),
                    "semestres": {},
                    "ecues": set(),
                    "derniere_date": None,
                    "niveaux": set(),
                },
            )
            entree["nombre_surveillances"] += 1
            entree["duree_minutes"] += minutes
            if jour:
                entree["dates"].add(jour)
                if (
                    entree["derniere_date"] is None
                    or jour > entree["derniere_date"]
                ):
                    entree["derniere_date"] = jour
            nom_semestre = element.semestre_nom or "—"
            entree["semestres"][nom_semestre] = (
                entree["semestres"].get(nom_semestre, 0) + 1
            )
            if element.ecue_code:
                entree["ecues"].add(element.ecue_code)
            if element.niveau_nom:
                entree["niveaux"].add(element.niveau_nom)

            detail = semestre["surveillants"].setdefault(
                cle,
                {"nom": nom, "nombre_surveillances": 0, "dates": set()},
            )
            detail["nombre_surveillances"] += 1
            if jour:
                detail["dates"].add(jour)

    liste_surveillants = []
    for entree in par_surveillant.values():
        liste_surveillants.append(
            {
                "nom": entree["nom"],
                "nombre_surveillances": entree["nombre_surveillances"],
                "nombre_jours": len(entree["dates"]),
                "duree_minutes": entree["duree_minutes"],
                "semestres": [
                    {"nom": nom, "nombre_surveillances": nombre}
                    for nom, nombre in sorted(entree["semestres"].items())
                ],
                "ecues": sorted(entree["ecues"]),
                "niveaux": sorted(entree["niveaux"]),
                "derniere_date": entree["derniere_date"].isoformat()
                if entree["derniere_date"]
                else None,
            }
        )
    liste_surveillants.sort(
        key=lambda ligne: (
            -ligne["nombre_jours"],
            -ligne["nombre_surveillances"],
            _cle_nom(ligne["nom"]),
        )
    )

    liste_semestres = []
    for entree in par_semestre.values():
        surveillants = [
            {
                "nom": detail["nom"],
                "nombre_surveillances": detail["nombre_surveillances"],
                "nombre_jours": len(detail["dates"]),
            }
            for detail in entree["surveillants"].values()
        ]
        surveillants.sort(
            key=lambda ligne: (-ligne["nombre_jours"], _cle_nom(ligne["nom"]))
        )
        liste_semestres.append(
            {
                "semestre_id": entree["semestre_id"],
                "semestre_nom": entree["semestre_nom"],
                "annee": entree["annee"],
                "nombre_surveillances": entree["nombre_surveillances"],
                "nombre_jours": len(entree["dates"]),
                "nombre_surveillants": len(surveillants),
                "duree_minutes": entree["duree_minutes"],
                "surveillants": surveillants,
            }
        )
    liste_semestres.sort(
        key=lambda ligne: (ligne["annee"], ligne["semestre_nom"]), reverse=True
    )

    return {
        "resume": {
            "surveillances": len(elements),
            "surveillants": len(par_surveillant),
            "jours": len(jours_globaux),
            "duree_minutes": minutes_globales,
            "premiere_date": min(dates_globales).isoformat()
            if dates_globales
            else None,
            "derniere_date": max(dates_globales).isoformat()
            if dates_globales
            else None,
        },
        "par_surveillant": liste_surveillants,
        "par_semestre": liste_semestres,
    }


@router.get("/statistiques")
def statistiques(
    semestre_id: Optional[int] = None,
    niveau_id: Optional[int] = None,
    ecue_id: Optional[int] = None,
    date_debut: Optional[date] = None,
    date_fin: Optional[date] = None,
    q: str = Query(""),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Statistiques par surveillant et par semestre (jours = dates distinctes)."""
    elements = _requete(
        db, semestre_id, niveau_id, ecue_id, date_debut, date_fin, q
    ).all()
    return _calculer_statistiques(elements)


@router.get("/statistiques/exporter")
def exporter_statistiques(
    semestre_id: Optional[int] = None,
    niveau_id: Optional[int] = None,
    ecue_id: Optional[int] = None,
    date_debut: Optional[date] = None,
    date_fin: Optional[date] = None,
    q: str = Query(""),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Export Excel des statistiques de surveillances."""
    elements = _requete(
        db, semestre_id, niveau_id, ecue_id, date_debut, date_fin, q
    ).all()
    donnees = _calculer_statistiques(elements)
    return _flux_classeur(_classeur_statistiques(donnees), "statistiques_surveillances.xlsx")


# ------------------------------------------------------------------ Modèle Excel
def _entetes_modele(feuille, entetes: list[str], largeurs: list[int]):
    feuille.append(entetes)
    for cellule in feuille[1]:
        cellule.font = Font(bold=True, color="FFFFFF")
        cellule.fill = PatternFill("solid", fgColor="1E3A8A")
        cellule.alignment = cellule.alignment.copy(
            horizontal="center", vertical="center"
        )
    feuille.freeze_panes = "A2"
    for index, largeur in enumerate(largeurs, start=1):
        feuille.column_dimensions[
            feuille.cell(row=1, column=index).column_letter
        ].width = largeur


@router.get("/modele")
def modele(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Modèle Excel d'importation des surveillances."""
    classeur = Workbook()
    feuille = classeur.active
    feuille.title = "Surveillances"
    entetes = [
        "ECUE",
        "Niveau",
        "Semestre",
        "Type d'évaluation",
        "Durée (min)",
        "Date",
        "Surveillants",
        "Salle",
        "Observation",
        "Session",
    ]
    _entetes_modele(feuille, entetes, [18, 22, 24, 20, 14, 14, 46, 16, 34, 10])

    aide = classeur.create_sheet("Lisez-moi")
    aide["A1"] = "Modèle d'importation des surveillances"
    aide["A1"].font = Font(bold=True, size=14)
    instructions = [
        "Renseignez une ligne par surveillance dans la feuille « Surveillances ».",
        "Ne modifiez pas les en-têtes de la première ligne.",
        "ECUE : code de l'ECUE (ex. INF101) ou son intitulé. La feuille « Référentiel ECUE » liste les valeurs acceptées.",
        "Niveau : facultatif ; il est déduit de l'ECUE lorsqu'il est vide.",
        "Semestre : facultatif ; il est déduit de l'ECUE. Si le code ECUE existe dans plusieurs semestres, précisez le nom et l'année (ex. Semestre 1 2026-2027).",
        "Type d'évaluation : Examen, Devoir, Contrôle continu, TP, Oral, Projet ou Rattrapage.",
        "Durée : en minutes (120), ou au format 2h, 1h30.",
        "Date : JJ/MM/AAAA (une date Excel est également acceptée).",
        "Surveillants : plusieurs noms séparés par ; | ou /. Exemple : M. DIARRA ; Mme TRAORÉ.",
        "La feuille « Surveillants » liste le registre des surveillants et les enseignants disponibles.",
        "Session : 1 (session normale) ou 2 (rattrapage). Vide = 1.",
        "Ré-importer une même surveillance (même ECUE, même date, même type et même session) met à jour ses informations au lieu de la dupliquer.",
        "",
        "Exemple de ligne :",
        "INF101 | Licence 1 Informatique | Semestre 1 · 2026-2027 | Examen | 120 | 15/01/2027 | M. DIARRA ; Mme TRAORÉ | Amphi A | — | 1",
    ]
    for index, texte in enumerate(instructions, start=3):
        aide.cell(row=index, column=1, value=texte)
    aide.column_dimensions["A"].width = 120

    reference = classeur.create_sheet("Référentiel ECUE")
    _entetes_modele(
        reference,
        ["Code ECUE", "Intitulé", "Niveau", "Semestre", "UE"],
        [18, 46, 28, 30, 34],
    )
    for ecue in db.query(ECUE).options(joinedload(ECUE.ue), joinedload(ECUE.semestre)).all():
        reference.append(
            [
                ecue.code,
                ecue.nom,
                ecue.niveau_nom,
                f"{ecue.semestre_nom} · {ecue.annee}"
                if ecue.semestre
                else "",
                f"{ecue.ue_code} — {ecue.ue_nom}" if ecue.ue else "",
            ]
        )

    surveillants = classeur.create_sheet("Surveillants")
    _entetes_modele(
        surveillants,
        [
            "Nom du surveillant",
            "Origine",
            "Téléphone",
            "Email",
            "Fonction / Grade",
            "Département",
        ],
        [36, 14, 18, 30, 22, 30],
    )
    for surveillant in (
        db.query(Surveillant)
        .order_by(Surveillant.nom, Surveillant.prenom)
        .all()
    ):
        surveillants.append(
            [
                surveillant.nom_affichage,
                "Surveillant",
                surveillant.telephone,
                surveillant.email,
                surveillant.fonction,
                "",
            ]
        )
    for enseignant in (
        db.query(Enseignant)
        .options(joinedload(Enseignant.departement))
        .order_by(Enseignant.nom, Enseignant.prenom)
        .all()
    ):
        surveillants.append(
            [
                enseignant.nom_affichage,
                "Enseignant",
                enseignant.telephone,
                enseignant.email,
                enseignant.grade,
                enseignant.departement_nom,
            ]
        )

    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    return StreamingResponse(
        flux,
        media_type=MIME_XLSX,
        headers={
            "Content-Disposition": 'attachment; filename="modele_import_surveillances.xlsx"'
        },
    )


# ------------------------------------------------------------------ Exports Excel
def _duree_texte(minutes) -> str:
    """Durée lisible pour les exports : 90 → « 1 h 30 »."""
    total = int(minutes or 0)
    heures, reste = divmod(total, 60)
    if heures and reste:
        return f"{heures} h {reste:02d}"
    if heures:
        return f"{heures} h"
    return f"{total} min"


def _classeur_statistiques(donnees: dict) -> Workbook:
    """Classeur Excel des statistiques : résumé, surveillants, semestres."""
    classeur = Workbook()
    resume = donnees["resume"]
    feuille = classeur.active
    feuille.title = "Résumé"
    _entetes_modele(feuille, ["Indicateur", "Valeur"], [42, 24])
    lignes = [
        ("Surveillances", resume["surveillances"]),
        ("Surveillants", resume["surveillants"]),
        ("Jours de surveillance", resume["jours"]),
        ("Durée totale", _duree_texte(resume["duree_minutes"])),
        ("Durée totale (min)", resume["duree_minutes"]),
        ("Première date", _date_texte(resume["premiere_date"])),
        ("Dernière date", _date_texte(resume["derniere_date"])),
    ]
    for libelle, valeur in lignes:
        feuille.append([libelle, valeur])

    par_surveillant = classeur.create_sheet("Par surveillant")
    _entetes_modele(
        par_surveillant,
        [
            "Surveillant",
            "Surveillances",
            "Jours",
            "Durée",
            "Durée (min)",
            "Dernière date",
            "ECUE",
            "Niveaux",
        ],
        [34, 14, 10, 12, 12, 14, 40, 34],
    )
    for ligne in donnees["par_surveillant"]:
        par_surveillant.append(
            [
                ligne["nom"],
                ligne["nombre_surveillances"],
                ligne["nombre_jours"],
                _duree_texte(ligne["duree_minutes"]),
                ligne["duree_minutes"],
                _date_texte(ligne["derniere_date"]),
                ", ".join(ligne["ecues"]),
                ", ".join(ligne["niveaux"]),
            ]
        )
    par_surveillant.auto_filter.ref = par_surveillant.dimensions

    par_semestre = classeur.create_sheet("Par semestre")
    _entetes_modele(
        par_semestre,
        [
            "Semestre",
            "Année",
            "Surveillances",
            "Jours",
            "Surveillants",
            "Durée",
            "Durée (min)",
        ],
        [18, 14, 14, 10, 14, 12, 12],
    )
    for ligne in donnees["par_semestre"]:
        par_semestre.append(
            [
                ligne["semestre_nom"],
                ligne["annee"],
                ligne["nombre_surveillances"],
                ligne["nombre_jours"],
                ligne["nombre_surveillants"],
                _duree_texte(ligne["duree_minutes"]),
                ligne["duree_minutes"],
            ]
        )
    par_semestre.auto_filter.ref = par_semestre.dimensions

    detail = classeur.create_sheet("Surveillants par semestre")
    _entetes_modele(
        detail,
        ["Semestre", "Année", "Surveillant", "Surveillances", "Jours"],
        [18, 14, 34, 14, 10],
    )
    for semestre in donnees["par_semestre"]:
        for surveillant in semestre["surveillants"]:
            detail.append(
                [
                    semestre["semestre_nom"],
                    semestre["annee"],
                    surveillant["nom"],
                    surveillant["nombre_surveillances"],
                    surveillant["nombre_jours"],
                ]
            )
    detail.auto_filter.ref = detail.dimensions
    return classeur


def _date_texte(valeur) -> str:
    """Date ISO (AAAA-MM-JJ) → JJ/MM/AAAA, vide si absente."""
    if not valeur:
        return ""
    try:
        return date.fromisoformat(str(valeur)[:10]).strftime("%d/%m/%Y")
    except ValueError:
        return str(valeur)


def _flux_classeur(classeur: Workbook, nom: str) -> StreamingResponse:
    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    return StreamingResponse(
        flux,
        media_type=MIME_XLSX,
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/exporter")
def exporter_surveillances(
    semestre_id: Optional[int] = None,
    niveau_id: Optional[int] = None,
    ecue_id: Optional[int] = None,
    date_debut: Optional[date] = None,
    date_fin: Optional[date] = None,
    q: str = Query(""),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Export Excel de la liste des surveillances filtrées."""
    elements = _requete(
        db, semestre_id, niveau_id, ecue_id, date_debut, date_fin, q
    ).all()
    elements.sort(key=lambda element: (element.date_evaluation, element.id))

    classeur = Workbook()
    feuille = classeur.active
    feuille.title = "Surveillances"
    _entetes_modele(
        feuille,
        [
            "Date",
            "ECUE",
            "Intitulé ECUE",
            "Niveau",
            "Semestre",
            "Année",
            "Type d'évaluation",
            "Durée (min)",
            "Durée",
            "Session",
            "Salle",
            "Surveillants",
            "Observation",
        ],
        [12, 14, 40, 24, 16, 14, 18, 12, 10, 9, 16, 46, 34],
    )
    for element in elements:
        feuille.append(
            [
                element.date_evaluation.strftime("%d/%m/%Y")
                if element.date_evaluation
                else "",
                element.ecue_code,
                element.ecue_nom,
                element.niveau_nom,
                element.semestre_nom,
                element.annee,
                element.type_evaluation,
                element.duree_minutes,
                _duree_texte(element.duree_minutes),
                element.session,
                element.salle or "",
                element.surveillants_texte,
                element.observation or "",
            ]
        )
    feuille.auto_filter.ref = feuille.dimensions
    return _flux_classeur(classeur, "surveillances.xlsx")


# ------------------------------------------------------------------ Import Excel
def _index_ecues(db: Session):
    ecues = db.query(ECUE).options(joinedload(ECUE.ue)).all()
    par_code: dict[str, list[ECUE]] = {}
    par_nom: dict[str, list[ECUE]] = {}
    for ecue in ecues:
        par_code.setdefault(_cle(ecue.code), []).append(ecue)
        par_nom.setdefault(_cle(ecue.nom), []).append(ecue)
    return ecues, par_code, par_nom


def _index_semestres(db: Session) -> dict[str, Semestre]:
    index: dict[str, Semestre] = {}
    par_nom: dict[str, list[Semestre]] = {}
    for semestre in db.query(Semestre).all():
        par_nom.setdefault(_cle(semestre.nom), []).append(semestre)
        for libelle in (
            f"{semestre.nom} {semestre.annee}",
            f"{semestre.nom} · {semestre.annee}",
            f"{semestre.nom} - {semestre.annee}",
            f"{semestre.annee} {semestre.nom}",
        ):
            index[_cle(libelle)] = semestre
    # Le nom seul n'est utilisable que s'il désigne un unique semestre :
    # « Semestre 1 » existe dans plusieurs années universitaires.
    for nom, liste in par_nom.items():
        if len(liste) == 1:
            index[nom] = liste[0]
    return index


def _index_niveaux(db: Session) -> dict[str, Niveau]:
    index: dict[str, Niveau] = {}
    for niveau in db.query(Niveau).options(joinedload(Niveau.filiere)).all():
        index[_cle(niveau.nom)] = niveau
        if niveau.filiere:
            index[_cle(f"{niveau.nom} {niveau.filiere.code}")] = niveau
            index[_cle(f"{niveau.nom} - {niveau.filiere.code}")] = niveau
    return index


def _index_noms_surveillants(db: Session) -> dict[str, dict]:
    """Index des noms proposables : registre des surveillants puis enseignants.

    Le registre est prioritaire : un surveillant explicitement enregistré est
    rattaché à sa fiche même si un enseignant porte le même nom.
    """
    index: dict[str, dict] = {}
    for surveillant in db.query(Surveillant).filter(Surveillant.actif.is_(True)).all():
        for libelle in (surveillant.nom_affichage, surveillant.nom_complet):
            if libelle:
                index.setdefault(
                    _cle_nom(libelle),
                    {
                        "nom": surveillant.nom_affichage,
                        "enseignant_id": None,
                        "surveillant_id": surveillant.id,
                    },
                )
    for enseignant in db.query(Enseignant).all():
        for libelle in (
            enseignant.nom_complet,
            enseignant.nom_affichage,
            f"{enseignant.nom} {enseignant.prenom}",
        ):
            index.setdefault(
                _cle_nom(libelle),
                {
                    "nom": enseignant.nom_affichage,
                    "enseignant_id": enseignant.id,
                    "surveillant_id": None,
                },
            )
    return index


def _choisir_ecue(
    valeur: str,
    semestre: Optional[Semestre],
    par_code: dict[str, list[ECUE]],
    par_nom: dict[str, list[ECUE]],
) -> ECUE:
    candidats = par_code.get(_cle(valeur)) or par_nom.get(_cle(valeur)) or []
    if not candidats:
        raise ValueError(f"ECUE introuvable : {valeur}")
    if semestre is not None:
        correspondants = [
            ecue for ecue in candidats if ecue.semestre_id == semestre.id
        ]
        if correspondants:
            return correspondants[0]
        raise ValueError(
            f"L'ECUE {valeur} n'existe pas dans {semestre.nom} ({semestre.annee})"
        )
    if len(candidats) > 1:
        raise ValueError(
            f"Plusieurs ECUE portent le code {valeur} : précisez le semestre."
        )
    return candidats[0]


@router.post("/importer")
async def importer(
    fichier: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_gestionnaire_superviseur),
):
    """Importe des surveillances depuis un classeur Excel (création ou mise à jour)."""
    if not (fichier.filename or "").lower().endswith((".xlsx", ".xlsm")):
        raise HTTPException(400, "Le fichier doit être au format .xlsx")
    try:
        classeur = load_workbook(BytesIO(await fichier.read()), data_only=True)
    except Exception:
        raise HTTPException(400, "Impossible de lire le classeur Excel")

    feuille = None
    for candidate in classeur.worksheets:
        if _cle(candidate.title) in ("surveillances", "surveillance"):
            feuille = candidate
            break
    if feuille is None:
        feuille = classeur.worksheets[0] if classeur.worksheets else None
    if feuille is None:
        raise HTTPException(400, "Le classeur ne contient aucune feuille.")

    entetes = {
        _cle(cellule.value): cellule.column - 1
        for cellule in feuille[1]
        if cellule.value
    }
    if "ecue" not in entetes:
        raise HTTPException(400, "Colonne obligatoire manquante : ECUE.")
    if "date" not in entetes:
        raise HTTPException(400, "Colonne obligatoire manquante : Date.")

    def valeur(ligne, *noms):
        for nom in noms:
            index = entetes.get(_cle(nom))
            if index is not None and index < len(ligne):
                return ligne[index]
        return None

    ecues, par_code, par_nom = _index_ecues(db)
    semestres = _index_semestres(db)
    niveaux = _index_niveaux(db)
    index_noms = _index_noms_surveillants(db)

    importes = 0
    crees = 0
    mis_a_jour = 0
    erreurs: list[dict] = []

    for numero, ligne in enumerate(
        feuille.iter_rows(min_row=2, values_only=True), start=2
    ):
        if all(cellule in (None, "") for cellule in ligne):
            continue
        try:
            code_ecue = _texte(valeur(ligne, "ECUE", "Code ECUE", "Code"))
            if not code_ecue:
                raise ValueError("ECUE obligatoire")

            libelle_semestre = _texte(valeur(ligne, "Semestre"))
            semestre = None
            if libelle_semestre:
                semestre = semestres.get(_cle(libelle_semestre))
                if not semestre:
                    raise ValueError(
                        f"Semestre introuvable ou ambigu : {libelle_semestre} "
                        "(précisez l'année, ex. « Semestre 1 2026-2027 »)"
                    )

            ecue = _choisir_ecue(code_ecue, semestre, par_code, par_nom)
            if not ecue.semestre_id:
                raise ValueError(f"L'ECUE {code_ecue} n'est rattachée à aucun semestre")

            libelle_niveau = _texte(valeur(ligne, "Niveau"))
            niveau_id = ecue.niveau_id
            if libelle_niveau:
                niveau = niveaux.get(_cle(libelle_niveau))
                if not niveau:
                    raise ValueError(f"Niveau introuvable : {libelle_niveau}")
                niveau_id = niveau.id

            date_surveillance = _date_import(valeur(ligne, "Date"))
            if date_surveillance is None:
                raise ValueError("Date obligatoire")

            type_evaluation = (
                _texte(valeur(ligne, "Type d'évaluation", "Type evaluation", "Type"))
                or "Examen"
            )
            duree = _duree_minutes(valeur(ligne, "Durée (min)", "Duree", "Durée"))
            try:
                session = int(float(_texte(valeur(ligne, "Session")) or 1))
            except ValueError:
                raise ValueError("Session invalide")
            salle = _texte(valeur(ligne, "Salle"))
            observation = _texte(valeur(ligne, "Observation", "Observations"))

            noms_surveillants = _decouper_surveillants(
                valeur(ligne, "Surveillants", "Surveillant", "Noms des surveillants")
            )
            if not noms_surveillants:
                raise ValueError("Indiquez au moins un surveillant")

            element = (
                db.query(Surveillance)
                .filter(
                    Surveillance.ecue_id == ecue.id,
                    Surveillance.date_evaluation == date_surveillance,
                    Surveillance.type_evaluation == type_evaluation,
                    Surveillance.session == session,
                )
                .first()
            )
            if element is None:
                element = Surveillance(
                    ecue_id=ecue.id,
                    semestre_id=ecue.semestre_id,
                    date_evaluation=date_surveillance,
                    type_evaluation=type_evaluation,
                    session=session,
                )
                db.add(element)
                crees += 1
            else:
                mis_a_jour += 1

            element.semestre_id = ecue.semestre_id
            element.niveau_id = niveau_id
            element.duree_minutes = duree
            element.salle = salle
            element.observation = observation

            element.surveillants.clear()
            vus: set[str] = set()
            for nom in noms_surveillants:
                cle = _cle_nom(nom)
                if cle in vus:
                    continue
                vus.add(cle)
                correspondance = index_noms.get(cle)
                element.surveillants.append(
                    SurveillanceSurveillant(
                        nom=correspondance["nom"] if correspondance else nom,
                        enseignant_id=(
                            correspondance["enseignant_id"] if correspondance else None
                        ),
                        surveillant_id=(
                            correspondance["surveillant_id"]
                            if correspondance
                            else None
                        ),
                    )
                )

            db.commit()
            importes += 1
        except Exception as exc:
            db.rollback()
            erreurs.append(
                {"feuille": feuille.title, "ligne": numero, "message": str(exc)[:300]}
            )

    return {
        "importes": importes,
        "crees": crees,
        "mis_a_jour": mis_a_jour,
        "erreurs": erreurs,
        "message": (
            f"{importes} surveillance(s) importée(s) ({crees} créée(s), "
            f"{mis_a_jour} mise(s) à jour), {len(erreurs)} erreur(s)."
        ),
    }
