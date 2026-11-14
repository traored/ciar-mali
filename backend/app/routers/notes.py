"""API de l'espace « Gestion des notes » (8 modules)."""
import json
import unicodedata
from datetime import date, datetime
from io import BytesIO
from typing import Optional
from zipfile import ZIP_DEFLATED, ZipFile

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from openpyxl import Workbook, load_workbook
from openpyxl.comments import Comment
from openpyxl.styles import Font, PatternFill
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload, selectinload

from ..database import get_db
from ..models import (
    ECUE,
    Affectation,
    Etudiant,
    Evaluation,
    Filiere,
    Groupe,
    Inscription,
    Niveau,
    Note,
    PointJuryECUE,
    PointJuryUE,
    Presence,
    ResultatSemestre,
    Seance,
    Semestre,
    STATUTS_INSCRIPTION,
    TYPES_EVALUATION,
    UE,
    Utilisateur,
)
from ..notes_service import (
    MODES_SESSION2,
    calculer_et_enregistrer,
    calculer_semestre,
    coefficient_devoir,
    coefficient_examen,
    compensation_ecue,
    compensation_inter_ue,
    definir_coefficient_devoir,
    definir_coefficient_examen,
    definir_compensation_ecue,
    definir_compensation_inter_ue,
    definir_mode_session_2,
    definir_ponderation_ecue,
    enregistrer_signataires,
    lire_signataires,
    mode_session_2,
    moyenne_ecue,
    ponderation_ecue,
    precharger_donnees,
    resultat_inscription,
    resultats_passage,
    statistiques_semestre,
    diplomes_eligibles,
)
from ..pdf_notes import (
    generer_pdf_attestation,
    generer_pdf_diplome,
    generer_pdf_passages,
    generer_pdf_pv,
    generer_pdf_releve,
    generer_pdf_releve_passage,
)
from ..volumes import volumes_declares
from ..schemas import (
    DeliberationCreate,
    DeliberationOut,
    EtudiantCreate,
    EtudiantOut,
    EtudiantUpdate,
    EvaluationCreate,
    EvaluationOut,
    EvaluationUpdate,
    GenerationEvaluations,
    InscriptionCreate,
    InscriptionOut,
    InscriptionUpdate,
    NoteMasse,
    ParametresNotes,
    PointJuryLigne,
    PointsJuryECUEMasse,
    PointsJuryUEMasse,
    PresenceOut,
    PresencesMasse,
    ResultatOut,
    SignatairesNotes,
)
from ..security import (
    ROLE_ADMIN,
    ROLE_GESTIONNAIRE,
    admin_ou_gestionnaire,
    utilisateur_courant,
)

router = APIRouter(prefix="/api/notes", tags=["gestion des notes"])

DECISIONS = ("ADMIS", "AJOURNE", "RATTRAPAGE")


def _erreur_integrite(exc: IntegrityError):
    message = str(exc.orig)
    if "UNIQUE" in message.upper() or "DUPLICATE" in message.upper():
        raise HTTPException(409, "Un enregistrement avec ces valeurs existe déjà.")
    if "FOREIGN KEY" in message.upper():
        raise HTTPException(400, "Référence liée introuvable ou encore utilisée.")
    raise HTTPException(400, f"Opération impossible : {message}")


def _normaliser(texte) -> str:
    texte = unicodedata.normalize("NFKD", str(texte or ""))
    texte = "".join(c for c in texte if not unicodedata.combining(c))
    return texte.strip().lower().replace(" ", "_").replace("-", "_")


def _texte(valeur) -> str:
    if valeur is None:
        return ""
    if isinstance(valeur, float) and valeur.is_integer():
        return str(int(valeur))
    return str(valeur).strip()


def _nombre(valeur) -> Optional[float]:
    if valeur in (None, ""):
        return None
    try:
        return float(str(valeur).replace(",", ".").strip())
    except (TypeError, ValueError):
        raise ValueError(f"Note invalide : {valeur}")


def _date_import(valeur) -> Optional[date]:
    """Convertit une cellule Excel ou une chaîne en date (formats français inclus)."""
    if valeur in (None, ""):
        return None
    if isinstance(valeur, datetime):
        return valeur.date()
    if isinstance(valeur, date):
        return valeur
    texte = _texte(valeur)
    for format_ in ("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y", "%d/%m/%y"):
        try:
            return datetime.strptime(texte, format_).date()
        except ValueError:
            continue
    raise ValueError(f"Date invalide : {texte}")


MIME_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _classeur_modele(
    titre_feuille: str,
    entetes: list[str],
    largeurs: list[int],
    instructions: list[str] | None = None,
):
    """Construit un classeur modèle simple, prêt à être téléchargé."""
    classeur = Workbook()
    feuille = classeur.active
    feuille.title = titre_feuille
    feuille.append(entetes)
    for cellule in feuille[1]:
        cellule.font = Font(bold=True, color="FFFFFF")
        cellule.fill = PatternFill("solid", fgColor="1E3A8A")
        cellule.alignment = cellule.alignment.copy(horizontal="center", vertical="center")
    feuille.freeze_panes = "A2"
    for index, largeur in enumerate(largeurs, start=1):
        feuille.column_dimensions[feuille.cell(row=1, column=index).column_letter].width = largeur
    if instructions:
        aide = classeur.create_sheet("Lisez-moi")
        aide["A1"] = f"Modèle d'importation — {titre_feuille}"
        aide["A1"].font = Font(bold=True, size=14)
        for index, texte in enumerate(instructions, start=3):
            aide.cell(row=index, column=1, value=texte)
        aide.column_dimensions["A"].width = 110
    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    return flux


def _feuille_modele(classeur, *titres: str):
    """Retourne la feuille portant l'un des titres, sinon la première feuille."""
    for titre in titres:
        for feuille in classeur.worksheets:
            if _normaliser(feuille.title) == _normaliser(titre):
                return feuille
    return classeur.worksheets[0] if classeur.worksheets else None


# ========================================================== Contrôle des rôles
def _role(utilisateur: Utilisateur) -> str:
    return (utilisateur.role or "").strip().lower()


def _est_encadrement(utilisateur: Utilisateur) -> bool:
    return _role(utilisateur) in (ROLE_ADMIN, ROLE_GESTIONNAIRE)


def _est_enseignant(utilisateur: Utilisateur) -> bool:
    return _role(utilisateur) == "enseignant"


def _est_etudiant(utilisateur: Utilisateur) -> bool:
    return _role(utilisateur) == "lecteur"


def _volume_entier(valeur: float):
    """Volume horaire : entier lorsqu'il est rond, sinon décimale."""
    return int(valeur) if float(valeur).is_integer() else valeur


def _ecue_ids_enseignant(db: Session, utilisateur: Utilisateur) -> set[int]:
    if not utilisateur.enseignant_id:
        return set()
    return {
        ligne[0]
        for ligne in db.query(Affectation.ecue_id)
        .filter(Affectation.enseignant_id == utilisateur.enseignant_id)
        .distinct()
        .all()
    }


def _niveaux_enseignant(db: Session, utilisateur: Utilisateur) -> set[int]:
    ids = _ecue_ids_enseignant(db, utilisateur)
    if not ids:
        return set()
    niveaux: set[int] = set()
    for ue in (
        db.query(UE)
        .filter(UE.id.in_(db.query(ECUE.ue_id).filter(ECUE.id.in_(ids))))
        .all()
    ):
        niveaux.update(ue.niveau_ids)
    return niveaux


def _inscription_etudiant(db: Session, utilisateur: Utilisateur) -> Inscription | None:
    if not utilisateur.etudiant_id:
        return None
    return (
        db.query(Inscription)
        .filter(Inscription.etudiant_id == utilisateur.etudiant_id)
        .order_by(Inscription.annee.desc(), Inscription.id.desc())
        .first()
    )


def _verifier_ecue(db: Session, utilisateur: Utilisateur, ecue_id: int):
    if _est_encadrement(utilisateur):
        return
    if _est_enseignant(utilisateur) and ecue_id in _ecue_ids_enseignant(db, utilisateur):
        return
    raise HTTPException(403, "Cette ECUE ne relève pas de votre espace.")


def _verifier_evaluation(db: Session, utilisateur: Utilisateur, evaluation: Evaluation):
    if evaluation is None:
        raise HTTPException(404, "Évaluation introuvable")
    _verifier_ecue(db, utilisateur, evaluation.ecue_id)


def _verifier_inscription(db: Session, utilisateur: Utilisateur, inscription: Inscription):
    if inscription is None:
        raise HTTPException(404, "Inscription introuvable")
    if _est_encadrement(utilisateur):
        return
    if _est_enseignant(utilisateur):
        if inscription.niveau_id in _niveaux_enseignant(db, utilisateur):
            return
    elif _est_etudiant(utilisateur):
        if utilisateur.etudiant_id and inscription.etudiant_id == utilisateur.etudiant_id:
            return
    raise HTTPException(403, "Vous n’êtes pas autorisé à consulter cette inscription.")


def _verifier_seance(db: Session, utilisateur: Utilisateur, seance: Seance):
    if seance is None:
        raise HTTPException(404, "Séance introuvable")
    if _est_encadrement(utilisateur):
        return
    if _est_enseignant(utilisateur):
        if utilisateur.enseignant_id and seance.enseignant_id == utilisateur.enseignant_id:
            return
    elif _est_etudiant(utilisateur):
        groupes = {
            inscription.groupe_id
            for inscription in db.query(Inscription)
            .filter(Inscription.etudiant_id == utilisateur.etudiant_id)
            .all()
            if inscription.groupe_id
        }
        if groupes and groupes.intersection(seance.groupe_ids):
            return
    raise HTTPException(403, "Cette séance ne relève pas de votre espace.")


def _inscriptions_seance(db: Session, seance: Seance) -> list[Inscription]:
    requete = db.query(Inscription)
    if seance.semestre_id:
        annee = seance.semestre.annee if seance.semestre else None
        if annee:
            requete = requete.filter(Inscription.annee == annee)
    identifiants_groupes = [groupe.id for groupe in seance.groupes]
    if identifiants_groupes:
        requete = requete.filter(Inscription.groupe_id.in_(identifiants_groupes))
    elif seance.ecue and seance.ecue.ue:
        requete = requete.filter(
            Inscription.niveau_id.in_(seance.ecue.ue.niveau_ids)
        )
    return requete.order_by(Inscription.etudiant_id).all()


def _verifier_document_etudiant(utilisateur: Utilisateur, inscription: Inscription):
    if _est_encadrement(utilisateur):
        return
    if _est_etudiant(utilisateur):
        if utilisateur.etudiant_id and inscription.etudiant_id == utilisateur.etudiant_id:
            return
    raise HTTPException(403, "Vous ne pouvez consulter que vos propres documents.")


# ========================================================== Paramètres des notes
@router.get("/parametres")
def lire_parametres(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(utilisateur_courant),
):
    return {
        "compensation_ecue": compensation_ecue(db),
        "compensation_inter_ue": compensation_inter_ue(db),
        "ponderation_ecue": ponderation_ecue(db),
        "coefficient_devoir": coefficient_devoir(db),
        "coefficient_examen": coefficient_examen(db),
        "session2_mode": mode_session_2(db),
    }


@router.put("/parametres")
def maj_parametres(
    payload: ParametresNotes,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    compensation = compensation_ecue(db)
    if payload.compensation_ecue is not None:
        compensation = definir_compensation_ecue(db, payload.compensation_ecue)
    compensation_ue = compensation_inter_ue(db)
    if payload.compensation_inter_ue is not None:
        compensation_ue = definir_compensation_inter_ue(
            db, payload.compensation_inter_ue
        )
    ponderer = ponderation_ecue(db)
    if payload.ponderation_ecue is not None:
        ponderer = definir_ponderation_ecue(db, payload.ponderation_ecue)
    coef_devoir = coefficient_devoir(db)
    if payload.coefficient_devoir is not None:
        coef_devoir = definir_coefficient_devoir(db, payload.coefficient_devoir)
    coef_examen = coefficient_examen(db)
    if payload.coefficient_examen is not None:
        coef_examen = definir_coefficient_examen(db, payload.coefficient_examen)
    mode_session2 = mode_session_2(db)
    if payload.session2_mode is not None:
        if payload.session2_mode not in MODES_SESSION2:
            raise HTTPException(400, "Mode de session 2 invalide.")
        mode_session2 = definir_mode_session_2(db, payload.session2_mode)
    return {
        "compensation_ecue": compensation,
        "compensation_inter_ue": compensation_ue,
        "ponderation_ecue": ponderer,
        "coefficient_devoir": coef_devoir,
        "coefficient_examen": coef_examen,
        "session2_mode": mode_session2,
    }


# ========================================================== Signataires des documents
@router.get("/signataires")
def lire_signataires_endpoint(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(utilisateur_courant),
):
    return lire_signataires(db)


@router.put("/signataires")
def maj_signataires(
    payload: SignatairesNotes,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    return enregistrer_signataires(db, payload.model_dump())


# =============================================================== 1. Étudiants
@router.get("/etudiants", response_model=list[EtudiantOut])
def lister_etudiants(
    q: str = Query(""),
    filiere_id: Optional[int] = None,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    requete = db.query(Etudiant).options(
        joinedload(Etudiant.filiere),
        selectinload(Etudiant.inscriptions),
    )
    if _est_etudiant(utilisateur):
        if not utilisateur.etudiant_id:
            return []
        requete = requete.filter(Etudiant.id == utilisateur.etudiant_id)
    elif _est_enseignant(utilisateur):
        niveaux = _niveaux_enseignant(db, utilisateur)
        if not niveaux:
            return []
        requete = requete.filter(
            Etudiant.id.in_(
                db.query(Inscription.etudiant_id).filter(Inscription.niveau_id.in_(niveaux))
            )
        )
    if q.strip():
        cible = f"%{q.strip().lower()}%"
        requete = requete.filter(
            or_(
                Etudiant.nom.ilike(cible),
                Etudiant.prenom.ilike(cible),
                Etudiant.matricule.ilike(cible),
                Etudiant.email.ilike(cible),
            )
        )
    if filiere_id:
        requete = requete.filter(Etudiant.filiere_id == filiere_id)
    return requete.order_by(Etudiant.nom, Etudiant.prenom).all()


def _matricule_libre(db: Session, annee: int) -> str:
    compteur = db.query(Etudiant).count() + 1
    while True:
        matricule = f"ETU-{annee}-{compteur:04d}"
        if not db.query(Etudiant).filter(Etudiant.matricule == matricule).first():
            return matricule
        compteur += 1


@router.get("/etudiants/modele")
def modele_import_etudiants(
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Modèle Excel pour importer ou mettre à jour les étudiants."""
    entetes = [
        "Matricule",
        "Prénom",
        "Nom",
        "Sexe",
        "Date de naissance",
        "Lieu de naissance",
        "Téléphone",
        "Email",
        "Filière",
    ]
    flux = _classeur_modele(
        "Étudiants",
        entetes,
        [18, 18, 20, 9, 18, 20, 16, 26, 16],
        [
            "Renseignez une ligne par étudiant. Les colonnes doivent conserver leurs en-têtes.",
            "Le matricule est la clé : un étudiant existant est mis à jour, sinon il est créé.",
            "Si le matricule est vide, un matricule est généré automatiquement (ETU-AAAA-0001).",
            "Sexe : M ou F. Date de naissance : JJ/MM/AAAA.",
            "Filière : code de la filière (ex. INFO). Elle doit déjà exister dans l'application.",
        ],
    )
    return StreamingResponse(
        flux,
        media_type=MIME_XLSX,
        headers={"Content-Disposition": 'attachment; filename="modele_import_etudiants.xlsx"'},
    )


@router.post("/etudiants/importer")
async def importer_etudiants(
    fichier: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Importe les étudiants depuis un classeur Excel (création ou mise à jour)."""
    if not fichier.filename.lower().endswith((".xlsx", ".xlsm")):
        raise HTTPException(400, "Le fichier doit être au format .xlsx")
    try:
        classeur = load_workbook(BytesIO(await fichier.read()), data_only=True)
    except Exception:
        raise HTTPException(400, "Impossible de lire le classeur Excel")

    feuille = _feuille_modele(classeur, "Étudiants", "Etudiants")
    if feuille is None:
        raise HTTPException(400, "Le classeur ne contient aucune feuille.")
    entetes = {
        _normaliser(cellule.value): cellule.column - 1
        for cellule in feuille[1]
        if cellule.value
    }
    for requis in ("matricule", "prenom", "nom"):
        if requis not in entetes:
            raise HTTPException(
                400,
                "Colonnes obligatoires manquantes : Matricule, Prénom et Nom.",
            )

    def valeur(ligne, *noms):
        for nom in noms:
            index = entetes.get(_normaliser(nom))
            if index is not None and index < len(ligne):
                return ligne[index]
        return None

    filieres = {}
    for filiere in db.query(Filiere).all():
        filieres[_normaliser(filiere.code)] = filiere
        filieres[_normaliser(filiere.nom)] = filiere

    importes = 0
    crees = 0
    mis_a_jour = 0
    erreurs: list[dict] = []

    for numero, ligne in enumerate(feuille.iter_rows(min_row=2, values_only=True), start=2):
        if all(cellule in (None, "") for cellule in ligne):
            continue
        try:
            matricule = _texte(valeur(ligne, "Matricule"))
            prenom = _texte(valeur(ligne, "Prénom", "Prenom"))
            nom = _texte(valeur(ligne, "Nom"))
            if not prenom or not nom:
                raise ValueError("Prénom et nom obligatoires")
            element = None
            if matricule:
                element = db.query(Etudiant).filter(Etudiant.matricule == matricule).first()
            if element is None:
                if not matricule:
                    matricule = _matricule_libre(db, datetime.now().year)
                element = Etudiant(matricule=matricule)
                db.add(element)
                crees += 1
            else:
                mis_a_jour += 1

            element.prenom = prenom
            element.nom = nom
            sexe = _texte(valeur(ligne, "Sexe"))
            if sexe:
                normalise_sexe = _normaliser(sexe)
                if normalise_sexe in ("m", "masculin", "homme"):
                    element.sexe = "M"
                elif normalise_sexe in ("f", "feminin", "femme"):
                    element.sexe = "F"
                else:
                    raise ValueError(f"Sexe invalide : {sexe}")
            date_naissance = _date_import(valeur(ligne, "Date de naissance"))
            if date_naissance is not None:
                element.date_naissance = date_naissance
            lieu = _texte(valeur(ligne, "Lieu de naissance"))
            if lieu:
                element.lieu_naissance = lieu
            telephone = _texte(valeur(ligne, "Téléphone", "Telephone"))
            if telephone:
                element.telephone = telephone
            email = _texte(valeur(ligne, "Email"))
            if email:
                element.email = email
            code_filiere = _texte(valeur(ligne, "Filière", "Filiere", "Filière (code)"))
            if code_filiere:
                filiere = filieres.get(_normaliser(code_filiere))
                if not filiere:
                    raise ValueError(f"Filière introuvable : {code_filiere}")
                element.filiere_id = filiere.id
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
            f"{importes} étudiant(s) importé(s) ({crees} créé(s), "
            f"{mis_a_jour} mis à jour), {len(erreurs)} erreur(s)."
        ),
    }


@router.get("/etudiants/{etudiant_id}")
def detail_etudiant(
    etudiant_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur) and etudiant_id != utilisateur.etudiant_id:
        raise HTTPException(403, "Vous ne pouvez consulter que votre propre dossier.")
    etudiant = db.get(Etudiant, etudiant_id)
    if not etudiant:
        raise HTTPException(404, "Étudiant introuvable")
    if _est_enseignant(utilisateur):
        niveaux = _niveaux_enseignant(db, utilisateur)
        if not any(inscription.niveau_id in niveaux for inscription in etudiant.inscriptions):
            raise HTTPException(403, "Cet étudiant ne relève pas de vos cours.")
    parcours = []
    for inscription in sorted(
        etudiant.inscriptions, key=lambda i: (i.annee, i.niveau.ordre if i.niveau else 0)
    ):
        resultats = []
        for resultat in sorted(
            inscription.resultats, key=lambda r: (r.semestre_id, r.session)
        ):
            resultats.append(
                {
                    "semestre": resultat.semestre.nom if resultat.semestre else "",
                    "annee": resultat.semestre.annee if resultat.semestre else inscription.annee,
                    "session": resultat.session,
                    "moyenne": resultat.moyenne,
                    "credits_obtenus": resultat.credits_obtenus,
                    "credits_total": resultat.credits_total,
                    "statut": resultat.statut,
                    "decision": resultat.decision,
                    "mention": resultat.mention,
                }
            )
        parcours.append(
            {
                "id": inscription.id,
                "annee": inscription.annee,
                "niveau": inscription.niveau_nom,
                "filiere": inscription.filiere_nom,
                "groupe": inscription.groupe_nom,
                "statut": inscription.statut,
                "date_inscription": inscription.date_inscription.isoformat()
                if inscription.date_inscription
                else None,
                "resultats": resultats,
            }
        )
    return {
        "etudiant": {
            "id": etudiant.id,
            "matricule": etudiant.matricule,
            "nom_complet": etudiant.nom_complet,
            "sexe": etudiant.sexe,
            "email": etudiant.email,
            "telephone": etudiant.telephone,
            "date_naissance": etudiant.date_naissance.isoformat()
            if etudiant.date_naissance
            else None,
            "lieu_naissance": etudiant.lieu_naissance,
            "filiere": etudiant.filiere_nom,
        },
        "parcours": parcours,
    }


@router.post("/etudiants", response_model=EtudiantOut, status_code=201)
def creer_etudiant(
    payload: EtudiantCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    donnees = payload.model_dump()
    matricule = (donnees.pop("matricule") or "").strip()
    if not matricule:
        matricule = _matricule_libre(db, datetime.now().year)
    if db.query(Etudiant).filter(Etudiant.matricule == matricule).first():
        raise HTTPException(409, f"Le matricule {matricule} existe déjà.")
    element = Etudiant(matricule=matricule, **donnees)
    db.add(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.put("/etudiants/{etudiant_id}", response_model=EtudiantOut)
def modifier_etudiant(
    etudiant_id: int,
    payload: EtudiantUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Etudiant, etudiant_id)
    if not element:
        raise HTTPException(404, "Étudiant introuvable")
    donnees = payload.model_dump(exclude_unset=True)
    if "matricule" in donnees:
        matricule = (donnees.pop("matricule") or "").strip()
        if not matricule:
            raise HTTPException(400, "Le matricule est obligatoire.")
        if (
            db.query(Etudiant)
            .filter(Etudiant.matricule == matricule, Etudiant.id != etudiant_id)
            .first()
        ):
            raise HTTPException(409, f"Le matricule {matricule} existe déjà.")
        element.matricule = matricule
    for cle, valeur in donnees.items():
        setattr(element, cle, valeur)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.delete("/etudiants/{etudiant_id}")
def supprimer_etudiant(
    etudiant_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Etudiant, etudiant_id)
    if not element:
        raise HTTPException(404, "Étudiant introuvable")
    db.delete(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    return {"ok": True, "message": "Étudiant supprimé"}


# =============================================================== Inscriptions
@router.get("/inscriptions/modele")
def modele_import_inscriptions(
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Modèle Excel pour importer les inscriptions par étudiant et par niveau."""
    entetes = [
        "Matricule étudiant",
        "Année",
        "Niveau",
        "Filière",
        "Groupe",
        "Statut",
        "Date d'inscription",
    ]
    flux = _classeur_modele(
        "Inscriptions",
        entetes,
        [20, 14, 18, 16, 14, 16, 18],
        [
            "Renseignez une ligne par inscription. Les colonnes doivent conserver leurs en-têtes.",
            "Importez d'abord les étudiants : le matricule doit déjà exister.",
            "Année : année universitaire d'inscription (ex. 2026-2027).",
            "Niveau : nom exact du niveau (ex. Licence 1). Filière : code de la filière (ex. INFO).",
            "Groupe : nom du groupe existant pour ce niveau. Statut : Inscrit, Redoublant, Rattrapage, Diplômé ou Abandon.",
            "Date d'inscription : JJ/MM/AAAA (facultative).",
        ],
    )
    return StreamingResponse(
        flux,
        media_type=MIME_XLSX,
        headers={
            "Content-Disposition": 'attachment; filename="modele_import_inscriptions.xlsx"'
        },
    )


@router.post("/inscriptions/importer")
async def importer_inscriptions(
    fichier: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Importe les inscriptions depuis un classeur Excel (création ou mise à jour)."""
    if not fichier.filename.lower().endswith((".xlsx", ".xlsm")):
        raise HTTPException(400, "Le fichier doit être au format .xlsx")
    try:
        classeur = load_workbook(BytesIO(await fichier.read()), data_only=True)
    except Exception:
        raise HTTPException(400, "Impossible de lire le classeur Excel")

    feuille = _feuille_modele(classeur, "Inscriptions")
    if feuille is None:
        raise HTTPException(400, "Le classeur ne contient aucune feuille.")
    entetes = {
        _normaliser(cellule.value): cellule.column - 1
        for cellule in feuille[1]
        if cellule.value
    }
    for requis in ("matricule_etudiant", "annee", "niveau"):
        if requis not in entetes:
            raise HTTPException(
                400,
                "Colonnes obligatoires manquantes : Matricule étudiant, Année et Niveau.",
            )

    def valeur(ligne, *noms):
        for nom in noms:
            index = entetes.get(_normaliser(nom))
            if index is not None and index < len(ligne):
                return ligne[index]
        return None

    niveaux = db.query(Niveau).all()

    def trouver_niveau(nom_niveau: str, code_filiere: str) -> Niveau | None:
        candidats = [
            niveau
            for niveau in niveaux
            if _normaliser(niveau.nom) == _normaliser(nom_niveau)
        ]
        if code_filiere:
            reference = _normaliser(code_filiere)
            candidats = [
                niveau
                for niveau in candidats
                if niveau.filiere
                and reference
                in {_normaliser(niveau.filiere.code), _normaliser(niveau.filiere.nom)}
            ]
        return candidats[0] if len(candidats) == 1 else None

    importes = 0
    crees = 0
    mis_a_jour = 0
    erreurs: list[dict] = []

    for numero, ligne in enumerate(feuille.iter_rows(min_row=2, values_only=True), start=2):
        if all(cellule in (None, "") for cellule in ligne):
            continue
        try:
            matricule = _texte(valeur(ligne, "Matricule étudiant", "Matricule"))
            annee = _texte(valeur(ligne, "Année", "Annee", "Année académique"))
            nom_niveau = _texte(valeur(ligne, "Niveau"))
            code_filiere = _texte(valeur(ligne, "Filière", "Filiere", "Filière (code)"))
            if not matricule:
                raise ValueError("Matricule étudiant obligatoire")
            if not annee:
                raise ValueError("Année obligatoire")
            if not nom_niveau:
                raise ValueError("Niveau obligatoire")
            etudiant = db.query(Etudiant).filter(Etudiant.matricule == matricule).first()
            if not etudiant:
                raise ValueError(f"Étudiant introuvable : {matricule}")
            niveau = trouver_niveau(nom_niveau, code_filiere)
            if niveau is None:
                precision = f" / filière {code_filiere}" if code_filiere else ""
                raise ValueError(f"Niveau introuvable ou ambigu : {nom_niveau}{precision}")

            element = (
                db.query(Inscription)
                .filter(
                    Inscription.etudiant_id == etudiant.id,
                    Inscription.annee == annee,
                    Inscription.niveau_id == niveau.id,
                )
                .first()
            )
            if element is None:
                element = Inscription(
                    etudiant_id=etudiant.id,
                    annee=annee,
                    niveau_id=niveau.id,
                    date_inscription=date.today(),
                )
                db.add(element)
                crees += 1
            else:
                mis_a_jour += 1

            nom_groupe = _texte(valeur(ligne, "Groupe"))
            if nom_groupe:
                groupe = (
                    db.query(Groupe)
                    .filter(
                        Groupe.niveau_id == niveau.id,
                        Groupe.nom == nom_groupe,
                    )
                    .first()
                )
                if not groupe:
                    raise ValueError(f"Groupe introuvable pour ce niveau : {nom_groupe}")
                element.groupe_id = groupe.id
            statut = _texte(valeur(ligne, "Statut"))
            if statut:
                if statut not in STATUTS_INSCRIPTION:
                    raise ValueError(f"Statut d’inscription invalide : {statut}")
                element.statut = statut
            date_inscription = _date_import(valeur(ligne, "Date d'inscription", "Date inscription"))
            if date_inscription is not None:
                element.date_inscription = date_inscription
            if etudiant.filiere_id is None and niveau.filiere_id:
                etudiant.filiere_id = niveau.filiere_id
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
            f"{importes} inscription(s) importée(s) ({crees} créée(s), "
            f"{mis_a_jour} mise(s) à jour), {len(erreurs)} erreur(s)."
        ),
    }


@router.get("/inscriptions", response_model=list[InscriptionOut])
def lister_inscriptions(
    etudiant_id: Optional[int] = None,
    niveau_id: Optional[int] = None,
    annee: Optional[str] = None,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    requete = db.query(Inscription).options(
        joinedload(Inscription.etudiant),
        joinedload(Inscription.niveau).joinedload(Niveau.filiere),
        joinedload(Inscription.groupe),
    )
    if _est_etudiant(utilisateur):
        if not utilisateur.etudiant_id:
            return []
        requete = requete.filter(Inscription.etudiant_id == utilisateur.etudiant_id)
    elif _est_enseignant(utilisateur):
        niveaux = _niveaux_enseignant(db, utilisateur)
        if not niveaux:
            return []
        requete = requete.filter(Inscription.niveau_id.in_(niveaux))
        if etudiant_id:
            requete = requete.filter(Inscription.etudiant_id == etudiant_id)
    elif etudiant_id:
        requete = requete.filter(Inscription.etudiant_id == etudiant_id)
    if niveau_id:
        requete = requete.filter(Inscription.niveau_id == niveau_id)
    if annee:
        requete = requete.filter(Inscription.annee == annee)
    return requete.order_by(Inscription.annee.desc(), Inscription.etudiant_id).all()


@router.post("/inscriptions", response_model=InscriptionOut, status_code=201)
def creer_inscription(
    payload: InscriptionCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    donnees = payload.model_dump()
    if donnees.get("statut") not in STATUTS_INSCRIPTION:
        raise HTTPException(400, "Statut d’inscription invalide.")
    if donnees.get("date_inscription") is None:
        donnees["date_inscription"] = date.today()
    element = Inscription(**donnees)
    db.add(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.put("/inscriptions/{inscription_id}", response_model=InscriptionOut)
def modifier_inscription(
    inscription_id: int,
    payload: InscriptionUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Inscription, inscription_id)
    if not element:
        raise HTTPException(404, "Inscription introuvable")
    donnees = payload.model_dump(exclude_unset=True)
    if "statut" in donnees and donnees["statut"] not in STATUTS_INSCRIPTION:
        raise HTTPException(400, "Statut d’inscription invalide.")
    for cle, valeur in donnees.items():
        setattr(element, cle, valeur)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.delete("/inscriptions/{inscription_id}")
def supprimer_inscription(
    inscription_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Inscription, inscription_id)
    if not element:
        raise HTTPException(404, "Inscription introuvable")
    db.delete(element)
    db.commit()
    return {"ok": True, "message": "Inscription supprimée"}


# ================================================= 2 bis. Cours d'un enseignant
@router.get("/mes-cours")
def mes_cours(
    semestre_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Cours d'un enseignant pour un semestre, avec les étudiants inscrits.

    Un cours regroupe les affectations d'un même ECUE. Les étudiants listés
    sont ceux des groupes affectés, ou tout le niveau lorsque l'affectation
    est marquée « CM commun ».
    """
    if not _est_enseignant(utilisateur):
        raise HTTPException(403, "Espace réservé aux enseignants.")
    semestre = db.get(Semestre, semestre_id)
    if semestre is None:
        raise HTTPException(404, "Semestre introuvable")
    entete_semestre = {
        "id": semestre.id,
        "nom": semestre.nom,
        "annee": semestre.annee,
    }
    if not utilisateur.enseignant_id:
        return {"semestre": entete_semestre, "cours": []}

    affectations = (
        db.query(Affectation)
        .options(
            joinedload(Affectation.ecue)
            .joinedload(ECUE.ue)
            .joinedload(UE.niveau)
            .joinedload(Niveau.filiere),
            joinedload(Affectation.groupe)
            .joinedload(Groupe.niveau)
            .joinedload(Niveau.filiere),
        )
        .filter(
            Affectation.enseignant_id == utilisateur.enseignant_id,
            Affectation.semestre_id == semestre_id,
        )
        .order_by(Affectation.ecue_id, Affectation.groupe_id)
        .all()
    )

    cours: dict[int, dict] = {}
    ids_niveaux: set[int] = set()
    for affectation in affectations:
        ecue = affectation.ecue
        if ecue is None:
            continue
        ue = ecue.ue
        niveau = ue.niveau if ue else None
        entree = cours.setdefault(
            ecue.id,
            {
                "ecue_id": ecue.id,
                "ecue_code": ecue.code,
                "ecue_nom": ecue.nom,
                "ue_code": ue.code if ue else "",
                "ue_nom": ue.nom if ue else "",
                "niveau_id": niveau.id if niveau else None,
                "niveau_nom": niveau.nom if niveau else "",
                "filiere_code": (
                    niveau.filiere.code if niveau and niveau.filiere else ""
                ),
                "heures_cm": 0,
                "heures_td": 0,
                "heures_tp": 0,
                "cm_commun": False,
                "groupes": [],
                "_affectations": [],
                "_groupes_ids": set(),
                "_niveaux_cm": set(),
            },
        )
        entree["_affectations"].append(affectation)
        groupe = affectation.groupe
        if groupe is not None:
            ids_niveaux.add(groupe.niveau_id)
            if not any(g["id"] == groupe.id for g in entree["groupes"]):
                entree["groupes"].append({"id": groupe.id, "nom": groupe.nom})
            if affectation.cm_commun:
                entree["_niveaux_cm"].add(groupe.niveau_id)
            else:
                entree["_groupes_ids"].add(groupe.id)
        elif niveau is not None:
            ids_niveaux.add(niveau.id)
            if affectation.cm_commun:
                entree["_niveaux_cm"].add(niveau.id)
        if affectation.cm_commun:
            entree["cm_commun"] = True

    inscriptions: list[Inscription] = []
    if cours and ids_niveaux:
        inscriptions = (
            db.query(Inscription)
            .options(
                joinedload(Inscription.etudiant),
                joinedload(Inscription.groupe),
            )
            .filter(
                Inscription.annee == semestre.annee,
                Inscription.niveau_id.in_(ids_niveaux),
            )
            .order_by(Inscription.etudiant_id)
            .all()
        )

    liste_cours = []
    for entree in cours.values():
        # Les affectations font foi ; un CM mutualisé n'est compté qu'une fois
        # par niveau, quel que soit le nombre de groupes affectés.
        volumes = volumes_declares(entree.pop("_affectations", []))
        entree["heures_cm"] = _volume_entier(volumes["cm"])
        entree["heures_td"] = _volume_entier(volumes["td"])
        entree["heures_tp"] = _volume_entier(volumes["tp"])
        if entree["cm_commun"]:
            retenues = [
                inscription
                for inscription in inscriptions
                if inscription.niveau_id in entree["_niveaux_cm"]
            ]
        else:
            retenues = [
                inscription
                for inscription in inscriptions
                if inscription.groupe_id in entree["_groupes_ids"]
            ]
        etudiants = sorted(
            (
                {
                    "inscription_id": inscription.id,
                    "etudiant_id": inscription.etudiant_id,
                    "matricule": inscription.etudiant.matricule
                    if inscription.etudiant
                    else "",
                    "nom_complet": inscription.etudiant.nom_complet
                    if inscription.etudiant
                    else "",
                    "groupe_nom": inscription.groupe.nom
                    if inscription.groupe
                    else "",
                    "statut": inscription.statut,
                }
                for inscription in retenues
            ),
            key=lambda ligne: ligne["nom_complet"],
        )
        liste_cours.append(
            {
                "ecue_id": entree["ecue_id"],
                "ecue_code": entree["ecue_code"],
                "ecue_nom": entree["ecue_nom"],
                "ue_code": entree["ue_code"],
                "ue_nom": entree["ue_nom"],
                "niveau_id": entree["niveau_id"],
                "niveau_nom": entree["niveau_nom"],
                "filiere_code": entree["filiere_code"],
                "heures_cm": entree["heures_cm"],
                "heures_td": entree["heures_td"],
                "heures_tp": entree["heures_tp"],
                "total_heures": entree["heures_cm"]
                + entree["heures_td"]
                + entree["heures_tp"],
                "cm_commun": entree["cm_commun"],
                "groupes": entree["groupes"],
                "nb_etudiants": len(etudiants),
                "etudiants": etudiants,
            }
        )

    liste_cours.sort(key=lambda c: (c["filiere_code"], c["ecue_code"]))
    return {"semestre": entete_semestre, "cours": liste_cours}


@router.get("/mes-releves")
def mes_releves(
    session: int = 1,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Relevés de notes de l'étudiant connecté, par année d'inscription.

    Chaque année renvoie les semestres de son parcours (par exemple
    « Semestre 5 » et « Semestre 6 ») ainsi que le récapitulatif de passage
    qui reprend les moyennes des deux semestres.
    """
    if not _est_etudiant(utilisateur) or not utilisateur.etudiant_id:
        raise HTTPException(403, "Espace réservé aux étudiants.")
    inscriptions = (
        db.query(Inscription)
        .options(
            joinedload(Inscription.etudiant),
            joinedload(Inscription.niveau).joinedload(Niveau.filiere),
            joinedload(Inscription.groupe),
        )
        .filter(Inscription.etudiant_id == utilisateur.etudiant_id)
        .order_by(Inscription.annee.desc(), Inscription.id)
        .all()
    )
    releves = []
    for inscription in inscriptions:
        # Relevé individuel : on ne recalcule que cette inscription. Calculer
        # toute la classe pour chaque année rendait l'écran « Mes relevés »
        # très lent (plus d'une minute sur la base distante).
        resultats = resultats_passage(
            db,
            annee=inscription.annee,
            session=session,
            niveau_id=inscription.niveau_id,
            inscription_id=inscription.id,
        )
        passage = next(
            (
                resultat
                for resultat in resultats
                if resultat["inscription_id"] == inscription.id
            ),
            None,
        )
        semestres = []
        if passage:
            for detail in passage.get("semestres", []):
                semestres.append(
                    {
                        "id": detail.get("semestre_id"),
                        "nom": detail.get("semestre") or "—",
                        "moyenne": detail.get("moyenne"),
                        "credits_obtenus": detail.get("credits_obtenus", 0),
                        "credits_total": detail.get("credits_total", 0),
                        "statut": detail.get("statut") or "—",
                        "mention": detail.get("mention"),
                    }
                )
        if not semestres:
            # Parcours non déterminable (UE non rattachées au niveau) :
            # on retombe sur les résultats déjà enregistrés pour l'année.
            lignes = (
                db.query(ResultatSemestre)
                .options(joinedload(ResultatSemestre.semestre))
                .join(Semestre, ResultatSemestre.semestre_id == Semestre.id)
                .filter(
                    ResultatSemestre.inscription_id == inscription.id,
                    Semestre.annee == inscription.annee,
                )
                .order_by(Semestre.date_debut, Semestre.id)
                .all()
            )
            vus: set[int] = set()
            for ligne in lignes:
                if ligne.semestre is None or ligne.semestre_id in vus:
                    continue
                vus.add(ligne.semestre_id)
                semestres.append(
                    {
                        "id": ligne.semestre_id,
                        "nom": ligne.semestre.nom,
                        "moyenne": ligne.moyenne,
                        "credits_obtenus": ligne.credits_obtenus,
                        "credits_total": ligne.credits_total,
                        "statut": ligne.decision or ligne.statut or "—",
                        "mention": ligne.mention or None,
                    }
                )
        moyenne_annee = passage.get("moyenne_annee") if passage else None
        credits_obtenus = passage.get("credits_obtenus", 0) if passage else 0
        credits_total = passage.get("credits_total", 0) if passage else 0
        decision = passage.get("decision") if passage else ""
        if (passage is None or moyenne_annee is None) and semestres:
            # Sécurité : le récapitulatif est recalculé à partir des lignes
            # affichées si le calcul de passage n'a rien pu produire.
            moyennes = [
                ligne["moyenne"]
                for ligne in semestres
                if ligne.get("moyenne") is not None
            ]
            if moyennes:
                moyenne_annee = round(sum(moyennes) / len(moyennes), 2)
            credits_obtenus = sum(ligne.get("credits_obtenus", 0) for ligne in semestres)
            credits_total = sum(ligne.get("credits_total", 0) for ligne in semestres)
            if not decision:
                valides = len(semestres) >= 2 and all(
                    ligne.get("statut") == "Validé" for ligne in semestres
                )
                decision = (
                    "Admis en classe supérieure" if valides else "Année incomplète"
                )
        releves.append(
            {
                "inscription_id": inscription.id,
                "annee": inscription.annee,
                "niveau_id": inscription.niveau_id,
                "niveau_nom": inscription.niveau_nom,
                "filiere_nom": inscription.filiere_nom,
                "groupe_nom": inscription.groupe_nom,
                "matricule": inscription.matricule,
                "semestres": semestres,
                "moyenne_annee": moyenne_annee,
                "credits_obtenus": credits_obtenus,
                "credits_total": credits_total,
                "decision": decision,
            }
        )
    return releves


# =============================================================== 3. Évaluations
@router.get("/evaluations", response_model=list[EvaluationOut])
def lister_evaluations(
    semestre_id: Optional[int] = None,
    ecue_id: Optional[int] = None,
    session: Optional[int] = None,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    requete = db.query(Evaluation).options(
        joinedload(Evaluation.ecue).joinedload(ECUE.ue),
        selectinload(Evaluation.notes),
    )
    if _est_etudiant(utilisateur):
        return []
    if _est_enseignant(utilisateur):
        ids = _ecue_ids_enseignant(db, utilisateur)
        if not ids:
            return []
        requete = requete.filter(Evaluation.ecue_id.in_(ids))
    if semestre_id:
        requete = requete.filter(Evaluation.semestre_id == semestre_id)
    if ecue_id:
        requete = requete.filter(Evaluation.ecue_id == ecue_id)
    if session:
        requete = requete.filter(Evaluation.session == session)
    return requete.order_by(Evaluation.session, Evaluation.ecue_id, Evaluation.nom).all()


def _semestre_ecue(db: Session, ecue_id: int) -> int:
    ecue = db.get(ECUE, ecue_id)
    if not ecue or not ecue.ue:
        raise HTTPException(404, "ECUE introuvable")
    return ecue.ue.semestre_id


@router.post("/evaluations", response_model=EvaluationOut, status_code=201)
def creer_evaluation(
    payload: EvaluationCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    if payload.type_evaluation not in TYPES_EVALUATION:
        raise HTTPException(400, "Type d’évaluation invalide.")
    if payload.note_max <= 0:
        raise HTTPException(400, "Le barème doit être supérieur à zéro.")
    donnees = payload.model_dump()
    donnees["semestre_id"] = _semestre_ecue(db, donnees["ecue_id"])
    element = Evaluation(**donnees)
    db.add(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.put("/evaluations/{evaluation_id}", response_model=EvaluationOut)
def modifier_evaluation(
    evaluation_id: int,
    payload: EvaluationUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Evaluation, evaluation_id)
    if not element:
        raise HTTPException(404, "Évaluation introuvable")
    donnees = payload.model_dump(exclude_unset=True)
    if "type_evaluation" in donnees and donnees["type_evaluation"] not in TYPES_EVALUATION:
        raise HTTPException(400, "Type d’évaluation invalide.")
    if "note_max" in donnees and (donnees["note_max"] or 0) <= 0:
        raise HTTPException(400, "Le barème doit être supérieur à zéro.")
    if "ecue_id" in donnees:
        element.semestre_id = _semestre_ecue(db, donnees["ecue_id"])
    for cle, valeur in donnees.items():
        setattr(element, cle, valeur)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.delete("/evaluations/{evaluation_id}")
def supprimer_evaluation(
    evaluation_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Evaluation, evaluation_id)
    if not element:
        raise HTTPException(404, "Évaluation introuvable")
    db.delete(element)
    db.commit()
    return {"ok": True, "message": "Évaluation supprimée"}


# Modèles d'évaluations créés automatiquement pour chaque ECUE d'un niveau.
MODELES_EVALUATIONS = (
    ("Devoir 1", "Devoir", 1, 1),
    ("Examen final", "Examen", 2, 1),
    ("Session 2", "Examen", 1, 2),
)


@router.post("/evaluations/generer")
def generer_evaluations(
    payload: GenerationEvaluations,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Crée les évaluations types pour toutes les UE/ECUE d'un niveau et semestre.

    Session 1 : « Devoir 1 » (Devoir) et « Examen final » (Examen).
    Session 2 : « Session 2 » (Examen).
    Les évaluations déjà présentes (même nom et même session) sont conservées.
    """
    semestre = db.get(Semestre, payload.semestre_id)
    if not semestre:
        raise HTTPException(404, "Semestre introuvable")
    niveau = db.get(Niveau, payload.niveau_id)
    if not niveau:
        raise HTTPException(404, "Niveau introuvable")

    ecues = [
        ecue
        for ue in db.query(UE).filter(UE.semestre_id == semestre.id).all()
        if niveau.id in ue.niveau_ids
        for ecue in ue.ecues
    ]

    crees = 0
    ignores = 0
    for ecue in ecues:
        existantes = {
            ((evaluation.nom or "").strip().lower(), evaluation.session)
            for evaluation in db.query(Evaluation)
            .filter(Evaluation.ecue_id == ecue.id)
            .all()
        }
        for nom, type_evaluation, coefficient, session in MODELES_EVALUATIONS:
            cle = (nom.strip().lower(), session)
            if cle in existantes:
                ignores += 1
                continue
            db.add(
                Evaluation(
                    ecue_id=ecue.id,
                    semestre_id=semestre.id,
                    nom=nom,
                    type_evaluation=type_evaluation,
                    coefficient=coefficient,
                    note_max=20,
                    session=session,
                )
            )
            existantes.add(cle)
            crees += 1

    db.commit()
    return {
        "ok": True,
        "semestre_id": semestre.id,
        "niveau_id": niveau.id,
        "ecues": len(ecues),
        "crees": crees,
        "ignores": ignores,
        "message": (
            f"{crees} évaluation(s) créée(s) pour {len(ecues)} ECUE "
            f"({niveau.nom} · {semestre.nom} · {semestre.annee})."
        ),
    }


# =============================================================== 4. Saisie des notes
def _inscriptions_niveau(db: Session, niveau_id: int) -> list[Inscription]:
    return _inscriptions_niveaux(db, [niveau_id])


def _inscriptions_niveaux(db: Session, niveau_ids: list[int]) -> list[Inscription]:
    if not niveau_ids:
        return []
    return (
        db.query(Inscription)
        .filter(Inscription.niveau_id.in_(niveau_ids))
        .order_by(Inscription.etudiant_id)
        .all()
    )


def _inscriptions_niveau_annee(
    db: Session, niveau_id: int, annee: str
) -> list[Inscription]:
    """Étudiants du niveau pour l'année universitaire du semestre sélectionné."""
    return _inscriptions_niveaux_annee(db, [niveau_id], annee)


def _inscriptions_niveaux_annee(
    db: Session, niveau_ids: list[int], annee: str
) -> list[Inscription]:
    if not niveau_ids:
        return []
    return (
        db.query(Inscription)
        .filter(Inscription.niveau_id.in_(niveau_ids), Inscription.annee == annee)
        .order_by(Inscription.etudiant_id)
        .all()
    )


def _inscriptions_ecue(db: Session, ecue: ECUE, session: int) -> list[Inscription]:
    """Inscriptions autorisées pour la saisie des notes d'un ECUE.

    En session 2, seuls les étudiants ayant échoué à l'ECUE en session 1 et dont
    l'UE n'est pas validée peuvent saisir une note de rattrapage.
    """
    if not ecue or not ecue.ue:
        return []
    ue = ecue.ue
    semestre = ue.semestre
    inscriptions = [
        inscription
        for inscription in _inscriptions_niveaux(db, ue.niveau_ids)
        if semestre is None
        or not inscription.annee
        or inscription.annee == semestre.annee
    ]
    if session != 2:
        return inscriptions

    eligibles = []
    for inscription in inscriptions:
        # L'étudiant doit avoir été évalué en session 1 (une absence compte).
        a_des_notes = (
            db.query(Note.id)
            .join(Evaluation, Note.evaluation_id == Evaluation.id)
            .filter(
                Note.inscription_id == inscription.id,
                Evaluation.ecue_id == ecue.id,
                Evaluation.session == 1,
            )
            .first()
        )
        if a_des_notes is None:
            continue
        calcul = moyenne_ecue(db, inscription.id, ecue.id, ue.semestre_id, 1)
        moyenne_session1 = calcul["moyenne"]
        if moyenne_session1 is not None and moyenne_session1 >= 10:
            continue
        resultat = resultat_inscription(db, inscription, ue.semestre_id, 1)
        detail_ue = next(
            (detail for detail in resultat["ues"] if detail["ue_id"] == ue.id), None
        )
        if detail_ue is None or detail_ue["statut"] == "Validée":
            continue
        eligibles.append(inscription)
    return eligibles


def _inscriptions_evaluation(db: Session, evaluation: Evaluation) -> list[Inscription]:
    if not evaluation or not evaluation.ecue:
        return []
    return _inscriptions_ecue(db, evaluation.ecue, evaluation.session)


def _recalculer_resultats_inscriptions(
    db: Session, inscriptions: list[Inscription], semestre_id: int
) -> int:
    """Recalcule les résultats non verrouillés après une saisie de points jury."""
    if not inscriptions:
        return 0
    # Un préchargement commun évite des milliers de requêtes (une par note et
    # par étudiant) : sur une base distante, le calcul dépassait le délai
    # d'attente de l'interface et « Points jury » ne s'affichait jamais.
    donnees = precharger_donnees(
        db, [inscription.id for inscription in inscriptions], [semestre_id]
    )
    sessions_par_inscription: dict[int, set[int]] = {}
    for (inscription_id, semestre, session) in donnees.resultats:
        if semestre == semestre_id:
            sessions_par_inscription.setdefault(inscription_id, set()).add(session)
    recalculs = 0
    for inscription in inscriptions:
        sessions = sessions_par_inscription.get(inscription.id) or {1}
        for session in sorted(sessions):
            _, modifie = calculer_et_enregistrer(
                db, inscription, semestre_id, session, donnees
            )
            if modifie:
                recalculs += 1
    return recalculs


def _moyennes_ue_par_inscription(
    db: Session, ue: UE, inscriptions: list[Inscription]
) -> dict[int, Optional[float]]:
    """Moyenne pondérée actuelle de l'UE pour chaque étudiant (lecture seule)."""
    moyennes: dict[int, Optional[float]] = {}
    if not inscriptions:
        return moyennes
    donnees = precharger_donnees(
        db, [inscription.id for inscription in inscriptions], [ue.semestre_id]
    )
    for inscription in inscriptions:
        resultat = resultat_inscription(
            db, inscription, ue.semestre_id, 1, donnees
        )
        detail = next(
            (element for element in resultat["ues"] if element["ue_id"] == ue.id),
            None,
        )
        moyennes[inscription.id] = detail["moyenne"] if detail else None
    return moyennes


def _moyennes_ecue_par_inscription(
    db: Session, ecue: ECUE, inscriptions: list[Inscription]
) -> dict[int, Optional[float]]:
    """Moyenne pondérée actuelle de l'ECUE pour chaque étudiant (lecture seule)."""
    moyennes: dict[int, Optional[float]] = {}
    if not inscriptions:
        return moyennes
    donnees = precharger_donnees(
        db,
        [inscription.id for inscription in inscriptions],
        [ecue.ue.semestre_id],
    )
    for inscription in inscriptions:
        resultat = resultat_inscription(
            db, inscription, ecue.ue.semestre_id, 1, donnees
        )
        detail_ue = next(
            (
                element
                for element in resultat["ues"]
                if element["ue_id"] == ecue.ue_id
            ),
            None,
        )
        detail_ecue = (
            next(
                (
                    element
                    for element in detail_ue["ecues"]
                    if element["ecue_id"] == ecue.id
                ),
                None,
            )
            if detail_ue
            else None
        )
        moyennes[inscription.id] = (
            detail_ecue["moyenne"] if detail_ecue else None
        )
    return moyennes


def _points_jury_ue_lignes(
    db: Session, ue: UE, annee: str
) -> list[dict]:
    points = {
        ligne.inscription_id: float(ligne.points or 0)
        for ligne in db.query(PointJuryUE)
        .filter(PointJuryUE.ue_id == ue.id)
        .all()
    }
    inscriptions = _inscriptions_niveaux_annee(db, ue.niveau_ids, annee)
    moyennes = _moyennes_ue_par_inscription(db, ue, inscriptions)
    return [
        {
            "inscription_id": inscription.id,
            "matricule": inscription.matricule,
            "etudiant_nom": inscription.etudiant_nom,
            "groupe_nom": inscription.groupe_nom,
            "moyenne": moyennes.get(inscription.id),
            "points": round(points.get(inscription.id, 0.0), 2),
        }
        for inscription in inscriptions
    ]


def _points_jury_ecue_lignes(
    db: Session, ecue: ECUE, annee: str
) -> list[dict]:
    points = {
        ligne.inscription_id: float(ligne.points or 0)
        for ligne in db.query(PointJuryECUE)
        .filter(PointJuryECUE.ecue_id == ecue.id)
        .all()
    }
    inscriptions = _inscriptions_niveaux_annee(
        db, ecue.ue.niveau_ids, annee
    )
    moyennes = _moyennes_ecue_par_inscription(db, ecue, inscriptions)
    return [
        {
            "inscription_id": inscription.id,
            "matricule": inscription.matricule,
            "etudiant_nom": inscription.etudiant_nom,
            "groupe_nom": inscription.groupe_nom,
            "moyenne": moyennes.get(inscription.id),
            "points": round(points.get(inscription.id, 0.0), 2),
        }
        for inscription in inscriptions
    ]


@router.get("/saisie")
def grille_saisie(
    evaluation_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La saisie des notes n’est pas accessible à cet espace.")
    evaluation = db.get(Evaluation, evaluation_id)
    if not evaluation or not evaluation.ecue or not evaluation.ecue.ue:
        raise HTTPException(404, "Évaluation introuvable")
    _verifier_evaluation(db, utilisateur, evaluation)
    notes = {
        note.inscription_id: note
        for note in db.query(Note).filter(Note.evaluation_id == evaluation_id).all()
    }
    lignes = []
    for inscription in _inscriptions_evaluation(db, evaluation):
        note = notes.get(inscription.id)
        lignes.append(
            {
                "inscription_id": inscription.id,
                "matricule": inscription.matricule,
                "etudiant_nom": inscription.etudiant_nom,
                "niveau_nom": inscription.niveau_nom,
                "groupe_nom": inscription.groupe_nom,
                "note_id": note.id if note else None,
                "valeur": note.valeur if note else None,
                "absent": note.absent if note else False,
                "commentaire": note.commentaire if note else "",
                "sur_20": note.sur_20 if note else None,
            }
        )
    return {
        "evaluation": {
            "id": evaluation.id,
            "nom": evaluation.nom,
            "type_evaluation": evaluation.type_evaluation,
            "coefficient": evaluation.coefficient,
            "note_max": evaluation.note_max,
            "session": evaluation.session,
            "date_evaluation": evaluation.date_evaluation.isoformat()
            if evaluation.date_evaluation
            else None,
            "ecue_code": evaluation.ecue_code,
            "ecue_nom": evaluation.ecue_nom,
            "ue_code": evaluation.ue_code,
        },
        "lignes": lignes,
    }


def _enregistrer_notes(db: Session, evaluation: Evaluation, notes: list) -> int:
    enregistrees = 0
    for item in notes:
        note = (
            db.query(Note)
            .filter(
                Note.inscription_id == item.inscription_id,
                Note.evaluation_id == evaluation.id,
            )
            .first()
        )
        if item.valeur is None and not item.absent and not (item.commentaire or "").strip():
            if note:
                db.delete(note)
                enregistrees += 1
            continue
        if item.valeur is not None and (item.valeur < 0 or item.valeur > evaluation.note_max):
            raise HTTPException(
                400,
                f"La note de {item.valeur} dépasse le barème de {evaluation.note_max}.",
            )
        if note is None:
            note = Note(inscription_id=item.inscription_id, evaluation_id=evaluation.id)
            db.add(note)
        note.valeur = item.valeur
        note.absent = item.absent
        note.commentaire = item.commentaire or ""
        note.maj_le = datetime.utcnow()
        enregistrees += 1
    return enregistrees


@router.post("/saisie")
def enregistrer_saisie(
    payload: NoteMasse,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La saisie des notes n’est pas accessible à cet espace.")
    evaluation = db.get(Evaluation, payload.evaluation_id)
    if not evaluation:
        raise HTTPException(404, "Évaluation introuvable")
    _verifier_evaluation(db, utilisateur, evaluation)
    autorisees = {
        inscription.id for inscription in _inscriptions_evaluation(db, evaluation)
    }
    if any(item.inscription_id not in autorisees for item in payload.notes):
        raise HTTPException(
            400,
            "Un étudiant sélectionné n’est pas éligible à cette évaluation.",
        )
    enregistrees = _enregistrer_notes(db, evaluation, payload.notes)
    db.commit()
    return {
        "ok": True,
        "enregistrees": enregistrees,
        "message": f"{enregistrees} note(s) enregistrée(s).",
    }


@router.get("/saisie/modele")
def modele_saisie(
    evaluation_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La saisie des notes n’est pas accessible à cet espace.")
    evaluation = db.get(Evaluation, evaluation_id)
    if not evaluation or not evaluation.ecue or not evaluation.ecue.ue:
        raise HTTPException(404, "Évaluation introuvable")
    _verifier_evaluation(db, utilisateur, evaluation)
    classeur = Workbook()
    feuille = classeur.active
    feuille.title = "Notes"
    entetes = ["Matricule", "Nom", "Note", "Absent", "Commentaire"]
    feuille.append(entetes)
    for cellule in feuille[1]:
        cellule.font = Font(bold=True, color="FFFFFF")
        cellule.fill = PatternFill("solid", fgColor="1E3A8A")
    for inscription in _inscriptions_evaluation(db, evaluation):
        note = (
            db.query(Note)
            .filter(
                Note.inscription_id == inscription.id,
                Note.evaluation_id == evaluation.id,
            )
            .first()
        )
        feuille.append(
            [
                inscription.matricule,
                inscription.etudiant_nom,
                note.valeur if note else None,
                "Oui" if note and note.absent else "Non",
                note.commentaire if note else "",
            ]
        )
    for index, largeur in enumerate([18, 32, 10, 10, 30], start=1):
        feuille.column_dimensions[feuille.cell(row=1, column=index).column_letter].width = largeur
    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    return StreamingResponse(
        flux,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f'attachment; filename="notes_evaluation_{evaluation_id}.xlsx"'
        },
    )


def _titre_feuille(nom: str, code: str, utilises: set[str]) -> str:
    """Construit un nom de feuille Excel valide (31 caractères maximum)."""
    base = "".join(" " if caractere in "[]:*?/\\" else caractere for caractere in (nom or code))
    base = " ".join(base.split())[:31].strip() or code[:31]
    titre = base
    compteur = 2
    while titre in utilises:
        suffixe = f" ({compteur})"
        titre = f"{base[: 31 - len(suffixe)]}{suffixe}"
        compteur += 1
    utilises.add(titre)
    return titre


def _evaluation_devoir(evaluations: list[Evaluation]) -> Evaluation | None:
    candidats = [
        evaluation
        for evaluation in evaluations
        if (evaluation.type_evaluation or "").strip().lower() == "devoir"
    ]
    for evaluation in candidats:
        nom = _normaliser(evaluation.nom)
        if "devoir_1" in nom or nom.endswith("_1"):
            return evaluation
    return candidats[0] if candidats else None


def _evaluation_cc(evaluations: list[Evaluation]) -> Evaluation | None:
    for evaluation in evaluations:
        nom = _normaliser(evaluation.nom)
        if (evaluation.type_evaluation or "").strip().lower() == "cc":
            return evaluation
        if "cc" in nom or "controle_continu" in nom:
            return evaluation
    return None


def _evaluation_type(evaluations: list[Evaluation], type_cible: str) -> Evaluation | None:
    for evaluation in evaluations:
        if (evaluation.type_evaluation or "").strip().lower() == type_cible:
            return evaluation
    return None


def _evaluation_examen(evaluations: list[Evaluation]) -> Evaluation | None:
    candidats = [
        evaluation
        for evaluation in evaluations
        if (evaluation.type_evaluation or "").strip().lower() == "examen"
    ]
    for evaluation in candidats:
        if "final" in _normaliser(evaluation.nom):
            return evaluation
    return candidats[0] if candidats else None


def _valeur_modele(note: Note | None):
    if note is None:
        return None
    if note.absent:
        return "ABS"
    if note.valeur is None:
        return None
    valeur = float(note.valeur)
    return int(valeur) if valeur.is_integer() else round(valeur, 2)


@router.get("/documents/modele-saisie")
def modele_saisie_classeur(
    semestre_id: int,
    niveau_id: Optional[int] = None,
    session: int = 1,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Classeur Excel de saisie : une feuille par ECUE, prête à être remplie.

    Les administrateurs et gestionnaires choisissent un niveau ; un enseignant
    ne reçoit que les ECUE qui lui sont affectés.
    """
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise HTTPException(404, "Semestre introuvable")

    role = (utilisateur.role or "").strip().lower()
    if role not in ("admin", "gestionnaire", "enseignant"):
        raise HTTPException(
            403, "Téléchargement réservé aux administrateurs, gestionnaires et enseignants."
        )

    requete = db.query(ECUE).join(UE).filter(UE.semestre_id == semestre_id)
    if niveau_id is not None:
        ids_ues_niveau = {
            ue.id
            for ue in db.query(UE).filter(UE.semestre_id == semestre_id).all()
            if niveau_id in ue.niveau_ids
        }
        requete = requete.filter(UE.id.in_(ids_ues_niveau))
    if role == "enseignant":
        if not utilisateur.enseignant_id:
            raise HTTPException(403, "Aucun profil enseignant n’est associé à ce compte.")
        ecues_enseignant = [
            ligne[0]
            for ligne in db.query(Affectation.ecue_id)
            .filter(Affectation.enseignant_id == utilisateur.enseignant_id)
            .distinct()
            .all()
        ]
        if not ecues_enseignant:
            raise HTTPException(404, "Aucune ECUE n’est affectée à ce compte.")
        requete = requete.filter(ECUE.id.in_(ecues_enseignant))
    ecues = requete.order_by(ECUE.code).all()
    if not ecues:
        raise HTTPException(404, "Aucune ECUE ne correspond à ces critères.")

    classeur = Workbook()
    classeur.remove(classeur.active)
    utilises: set[str] = set()
    entetes = [
        "Semestre",
        "Annee",
        "Filiere",
        "Code ECUE",
        "Matricule étudiant",
        "Nom et prénom étudiant",
        "Note devoir 1",
        "Note CC",
        "Note TP",
        "Note examen final",
    ]

    for ecue in ecues:
        feuille = classeur.create_sheet(_titre_feuille(ecue.nom, ecue.code, utilises))
        feuille.append(entetes)
        for cellule in feuille[1]:
            cellule.font = Font(bold=True, color="FFFFFF")
            cellule.fill = PatternFill("solid", fgColor="1E3A8A")
            cellule.alignment = cellule.alignment.copy(horizontal="center", vertical="center")
        feuille.freeze_panes = "A2"

        ecritures = db.query(Evaluation).filter(
            Evaluation.ecue_id == ecue.id,
            Evaluation.session == session,
        ).order_by(Evaluation.id).all()
        evaluations = [
            _evaluation_devoir(ecritures),
            _evaluation_cc(ecritures),
            _evaluation_type(ecritures, "tp"),
            _evaluation_examen(ecritures),
        ]
        for index, evaluation in enumerate(evaluations, start=7):
            cellule = feuille.cell(row=1, column=index)
            if evaluation is None:
                cellule.fill = PatternFill("solid", fgColor="64748B")
                cellule.comment = Comment(
                    "Aucune évaluation de ce type pour cet ECUE : la colonne reste vide.",
                    "CIAR-Mali",
                )
            else:
                cellule.comment = Comment(
                    f"Évaluation liée : {evaluation.nom} (barème /{evaluation.note_max}).",
                    "CIAR-Mali",
                )

        inscriptions = sorted(
            _inscriptions_ecue(db, ecue, session),
            key=lambda inscription: (inscription.etudiant_nom or "").lower(),
        )
        identifiants = [inscription.id for inscription in inscriptions]
        notes = {}
        identifiants_evaluations = [
            evaluation.id for evaluation in evaluations if evaluation is not None
        ]
        if identifiants and identifiants_evaluations:
            notes = {
                (note.inscription_id, note.evaluation_id): note
                for note in db.query(Note)
                .filter(
                    Note.inscription_id.in_(identifiants),
                    Note.evaluation_id.in_(identifiants_evaluations),
                )
                .all()
            }
        for inscription in inscriptions:
            feuille.append(
                [
                    semestre.nom,
                    inscription.annee or semestre.annee,
                    inscription.filiere_code,
                    ecue.code,
                    inscription.matricule,
                    inscription.etudiant_nom,
                    *[
                        _valeur_modele(
                            notes.get((inscription.id, evaluation.id))
                            if evaluation is not None
                            else None
                        )
                        for evaluation in evaluations
                    ],
                ]
            )

        for index, largeur in enumerate(
            [14, 12, 14, 14, 20, 34, 14, 12, 12, 16], start=1
        ):
            feuille.column_dimensions[feuille.cell(row=1, column=index).column_letter].width = (
                largeur
            )

    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    suffixe = f"_niveau_{niveau_id}" if niveau_id else ""
    if role == "enseignant":
        suffixe += f"_enseignant_{utilisateur.enseignant_id}"
    return StreamingResponse(
        flux,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": (
                f'attachment; filename="modele_saisie_{semestre_id}{suffixe}_S{session}.xlsx"'
            )
        },
    )


@router.post("/saisie/importer")
async def importer_notes(
    evaluation_id: int,
    fichier: UploadFile = File(...),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La saisie des notes n’est pas accessible à cet espace.")
    evaluation = db.get(Evaluation, evaluation_id)
    if not evaluation:
        raise HTTPException(404, "Évaluation introuvable")
    _verifier_evaluation(db, utilisateur, evaluation)
    if not fichier.filename.lower().endswith((".xlsx", ".xlsm")):
        raise HTTPException(400, "Le fichier doit être au format .xlsx")
    try:
        classeur = load_workbook(BytesIO(await fichier.read()), data_only=True)
    except Exception:
        raise HTTPException(400, "Impossible de lire le classeur Excel")
    feuille = classeur.worksheets[0]
    entetes = {
        _normaliser(cellule.value): cellule.column - 1
        for cellule in feuille[1]
        if cellule.value
    }

    def valeur(ligne, *noms):
        for nom in noms:
            index = entetes.get(_normaliser(nom))
            if index is not None and index < len(ligne):
                return ligne[index]
        return None

    importees = 0
    erreurs = []
    inscriptions_autorisees = {
        inscription.id for inscription in _inscriptions_evaluation(db, evaluation)
    }
    for numero, ligne in enumerate(feuille.iter_rows(min_row=2, values_only=True), start=2):
        if all(v in (None, "") for v in ligne):
            continue
        matricule = _texte(valeur(ligne, "Matricule"))
        if not matricule:
            erreurs.append({"ligne": numero, "message": "Matricule manquant"})
            continue
        etudiant = db.query(Etudiant).filter(Etudiant.matricule == matricule).first()
        if not etudiant:
            erreurs.append({"ligne": numero, "message": f"Étudiant introuvable : {matricule}"})
            continue
        inscription = (
            db.query(Inscription)
            .filter(
                Inscription.etudiant_id == etudiant.id,
                Inscription.niveau_id.in_(evaluation.ecue.ue.niveau_ids),
            )
            .first()
        )
        if not inscription:
            erreurs.append(
                {"ligne": numero, "message": f"Aucune inscription de {matricule} à ce niveau"}
            )
            continue
        if inscription.id not in inscriptions_autorisees:
            erreurs.append(
                {
                    "ligne": numero,
                    "message": (
                        f"{matricule} n’est pas éligible à cette évaluation "
                        "(ECUE validé ou UE déjà validée)."
                    ),
                }
            )
            continue
        try:
            note_valeur = _nombre(valeur(ligne, "Note"))
            if note_valeur is not None and (note_valeur < 0 or note_valeur > evaluation.note_max):
                raise ValueError(f"note hors barème (0 à {evaluation.note_max})")
            absent = _normaliser(valeur(ligne, "Absent")) in {"oui", "o", "1", "true", "x"}
            commentaire = _texte(valeur(ligne, "Commentaire"))
            note = (
                db.query(Note)
                .filter(
                    Note.inscription_id == inscription.id,
                    Note.evaluation_id == evaluation.id,
                )
                .first()
            )
            if note_valeur is None and not absent and not commentaire:
                if note:
                    db.delete(note)
                    importees += 1
                continue
            if note is None:
                note = Note(inscription_id=inscription.id, evaluation_id=evaluation.id)
                db.add(note)
            note.valeur = note_valeur
            note.absent = absent
            note.commentaire = commentaire
            note.maj_le = datetime.utcnow()
            importees += 1
        except Exception as exc:
            erreurs.append({"ligne": numero, "message": str(exc)})
    db.commit()
    return {
        "importees": importees,
        "erreurs": erreurs,
        "message": f"{importees} note(s) importée(s), {len(erreurs)} erreur(s).",
    }


COLONNES_NOTES_ECUE = (
    (("Note devoir 1", "Note devoir"), "devoir"),
    (("Note CC",), "cc"),
    (("Note TP",), "tp"),
    (("Note examen final", "Note examen"), "examen"),
)


@router.post("/saisie/importer-ecues")
async def importer_notes_ecues(
    semestre_id: int,
    session: int = 1,
    fichier: UploadFile = File(...),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Importe les notes de toutes les ECUE d'un classeur, une feuille par ECUE."""
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La saisie des notes n’est pas accessible à cet espace.")
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise HTTPException(404, "Semestre introuvable")
    if not fichier.filename.lower().endswith((".xlsx", ".xlsm")):
        raise HTTPException(400, "Le fichier doit être au format .xlsx")
    try:
        classeur = load_workbook(BytesIO(await fichier.read()), data_only=True)
    except Exception:
        raise HTTPException(400, "Impossible de lire le classeur Excel")

    ecues = (
        db.query(ECUE)
        .filter(ECUE.semestre_id == semestre_id)
        .order_by(ECUE.code)
        .all()
    )
    if not ecues:
        raise HTTPException(404, "Aucune ECUE pour ce semestre.")
    par_code: dict[str, list[ECUE]] = {}
    par_nom: dict[str, list[ECUE]] = {}
    for ecue in ecues:
        par_code.setdefault(_normaliser(ecue.code), []).append(ecue)
        par_nom.setdefault(_normaliser(ecue.nom), []).append(ecue)

    def references_filiere(ecue: ECUE) -> set[str]:
        """Toutes les filières d'une UE, y compris les niveaux mutualisés."""
        if not ecue.ue:
            return set()
        references: set[str] = set()
        for niveau in [ecue.ue.niveau, *(ecue.ue.niveaux or [])]:
            filiere = niveau.filiere if niveau else None
            if filiere:
                references.add(_normaliser(filiere.code))
                references.add(_normaliser(filiere.nom))
        return references

    def trouver_ecue(code: str, nom_feuille: str, filiere_ligne: str):
        candidats = list(par_code.get(_normaliser(code), [])) if code else []
        if not candidats:
            # Repli sur le nom de la feuille si la colonne Code ECUE est vide.
            candidats = list(par_nom.get(_normaliser(nom_feuille), []))
        if not candidats:
            return None, f"ECUE introuvable pour ce semestre : {code or nom_feuille}"
        # Un code exact et unique dans le semestre suffit : il ne doit pas être
        # écarté parce que la feuille mentionne une filière mutualisée.
        if len(candidats) == 1:
            return candidats[0], None
        if filiere_ligne:
            reference = _normaliser(filiere_ligne)
            filtres = [
                ecue for ecue in candidats if reference in references_filiere(ecue)
            ]
            if len(filtres) == 1:
                return filtres[0], None
            if filtres:
                candidats = filtres
        return None, (
            f"Plusieurs ECUE correspondent à {code or nom_feuille} : "
            "précisez la filière dans la colonne « Filiere »."
        )

    autorisees = (
        _ecue_ids_enseignant(db, utilisateur)
        if _est_enseignant(utilisateur)
        else None
    )

    evaluations_par_ecue: dict[int, dict[str, Evaluation | None]] = {}
    for ecue in ecues:
        ecritures = (
            db.query(Evaluation)
            .filter(Evaluation.ecue_id == ecue.id, Evaluation.session == session)
            .order_by(Evaluation.id)
            .all()
        )
        evaluations_par_ecue[ecue.id] = {
            "devoir": _evaluation_devoir(ecritures),
            "cc": _evaluation_cc(ecritures),
            "tp": _evaluation_type(ecritures, "tp"),
            "examen": _evaluation_examen(ecritures),
        }

    importees = 0
    supprimees = 0
    erreurs: list[dict] = []
    feuilles_traitees = 0

    for feuille in classeur.worksheets:
        entetes = {
            _normaliser(cellule.value): cellule.column - 1
            for cellule in feuille[1]
            if cellule.value
        }
        if "matricule_etudiant" not in entetes and "matricule" not in entetes:
            erreurs.append(
                {
                    "feuille": feuille.title,
                    "ligne": 1,
                    "message": "Colonne « Matricule étudiant » absente.",
                }
            )
            continue
        colonnes_presentes = [
            (libelles, cle)
            for libelles, cle in COLONNES_NOTES_ECUE
            if any(_normaliser(libelle) in entetes for libelle in libelles)
        ]
        if not colonnes_presentes:
            erreurs.append(
                {
                    "feuille": feuille.title,
                    "ligne": 1,
                    "message": "Aucune colonne de note reconnue.",
                }
            )
            continue
        feuilles_traitees += 1

        def valeur(ligne, *noms):
            for nom in noms:
                index = entetes.get(_normaliser(nom))
                if index is not None and index < len(ligne):
                    return ligne[index]
            return None

        for numero, ligne in enumerate(
            feuille.iter_rows(min_row=2, values_only=True), start=2
        ):
            if all(valeur in (None, "") for valeur in ligne):
                continue
            code = _texte(valeur(ligne, "Code ECUE"))
            matricule = _texte(valeur(ligne, "Matricule étudiant", "Matricule"))
            semestre_ligne = _texte(valeur(ligne, "Semestre"))
            annee_ligne = _texte(valeur(ligne, "Annee", "Année"))
            filiere_ligne = _texte(valeur(ligne, "Filiere", "Filière"))
            if not matricule:
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": "Matricule manquant",
                    }
                )
                continue
            if semestre_ligne and _normaliser(semestre_ligne) != _normaliser(semestre.nom):
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": (
                            f"Semestre {semestre_ligne} incompatible avec "
                            f"{semestre.nom} ({semestre.annee})."
                        ),
                    }
                )
                continue
            if annee_ligne and annee_ligne != semestre.annee:
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": (
                            f"Année d’inscription {annee_ligne} incompatible avec "
                            f"le semestre {semestre.nom} ({semestre.annee})."
                        ),
                    }
                )
                continue

            ecue, message_ecue = trouver_ecue(code, feuille.title, filiere_ligne)
            if ecue is None:
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": message_ecue or "ECUE introuvable",
                    }
                )
                continue
            if autorisees is not None and ecue.id not in autorisees:
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": f"L’ECUE {ecue.code} ne relève pas de votre espace.",
                    }
                )
                continue

            etudiant = (
                db.query(Etudiant)
                .filter(Etudiant.matricule == matricule)
                .first()
            )
            if not etudiant:
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": f"Étudiant introuvable : {matricule}",
                    }
                )
                continue
            annee_inscription = annee_ligne or semestre.annee
            candidats = (
                db.query(Inscription)
                .filter(
                    Inscription.etudiant_id == etudiant.id,
                    Inscription.niveau_id.in_(ecue.ue.niveau_ids),
                )
                .all()
            )
            inscription = next(
                (
                    candidat
                    for candidat in candidats
                    if (candidat.annee or "") == annee_inscription
                ),
                None,
            )
            if not inscription:
                erreurs.append(
                    {
                        "feuille": feuille.title,
                        "ligne": numero,
                        "message": (
                            f"Aucune inscription de {matricule} à ce niveau "
                            f"pour l’année {annee_inscription}"
                        ),
                    }
                )
                continue

            evaluations = evaluations_par_ecue[ecue.id]
            for libelles, cle in colonnes_presentes:
                evaluation = evaluations[cle]
                brut = valeur(ligne, *libelles)
                if evaluation is None:
                    if brut not in (None, ""):
                        erreurs.append(
                            {
                                "feuille": feuille.title,
                                "ligne": numero,
                                "message": (
                                    f"Aucune évaluation « {libelles[0]} » pour "
                                    f"{ecue.code} en session {session}."
                                ),
                            }
                        )
                    continue
                note = (
                    db.query(Note)
                    .filter(
                        Note.inscription_id == inscription.id,
                        Note.evaluation_id == evaluation.id,
                    )
                    .first()
                )
                try:
                    texte = _texte(brut)
                    if not texte:
                        if note:
                            db.delete(note)
                            supprimees += 1
                        continue
                    absent = texte.upper() in {
                        "ABS",
                        "ABSENT",
                        "A",
                        "X",
                        "OUI",
                        "O",
                        "1",
                        "TRUE",
                    }
                    note_valeur = None
                    if not absent:
                        note_valeur = _nombre(brut)
                        if note_valeur is None:
                            continue
                        if note_valeur < 0 or note_valeur > evaluation.note_max:
                            raise ValueError(
                                f"note hors barème (0 à {evaluation.note_max})"
                            )
                    if note is None:
                        note = Note(
                            inscription_id=inscription.id,
                            evaluation_id=evaluation.id,
                        )
                        db.add(note)
                    note.valeur = note_valeur
                    note.absent = absent
                    note.maj_le = datetime.utcnow()
                    importees += 1
                except Exception as exc:
                    erreurs.append(
                        {
                            "feuille": feuille.title,
                            "ligne": numero,
                            "message": f"{libelles[0]} : {exc}",
                        }
                    )

    db.commit()
    return {
        "importees": importees,
        "supprimees": supprimees,
        "feuilles": feuilles_traitees,
        "erreurs": erreurs,
        "message": (
            f"{importees} note(s) importée(s), {supprimees} supprimée(s), "
            f"{len(erreurs)} erreur(s) sur {feuilles_traitees} feuille(s)."
        ),
    }


# ===================================================== 4bis. Points jury UE / ECUE
def _infos_semestre(semestre: Semestre) -> dict:
    return {"id": semestre.id, "nom": semestre.nom, "annee": semestre.annee}


@router.get("/points-jury/ue")
def lignes_points_jury_ue(
    ue_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    ue = db.get(UE, ue_id)
    if not ue or not ue.semestre:
        raise HTTPException(404, "UE introuvable")
    return {
        "ue": {
            "id": ue.id,
            "code": ue.code,
            "nom": ue.nom,
            "credits": ue.credits,
        },
        "semestre": _infos_semestre(ue.semestre),
        "lignes": _points_jury_ue_lignes(db, ue, ue.semestre.annee),
    }


@router.post("/points-jury/ue")
def enregistrer_points_jury_ue(
    payload: PointsJuryUEMasse,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    ue = db.get(UE, payload.ue_id)
    if not ue or not ue.semestre:
        raise HTTPException(404, "UE introuvable")
    inscriptions = _inscriptions_niveaux_annee(
        db, ue.niveau_ids, ue.semestre.annee
    )
    autorises = {inscription.id for inscription in inscriptions}
    enregistres = 0
    for ligne in payload.points:
        if ligne.inscription_id not in autorises:
            continue
        points = max(0.0, round(float(ligne.points or 0), 2))
        existant = (
            db.query(PointJuryUE)
            .filter(
                PointJuryUE.inscription_id == ligne.inscription_id,
                PointJuryUE.ue_id == ue.id,
            )
            .first()
        )
        if points <= 0:
            if existant:
                db.delete(existant)
            continue
        if existant is None:
            db.add(
                PointJuryUE(
                    inscription_id=ligne.inscription_id,
                    ue_id=ue.id,
                    points=points,
                )
            )
        else:
            existant.points = points
            existant.maj_le = datetime.utcnow()
        enregistres += 1
    db.flush()
    recalculs = _recalculer_resultats_inscriptions(
        db, inscriptions, ue.semestre_id
    )
    db.commit()
    return {
        "ok": True,
        "message": (
            f"Points jury enregistrés pour {enregistres} étudiant(s) "
            f"({recalculs} résultat(s) recalculé(s))."
        ),
        "enregistres": enregistres,
        "resultats_recalculés": recalculs,
    }


@router.get("/points-jury/ecue")
def lignes_points_jury_ecue(
    ecue_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    ecue = db.get(ECUE, ecue_id)
    if not ecue or not ecue.ue or not ecue.ue.semestre:
        raise HTTPException(404, "ECUE introuvable")
    return {
        "ecue": {
            "id": ecue.id,
            "code": ecue.code,
            "nom": ecue.nom,
            "credits": ecue.credits,
        },
        "ue": {
            "id": ecue.ue.id,
            "code": ecue.ue.code,
            "nom": ecue.ue.nom,
        },
        "semestre": _infos_semestre(ecue.ue.semestre),
        "lignes": _points_jury_ecue_lignes(
            db, ecue, ecue.ue.semestre.annee
        ),
    }


@router.post("/points-jury/ecue")
def enregistrer_points_jury_ecue(
    payload: PointsJuryECUEMasse,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    ecue = db.get(ECUE, payload.ecue_id)
    if not ecue or not ecue.ue or not ecue.ue.semestre:
        raise HTTPException(404, "ECUE introuvable")
    inscriptions = _inscriptions_niveaux_annee(
        db, ecue.ue.niveau_ids, ecue.ue.semestre.annee
    )
    autorises = {inscription.id for inscription in inscriptions}
    enregistres = 0
    for ligne in payload.points:
        if ligne.inscription_id not in autorises:
            continue
        points = max(0.0, round(float(ligne.points or 0), 2))
        existant = (
            db.query(PointJuryECUE)
            .filter(
                PointJuryECUE.inscription_id == ligne.inscription_id,
                PointJuryECUE.ecue_id == ecue.id,
            )
            .first()
        )
        if points <= 0:
            if existant:
                db.delete(existant)
            continue
        if existant is None:
            db.add(
                PointJuryECUE(
                    inscription_id=ligne.inscription_id,
                    ecue_id=ecue.id,
                    points=points,
                )
            )
        else:
            existant.points = points
            existant.maj_le = datetime.utcnow()
        enregistres += 1
    db.flush()
    recalculs = _recalculer_resultats_inscriptions(
        db, inscriptions, ecue.ue.semestre_id
    )
    db.commit()
    return {
        "ok": True,
        "message": (
            f"Points jury enregistrés pour {enregistres} étudiant(s) "
            f"({recalculs} résultat(s) recalculé(s))."
        ),
        "enregistres": enregistres,
        "resultats_recalculés": recalculs,
    }


# =============================================================== 5. Résultats
@router.get("/resultats", response_model=list[ResultatOut])
def lister_resultats(
    semestre_id: int,
    session: int = 1,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if not _est_encadrement(utilisateur):
        raise HTTPException(403, "Le calcul des résultats est réservé à l’administration.")
    calculer_semestre(db, semestre_id, session, niveau_id)
    requete = db.query(ResultatSemestre).filter(
        ResultatSemestre.semestre_id == semestre_id,
        ResultatSemestre.session == session,
    )
    if niveau_id:
        requete = requete.filter(
            ResultatSemestre.inscription.has(Inscription.niveau_id == niveau_id)
        )
    return requete.order_by(ResultatSemestre.moyenne.desc()).all()


@router.post("/resultats/calculer")
def calculer_resultats(
    semestre_id: int,
    session: int = 1,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    resultats = calculer_semestre(db, semestre_id, session, niveau_id)
    return {
        "ok": True,
        "resultats": len(resultats),
        "message": f"{len(resultats)} résultat(s) calculé(s) et enregistré(s).",
    }


@router.get("/resultats/{inscription_id}")
def detail_resultat(
    inscription_id: int,
    semestre_id: int,
    session: int = 1,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise HTTPException(404, "Inscription introuvable")
    if not _est_encadrement(utilisateur) and not (
        _est_etudiant(utilisateur)
        and utilisateur.etudiant_id == inscription.etudiant_id
    ):
        raise HTTPException(403, "Accès non autorisé à ce résultat.")
    donnees = resultat_inscription(db, inscription, semestre_id, session)
    resultat = (
        db.query(ResultatSemestre)
        .filter(
            ResultatSemestre.inscription_id == inscription_id,
            ResultatSemestre.semestre_id == semestre_id,
            ResultatSemestre.session == session,
        )
        .first()
    )
    return {
        "inscription_id": inscription_id,
        "etudiant": inscription.etudiant_nom,
        "matricule": inscription.matricule,
        "niveau": inscription.niveau_nom,
        "resultat": {
            **donnees,
            "id": resultat.id if resultat else None,
            "decision": resultat.decision if resultat else "",
            "verrouille": resultat.verrouille if resultat else False,
        },
    }


@router.post("/resultats/{resultat_id}/deverrouiller")
def deverrouiller_resultat(
    resultat_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    resultat = db.get(ResultatSemestre, resultat_id)
    if not resultat:
        raise HTTPException(404, "Résultat introuvable")
    resultat.verrouille = False
    resultat.decision = ""
    db.commit()
    return {"ok": True, "message": "Résultat déverrouillé, il peut être recalculé."}


# ==================================================== 5 bis. Passages en classe
@router.get("/passages/options")
def options_passages(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    annees = {
        annee
        for (annee,) in db.query(Inscription.annee).distinct().all()
        if annee
    }
    annees.update(
        annee
        for (annee,) in db.query(Semestre.annee).distinct().all()
        if annee
    )
    return {"annees": sorted(annees, reverse=True)}


@router.get("/passages")
def lister_passages(
    annee: Optional[str] = None,
    session: int = 1,
    mode: str = "10",
    seuil_dettes: float = 80,
    moyenne_passage: float = 10,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    if mode not in ("10", "12", "dettes"):
        raise HTTPException(400, "Mode de passage invalide.")
    if not annee:
        derniere = (
            db.query(Semestre.annee).order_by(Semestre.annee.desc()).first()
        )
        annee = derniere[0] if derniere else ""
    seuil = max(0.0, min(100.0, float(seuil_dettes)))
    seuil_moyenne = 12.0 if float(moyenne_passage or 10) >= 12 else 10.0
    resultats = resultats_passage(
        db,
        annee=annee,
        session=session,
        mode=mode,
        seuil_dettes=seuil,
        moyenne_passage=seuil_moyenne,
        niveau_id=niveau_id,
    )
    return {
        "annee": annee,
        "session": session,
        "mode": mode,
        "seuil_dettes": seuil,
        "moyenne_passage": seuil_moyenne,
        "total": len(resultats),
        "admis": sum(1 for resultat in resultats if resultat["admis"]),
        "resultats": resultats,
    }


# =============================================================== 6. Délibérations
@router.get("/deliberations")
def lister_deliberations(
    semestre_id: Optional[int] = None,
    session: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    requete = db.query(ResultatSemestre).filter(ResultatSemestre.decision != "")
    if semestre_id:
        requete = requete.filter(ResultatSemestre.semestre_id == semestre_id)
    if session:
        requete = requete.filter(ResultatSemestre.session == session)
    return [
        {
            "id": resultat.id,
            "inscription_id": resultat.inscription_id,
            "etudiant_nom": resultat.etudiant_nom,
            "matricule": resultat.matricule,
            "niveau_nom": resultat.niveau_nom,
            "moyenne": resultat.moyenne,
            "points_jury": resultat.points_jury,
            "statut": resultat.statut,
            "decision": resultat.decision,
            "verrouille": resultat.verrouille,
        }
        for resultat in requete.order_by(ResultatSemestre.moyenne.desc()).all()
    ]


@router.post("/deliberations", response_model=DeliberationOut, status_code=201)
def deliberer(
    payload: DeliberationCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    from ..models import Deliberation

    if payload.decision not in DECISIONS:
        raise HTTPException(400, "Décision invalide (ADMIS, AJOURNE ou RATTRAPAGE).")
    resultat = db.get(ResultatSemestre, payload.resultat_id)
    if not resultat:
        raise HTTPException(404, "Résultat introuvable")
    if payload.points_jury is not None:
        resultat.points_jury = max(0.0, float(payload.points_jury))
        db.flush()
        # Les points jury de la moyenne finale complètent le résultat avant
        # de figer la décision du jury.
        donnees = resultat_inscription(
            db, resultat.inscription, resultat.semestre_id, resultat.session
        )
        resultat.moyenne = donnees["moyenne"]
        resultat.credits_obtenus = donnees["credits_obtenus"]
        resultat.credits_total = donnees["credits_total"]
        resultat.statut = donnees["statut"]
        resultat.mention = donnees["mention"]
        resultat.detail = json.dumps(donnees, ensure_ascii=False)
        resultat.calcule_le = datetime.utcnow()
    element = Deliberation(
        resultat_id=resultat.id,
        decision=payload.decision,
        commentaire=payload.commentaire,
        jury=payload.jury,
    )
    resultat.decision = payload.decision
    resultat.verrouille = True
    db.add(element)
    db.commit()
    db.refresh(element)
    return element


@router.post("/deliberations/automatique")
def deliberation_automatique(
    semestre_id: int,
    session: int = 1,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    from ..models import Deliberation

    resultats = calculer_semestre(db, semestre_id, session, niveau_id)
    traites = 0
    for resultat in resultats:
        if resultat.verrouille:
            continue
        if resultat.statut == "Validé":
            decision = "ADMIS"
        elif resultat.statut == "Rattrapage":
            decision = "RATTRAPAGE"
        elif resultat.statut in ("Partiellement validé", "Ajourné"):
            decision = "AJOURNE"
        else:
            continue
        db.add(
            Deliberation(
                resultat_id=resultat.id,
                decision=decision,
                commentaire="Décision automatique proposée par le jury.",
                jury="Jury de délibération",
            )
        )
        resultat.decision = decision
        resultat.verrouille = True
        traites += 1
    db.commit()
    return {
        "ok": True,
        "traites": traites,
        "message": f"{traites} résultat(s) délibéré(s) automatiquement.",
    }


# =============================================================== 7. Documents
@router.get("/documents/releve/{inscription_id}")
def document_releve(
    inscription_id: int,
    semestre_id: int,
    session: int = 1,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise HTTPException(404, "Inscription introuvable")
    _verifier_document_etudiant(utilisateur, inscription)
    try:
        tampon, nom = generer_pdf_releve(db, inscription_id, semestre_id, session)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/documents/attestation/{inscription_id}")
def document_attestation(
    inscription_id: int,
    semestre_id: int,
    session: int = 1,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise HTTPException(404, "Inscription introuvable")
    _verifier_document_etudiant(utilisateur, inscription)
    try:
        tampon, nom = generer_pdf_attestation(db, inscription_id, semestre_id, session)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/documents/pv")
def document_pv(
    semestre_id: int,
    session: int = 1,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    try:
        tampon, nom = generer_pdf_pv(db, semestre_id, niveau_id, session)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/documents/releves")
def documents_releves_groupe(
    semestre_id: int,
    session: int = 1,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    requete = db.query(Inscription)
    if niveau_id:
        requete = requete.filter(Inscription.niveau_id == niveau_id)
    inscriptions = requete.order_by(Inscription.etudiant_id).all()
    if not inscriptions:
        raise HTTPException(404, "Aucun étudiant inscrit pour ces critères.")

    tampon = BytesIO()
    with ZipFile(tampon, "w", ZIP_DEFLATED) as archive:
        for inscription in inscriptions:
            try:
                pdf, nom = generer_pdf_releve(db, inscription.id, semestre_id, session)
            except ValueError:
                continue
            archive.writestr(nom, pdf.getvalue())
    tampon.seek(0)
    suffixe = f"niveau_{niveau_id}" if niveau_id else "tous_niveaux"
    return StreamingResponse(
        tampon,
        media_type="application/zip",
        headers={
            "Content-Disposition": (
                f'attachment; filename="releves_{semestre_id}_{suffixe}_S{session}.zip"'
            )
        },
    )


@router.get("/documents/passages")
def document_passages(
    annee: str,
    session: int = 1,
    mode: str = "10",
    seuil_dettes: float = 80,
    moyenne_passage: float = 10,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Liste globale des étudiants admis en classe supérieure (PDF)."""
    try:
        tampon, nom = generer_pdf_passages(
            db,
            annee=annee,
            session=session,
            mode=mode,
            seuil_dettes=seuil_dettes,
            moyenne_passage=moyenne_passage,
            niveau_id=niveau_id,
        )
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/documents/passage/{inscription_id}")
def document_releve_passage(
    inscription_id: int,
    session: int = 1,
    mode: str = "10",
    seuil_dettes: float = 80,
    moyenne_passage: float = 10,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Relevé récapitulatif de passage d'un étudiant (PDF)."""
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise HTTPException(404, "Inscription introuvable")
    _verifier_document_etudiant(utilisateur, inscription)
    try:
        tampon, nom = generer_pdf_releve_passage(
            db,
            inscription_id,
            session=session,
            mode=mode,
            seuil_dettes=seuil_dettes,
            moyenne_passage=moyenne_passage,
        )
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/documents/diplomes")
def documents_diplomes(
    annee: Optional[str] = None,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Étudiants éligibles aux attestations de réussite de diplôme."""
    return diplomes_eligibles(db, annee=annee, niveau_id=niveau_id)


@router.get("/documents/diplome/{etudiant_id}")
def document_diplome(
    etudiant_id: int,
    cycle: Optional[str] = None,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    """Attestation de réussite de diplôme (PDF)."""
    if _est_etudiant(utilisateur) and utilisateur.etudiant_id != etudiant_id:
        raise HTTPException(403, "Vous ne pouvez consulter que vos propres documents.")
    try:
        tampon, nom = generer_pdf_diplome(db, etudiant_id, cycle)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


# =============================================================== 8. Statistiques
@router.get("/statistiques")
def statistiques(
    semestre_id: int,
    session: int = 1,
    niveau_id: Optional[int] = None,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "Les statistiques ne sont pas accessibles à cet espace.")
    if _est_enseignant(utilisateur):
        ecue_ids = sorted(_ecue_ids_enseignant(db, utilisateur))
        if not ecue_ids:
            raise HTTPException(403, "Aucune ECUE ne vous est affectée.")
        donnees = statistiques_semestre(db, semestre_id, session, niveau_id, ecue_ids)
    else:
        calculer_semestre(db, semestre_id, session, niveau_id)
        donnees = statistiques_semestre(db, semestre_id, session, niveau_id)
    semestre = db.get(Semestre, semestre_id)
    donnees["semestre"] = (
        f"{semestre.nom} · {semestre.annee}" if semestre else str(semestre_id)
    )
    return donnees


# =============================================================== 9. Présences
@router.get("/presences")
def lister_presences(
    seance_id: int,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La feuille de présence n’est pas accessible à cet espace.")
    seance = db.get(Seance, seance_id)
    _verifier_seance(db, utilisateur, seance)
    existantes = {
        presence.inscription_id: presence
        for presence in db.query(Presence).filter(Presence.seance_id == seance_id).all()
    }
    lignes = []
    for inscription in _inscriptions_seance(db, seance):
        presence = existantes.get(inscription.id)
        lignes.append(
            {
                "presence_id": presence.id if presence else None,
                "inscription_id": inscription.id,
                "matricule": inscription.matricule,
                "etudiant_nom": inscription.etudiant_nom,
                "groupe_nom": inscription.groupe_nom,
                "present": presence.present if presence else True,
                "commentaire": presence.commentaire if presence else "",
                "saisie": presence is not None,
            }
        )
    return {
        "seance": {
            "id": seance.id,
            "ecue_code": seance.ecue_code,
            "ecue_nom": seance.ecue_nom,
            "groupes": seance.groupes_noms,
            "date": seance.creneau_jour,
        },
        "lignes": lignes,
    }


@router.post("/presences")
def enregistrer_presences(
    payload: PresencesMasse,
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    if _est_etudiant(utilisateur):
        raise HTTPException(403, "La feuille de présence n’est pas accessible à cet espace.")
    seance = db.get(Seance, payload.seance_id)
    _verifier_seance(db, utilisateur, seance)
    autorises = {inscription.id for inscription in _inscriptions_seance(db, seance)}
    enregistrees = 0
    for ligne in payload.presences:
        if ligne.inscription_id not in autorises:
            continue
        presence = (
            db.query(Presence)
            .filter(
                Presence.seance_id == seance.id,
                Presence.inscription_id == ligne.inscription_id,
            )
            .first()
        )
        if presence is None:
            presence = Presence(seance_id=seance.id, inscription_id=ligne.inscription_id)
            db.add(presence)
        presence.present = ligne.present
        presence.commentaire = ligne.commentaire or ""
        presence.maj_le = datetime.utcnow()
        enregistrees += 1
    db.commit()
    return {
        "ok": True,
        "enregistrees": enregistrees,
        "message": f"{enregistrees} présence(s) enregistrée(s).",
    }
