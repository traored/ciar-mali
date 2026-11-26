"""Importation des données depuis un classeur Excel."""
import unicodedata
from datetime import date, datetime
from io import BytesIO

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import (
    Affectation,
    Creneau,
    Departement,
    ECUE,
    Enseignant,
    Filiere,
    GRADES_ENSEIGNANT,
    Groupe,
    Niveau,
    Salle,
    Semestre,
    UE,
    Utilisateur,
)
from ..security import admin_ou_gestionnaire, utilisateur_courant

router = APIRouter(prefix="/api/importer", tags=["import Excel"])

JOURS = {"lundi": 0, "mardi": 1, "mercredi": 2, "jeudi": 3, "vendredi": 4, "samedi": 5}


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


def _entier(valeur, defaut=0) -> int:
    if valeur in (None, ""):
        return defaut
    try:
        return int(float(str(valeur).replace(",", ".")))
    except (TypeError, ValueError):
        return defaut


def _entier_controle(valeur, champ: str, defaut: int = 0) -> int:
    """Comme _entier, mais signale les valeurs non numériques dans le rapport d'import."""
    if valeur in (None, ""):
        return defaut
    try:
        return int(float(str(valeur).replace(",", ".")))
    except (TypeError, ValueError):
        raise ValueError(f"{champ} invalide : « {valeur} » (nombre entier attendu)")


def _booleen(valeur) -> bool:
    return _normaliser(valeur) in {"oui", "o", "1", "true", "vrai", "x"}


def _date(valeur) -> date:
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
    raise ValueError(f"Date invalide : {texte or '(vide)'}")


def _jour(valeur) -> int:
    if isinstance(valeur, (int, float)):
        nombre = int(valeur)
        if 1 <= nombre <= 6:
            return nombre - 1
        if 0 <= nombre <= 5:
            return nombre
    nom = _normaliser(valeur)
    if nom in JOURS:
        return JOURS[nom]
    raise ValueError(f"Jour invalide : {valeur}")


def _feuille(classeur, nom: str):
    cible = _normaliser(nom)
    for feuille in classeur.worksheets:
        if _normaliser(feuille.title) == cible:
            return feuille
    return None


def _entetes(feuille) -> dict[str, int]:
    entetes = {}
    for cellule in feuille[1]:
        if cellule.value:
            entetes[_normaliser(cellule.value)] = cellule.column - 1
    return entetes


def _valeur(ligne, entetes: dict, *noms):
    for nom in noms:
        index = entetes.get(_normaliser(nom))
        if index is not None and index < len(ligne):
            return ligne[index]
    return None


@router.get("/modele")
def telecharger_modele(_: Utilisateur = Depends(utilisateur_courant)):
    classeur = Workbook()
    feuilles = {
        "Départements": ["Code", "Nom", "Chef", "Email"],
        "Filières": ["Code", "Nom", "Département (code)"],
        "Niveaux": ["Nom", "Ordre", "Filière (code)"],
        "Groupes": ["Nom", "Effectif", "Niveau", "Filière (code)"],
        "Enseignants": [
            "Prénom",
            "Nom",
            "Email",
            "Téléphone",
            "Matricule",
            "Date de naissance",
            "Lieu de naissance",
            "Statut",
            "Grade",
            "Département (code)",
            "Heures max",
            "Actif",
        ],
        "Salles": ["Nom", "Bâtiment", "Capacité", "Type"],
        "Créneaux": ["Jour", "Début", "Fin", "Libellé"],
        "Semestres": ["Nom", "Année", "Début", "Fin", "Semaines", "Actif"],
        "UE": ["Code", "Nom", "Crédits", "Semestre", "Année", "Niveau", "Filière (code)", "Département (code)"],
        "ECUE": ["Code", "Nom", "UE (code)", "Semestre", "Année", "Heures CM", "Heures TD", "Heures TP"],
        "Affectations": [
            "Enseignant (email)",
            "ECUE (code)",
            "Semestre",
            "Année",
            "Groupe",
            "Filière (code)",
            "Niveau",
            "Heures CM",
            "Heures TD",
            "Heures TP",
            "CM commun",
        ],
    }
    premiere = classeur.active
    premiere.title = "Lisez-moi"
    premiere["A1"] = "Modèle d'importation — Gestion des emplois du temps"
    premiere["A1"].font = Font(bold=True, size=14)
    lignes = [
        "Remplissez les feuilles ci-dessous. Les colonnes doivent conserver leurs en-têtes.",
        "Les codes servent de clés : un enregistrement existant est mis à jour.",
        "Les champs « Département (code) », « Filière (code) », « UE (code) », « ECUE (code) » font référence aux codes.",
        "Format des dates : JJ/MM/AAAA. Les jours : Lundi à Samedi.",
        "« CM commun » accepte Oui/Non : le CM est alors mutualisé entre les groupes du même niveau.",
        "Pour les ECUE et les affectations, renseignez « Semestre » et « Année » si plusieurs occurrences partagent le même code.",
        "Feuilles disponibles : " + ", ".join(feuilles.keys()),
    ]
    for index, texte in enumerate(lignes, start=3):
        premiere.cell(row=index, column=1, value=texte)
    premiere.column_dimensions["A"].width = 120
    for nom, colonnes in feuilles.items():
        feuille = classeur.create_sheet(nom)
        feuille.append(colonnes)
        for cellule in feuille[1]:
            cellule.font = Font(bold=True, color="FFFFFF")
            cellule.fill = PatternFill("solid", fgColor="1E3A8A")
        for index, colonne in enumerate(colonnes, start=1):
            feuille.column_dimensions[feuille.cell(row=1, column=index).column_letter].width = max(
                14, min(30, len(colonne) + 4)
            )
    flux = BytesIO()
    classeur.save(flux)
    flux.seek(0)
    return StreamingResponse(
        flux,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": 'attachment; filename="modele_import_edt.xlsx"'},
    )


@router.post("/excel")
async def importer_excel(
    fichier: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    if not fichier.filename.lower().endswith((".xlsx", ".xlsm")):
        raise HTTPException(400, "Le fichier doit être au format .xlsx")
    try:
        classeur = load_workbook(BytesIO(await fichier.read()), data_only=True)
    except Exception:
        raise HTTPException(400, "Impossible de lire le classeur Excel")

    importes = {
        "Départements": 0,
        "Filières": 0,
        "Niveaux": 0,
        "Groupes": 0,
        "Enseignants": 0,
        "Salles": 0,
        "Créneaux": 0,
        "Semestres": 0,
        "UE": 0,
        "ECUE": 0,
        "Affectations": 0,
    }
    erreurs = []

    def traiter(nom_feuille, fonction, colonnes_requises=None):
        feuille = _feuille(classeur, nom_feuille)
        if feuille is None:
            return
        entetes = _entetes(feuille)
        if colonnes_requises:
            manquantes = [
                libelle
                for alternatives, libelle in colonnes_requises
                if not any(_normaliser(alternative) in entetes for alternative in alternatives)
            ]
            if manquantes:
                erreurs.append(
                    {
                        "feuille": nom_feuille,
                        "ligne": 1,
                        "message": (
                            "Colonne(s) obligatoire(s) absente(s) : "
                            + ", ".join(manquantes)
                            + ". Téléchargez le modèle pour retrouver les en-têtes attendus."
                        ),
                    }
                )
                return
        for numero, ligne in enumerate(feuille.iter_rows(min_row=2, values_only=True), start=2):
            if all(v in (None, "") for v in ligne):
                continue
            try:
                fonction(ligne, entetes)
                db.commit()
                importes[nom_feuille] += 1
            except Exception as exc:
                db.rollback()
                erreurs.append(
                    {"feuille": nom_feuille, "ligne": numero, "message": str(exc)[:300]}
                )

    # Départements
    def _departements(ligne, entetes):
        code = _texte(_valeur(ligne, entetes, "Code", "Département (code)"))
        nom = _texte(_valeur(ligne, entetes, "Nom"))
        if not code or not nom:
            raise ValueError("Code et nom obligatoires")
        obj = db.query(Departement).filter(Departement.code == code).first()
        if not obj:
            obj = Departement(code=code)
            db.add(obj)
        obj.nom = nom
        obj.chef = _texte(_valeur(ligne, entetes, "Chef"))
        obj.email = _texte(_valeur(ligne, entetes, "Email"))

    # Filières
    def _filieres(ligne, entetes):
        code = _texte(_valeur(ligne, entetes, "Code", "Filière (code)"))
        nom = _texte(_valeur(ligne, entetes, "Nom"))
        code_dep = _texte(_valeur(ligne, entetes, "Département (code)", "Département"))
        if not code or not nom:
            raise ValueError("Code et nom obligatoires")
        departement = db.query(Departement).filter(Departement.code == code_dep).first()
        if not departement:
            raise ValueError(f"Département introuvable : {code_dep}")
        obj = db.query(Filiere).filter(Filiere.code == code).first()
        if not obj:
            obj = Filiere(code=code)
            db.add(obj)
        obj.nom = nom
        obj.departement_id = departement.id

    # Niveaux
    def _niveaux(ligne, entetes):
        nom = _texte(_valeur(ligne, entetes, "Nom", "Niveau"))
        code_filiere = _texte(_valeur(ligne, entetes, "Filière (code)", "Filière"))
        filiere = db.query(Filiere).filter(Filiere.code == code_filiere).first()
        if not nom:
            raise ValueError("Nom obligatoire")
        if not filiere:
            raise ValueError(f"Filière introuvable : {code_filiere}")
        obj = (
            db.query(Niveau)
            .filter(Niveau.nom == nom, Niveau.filiere_id == filiere.id)
            .first()
        )
        if not obj:
            obj = Niveau(nom=nom, filiere_id=filiere.id)
            db.add(obj)
        obj.ordre = _entier(_valeur(ligne, entetes, "Ordre"), 1)

    # Groupes
    def _groupes(ligne, entetes):
        nom = _texte(_valeur(ligne, entetes, "Nom", "Groupe"))
        nom_niveau = _texte(_valeur(ligne, entetes, "Niveau"))
        code_filiere = _texte(_valeur(ligne, entetes, "Filière (code)", "Filière"))
        niveau = (
            db.query(Niveau)
            .join(Filiere)
            .filter(Niveau.nom == nom_niveau, Filiere.code == code_filiere)
            .first()
        )
        if not nom:
            raise ValueError("Nom du groupe obligatoire")
        if not niveau:
            raise ValueError(f"Niveau introuvable : {nom_niveau} / {code_filiere}")
        obj = (
            db.query(Groupe)
            .filter(Groupe.nom == nom, Groupe.niveau_id == niveau.id)
            .first()
        )
        if not obj:
            obj = Groupe(nom=nom, niveau_id=niveau.id)
            db.add(obj)
        obj.effectif = _entier(_valeur(ligne, entetes, "Effectif"), 30)

    # Enseignants
    def _enseignants(ligne, entetes):
        email = _texte(_valeur(ligne, entetes, "Email"))
        prenom = _texte(_valeur(ligne, entetes, "Prénom"))
        nom = _texte(_valeur(ligne, entetes, "Nom"))
        if not email or not prenom or not nom:
            raise ValueError("Prénom, nom et email obligatoires")
        code_dep = _texte(_valeur(ligne, entetes, "Département (code)", "Département"))
        departement = db.query(Departement).filter(Departement.code == code_dep).first() if code_dep else None
        obj = db.query(Enseignant).filter(Enseignant.email == email).first()
        if not obj:
            obj = Enseignant(email=email)
            db.add(obj)
        obj.prenom = prenom
        obj.nom = nom
        obj.telephone = _texte(_valeur(ligne, entetes, "Téléphone"))
        obj.matricule = _texte(_valeur(ligne, entetes, "Matricule")).strip() or None
        naissance = _valeur(ligne, entetes, "Date de naissance")
        obj.date_naissance = _date(naissance) if naissance not in (None, "") else None
        obj.lieu_naissance = _texte(_valeur(ligne, entetes, "Lieu de naissance"))
        obj.statut = _texte(_valeur(ligne, entetes, "Statut")) or "Permanent"
        grade = _texte(_valeur(ligne, entetes, "Grade")) or "Master"
        if grade not in GRADES_ENSEIGNANT:
            raise ValueError(f"Grade invalide : {grade}")
        obj.grade = grade
        obj.departement_id = departement.id if departement else None
        obj.heures_max = _entier(_valeur(ligne, entetes, "Heures max"), 192)
        obj.actif = _booleen(_valeur(ligne, entetes, "Actif")) if _valeur(ligne, entetes, "Actif") not in (None, "") else True

    # Salles
    def _salles(ligne, entetes):
        nom = _texte(_valeur(ligne, entetes, "Nom", "Salle"))
        if not nom:
            raise ValueError("Nom de salle obligatoire")
        obj = db.query(Salle).filter(Salle.nom == nom).first()
        if not obj:
            obj = Salle(nom=nom)
            db.add(obj)
        obj.batiment = _texte(_valeur(ligne, entetes, "Bâtiment"))
        obj.capacite = _entier(_valeur(ligne, entetes, "Capacité"), 40)
        obj.type_salle = _texte(_valeur(ligne, entetes, "Type")) or "Salle TD"

    # Créneaux
    def _creneaux(ligne, entetes):
        jour = _jour(_valeur(ligne, entetes, "Jour"))
        debut = _texte(_valeur(ligne, entetes, "Début"))
        fin = _texte(_valeur(ligne, entetes, "Fin"))
        if not debut or not fin:
            raise ValueError("Début et fin obligatoires")
        obj = (
            db.query(Creneau)
            .filter(Creneau.jour == jour, Creneau.debut == debut)
            .first()
        )
        if not obj:
            obj = Creneau(jour=jour, debut=debut)
            db.add(obj)
        obj.fin = fin
        obj.libelle = _texte(_valeur(ligne, entetes, "Libellé"))

    # Semestres
    def _semestres(ligne, entetes):
        nom = _texte(_valeur(ligne, entetes, "Nom", "Semestre"))
        annee = _texte(_valeur(ligne, entetes, "Année")) or "2025-2026"
        if not nom:
            raise ValueError("Nom du semestre obligatoire")
        obj = (
            db.query(Semestre)
            .filter(Semestre.nom == nom, Semestre.annee == annee)
            .first()
        )
        if not obj:
            obj = Semestre(nom=nom, annee=annee)
            db.add(obj)
        obj.date_debut = _date(_valeur(ligne, entetes, "Début"))
        obj.date_fin = _date(_valeur(ligne, entetes, "Fin"))
        obj.semaines = _entier(_valeur(ligne, entetes, "Semaines"), 12)
        obj.actif = _booleen(_valeur(ligne, entetes, "Actif"))

    # UE
    def _ues(ligne, entetes):
        code = _texte(_valeur(ligne, entetes, "Code", "UE (code)"))
        nom = _texte(_valeur(ligne, entetes, "Nom"))
        nom_semestre = _texte(_valeur(ligne, entetes, "Semestre"))
        annee = _texte(_valeur(ligne, entetes, "Année"))
        nom_niveau = _texte(_valeur(ligne, entetes, "Niveau"))
        code_filiere = _texte(_valeur(ligne, entetes, "Filière (code)", "Filière"))
        code_dep = _texte(_valeur(ligne, entetes, "Département (code)", "Département"))
        if not code or not nom:
            raise ValueError("Code et nom obligatoires")
        semestre = db.query(Semestre).filter(Semestre.nom == nom_semestre)
        if annee:
            semestre = semestre.filter(Semestre.annee == annee)
        semestre = semestre.first()
        if not semestre:
            raise ValueError(f"Semestre introuvable : {nom_semestre} {annee}")
        niveau = (
            db.query(Niveau)
            .join(Filiere)
            .filter(Niveau.nom == nom_niveau, Filiere.code == code_filiere)
            .first()
        )
        if not niveau:
            raise ValueError(f"Niveau introuvable : {nom_niveau} / {code_filiere}")
        departement = db.query(Departement).filter(Departement.code == code_dep).first() if code_dep else None
        obj = (
            db.query(UE)
            .filter(UE.code == code, UE.semestre_id == semestre.id)
            .first()
        )
        if not obj:
            obj = UE(code=code, semestre_id=semestre.id)
            db.add(obj)
        obj.nom = nom
        obj.credits = _entier(_valeur(ligne, entetes, "Crédits"), 6)
        obj.niveau_id = niveau.id
        obj.departement_id = departement.id if departement else None

    # ECUE
    def _ecues(ligne, entetes):
        code = _texte(_valeur(ligne, entetes, "Code", "ECUE (code)"))
        nom = _texte(_valeur(ligne, entetes, "Nom"))
        code_ue = _texte(_valeur(ligne, entetes, "UE (code)", "UE"))
        manquants = [
            libelle
            for libelle, valeur in (
                ("Code", code),
                ("Nom", nom),
                ("UE (code)", code_ue),
            )
            if not valeur
        ]
        if manquants:
            raise ValueError(
                "Champ(s) obligatoire(s) vide(s) : " + ", ".join(manquants)
            )
        nom_semestre = _texte(_valeur(ligne, entetes, "Semestre"))
        annee = _texte(_valeur(ligne, entetes, "Année", "Annee"))
        candidats = db.query(UE).filter(UE.code == code_ue).all()
        if nom_semestre:
            candidats = [
                ue
                for ue in candidats
                if ue.semestre
                and _normaliser(ue.semestre.nom) == _normaliser(nom_semestre)
            ]
        if annee:
            candidats = [
                ue
                for ue in candidats
                if ue.semestre and ue.semestre.annee == annee
            ]
        if not candidats:
            contexte = " ".join(
                valeur for valeur in (code_ue, nom_semestre, annee) if valeur
            )
            raise ValueError(
                f"UE introuvable pour « {contexte} » : vérifiez la feuille UE "
                "(code, semestre et année)."
            )
        ue = candidats[0]
        if len(candidats) > 1:
            existant = (
                db.query(ECUE)
                .filter(
                    ECUE.code == code,
                    ECUE.ue_id.in_([candidat.id for candidat in candidats]),
                )
                .first()
            )
            if existant:
                ue = existant.ue
            else:
                details = " ; ".join(
                    f"{candidat.code} — {candidat.semestre.nom} "
                    f"{candidat.semestre.annee}"
                    for candidat in candidats
                    if candidat.semestre
                )
                raise ValueError(
                    f"UE ambiguë : {len(candidats)} UE portent le code "
                    f"« {code_ue} » ({details}). Ajoutez les colonnes "
                    "« Semestre » et « Année » pour lever l’ambiguïté."
                )
        obj = (
            db.query(ECUE)
            .filter(ECUE.code == code, ECUE.semestre_id == ue.semestre_id)
            .first()
        )
        if not obj:
            obj = ECUE(code=code)
            db.add(obj)
        obj.nom = nom
        obj.ue_id = ue.id
        obj.semestre_id = ue.semestre_id
        obj.heures_cm = _entier_controle(
            _valeur(ligne, entetes, "Heures CM"), "Heures CM"
        )
        obj.heures_td = _entier_controle(
            _valeur(ligne, entetes, "Heures TD"), "Heures TD"
        )
        obj.heures_tp = _entier_controle(
            _valeur(ligne, entetes, "Heures TP"), "Heures TP"
        )

    # Affectations
    def _affectations(ligne, entetes):
        email = _texte(_valeur(ligne, entetes, "Enseignant (email)", "Enseignant"))
        code_ecue = _texte(_valeur(ligne, entetes, "ECUE (code)", "ECUE"))
        nom_semestre = _texte(_valeur(ligne, entetes, "Semestre"))
        annee = _texte(_valeur(ligne, entetes, "Année", "Annee"))
        nom_groupe = _texte(_valeur(ligne, entetes, "Groupe"))
        code_filiere = _texte(_valeur(ligne, entetes, "Filière (code)", "Filière"))
        nom_niveau = _texte(_valeur(ligne, entetes, "Niveau"))
        enseignant = db.query(Enseignant).filter(Enseignant.email == email).first()
        if not enseignant:
            raise ValueError(f"Enseignant introuvable : {email}")
        if not code_ecue:
            raise ValueError("Code de l’ECUE obligatoire")
        candidats = db.query(ECUE).filter(ECUE.code == code_ecue).all()
        if nom_semestre:
            candidats = [
                ecue
                for ecue in candidats
                if ecue.semestre
                and _normaliser(ecue.semestre.nom) == _normaliser(nom_semestre)
            ]
        if annee:
            candidats = [
                ecue
                for ecue in candidats
                if ecue.semestre and ecue.semestre.annee == annee
            ]
        if not candidats:
            contexte = " ".join(
                valeur for valeur in (code_ecue, nom_semestre, annee) if valeur
            )
            raise ValueError(
                f"ECUE introuvable : {contexte}. Vérifiez la feuille ECUE "
                "(code, semestre et année)."
            )
        if len(candidats) > 1:
            details = " ; ".join(
                f"{ecue.code} — {ecue.semestre.nom} {ecue.semestre.annee}"
                for ecue in candidats
                if ecue.semestre
            )
            raise ValueError(
                f"ECUE ambigu : {len(candidats)} occurrences portent le code "
                f"« {code_ecue} » ({details}). Ajoutez les colonnes "
                "« Semestre » et « Année » pour lever l’ambiguïté."
            )
        ecue = candidats[0]
        requete = db.query(Groupe).join(Niveau).join(Filiere).filter(Groupe.nom == nom_groupe)
        if code_filiere:
            requete = requete.filter(Filiere.code == code_filiere)
        if nom_niveau:
            requete = requete.filter(Niveau.nom == nom_niveau)
        groupe = requete.first()
        if not groupe:
            raise ValueError(f"Groupe introuvable : {nom_groupe} / {code_filiere}")
        obj = (
            db.query(Affectation)
            .filter(
                Affectation.enseignant_id == enseignant.id,
                Affectation.ecue_id == ecue.id,
                Affectation.groupe_id == groupe.id,
            )
            .first()
        )
        if not obj:
            obj = Affectation(
                enseignant_id=enseignant.id, ecue_id=ecue.id, groupe_id=groupe.id
            )
            db.add(obj)
        obj.semestre_id = ecue.semestre_id
        obj.heures_cm = _entier(_valeur(ligne, entetes, "Heures CM"), 0)
        obj.heures_td = _entier(_valeur(ligne, entetes, "Heures TD"), 0)
        obj.heures_tp = _entier(_valeur(ligne, entetes, "Heures TP"), 0)
        obj.cm_commun = _booleen(_valeur(ligne, entetes, "CM commun"))

    traiter("Départements", _departements)
    traiter("Filières", _filieres)
    traiter("Niveaux", _niveaux)
    traiter("Groupes", _groupes)
    traiter("Enseignants", _enseignants)
    traiter("Salles", _salles)
    traiter("Créneaux", _creneaux)
    traiter("Semestres", _semestres)
    traiter("UE", _ues)
    traiter(
        "ECUE",
        _ecues,
        colonnes_requises=[
            (("Code", "ECUE (code)"), "Code"),
            (("Nom",), "Nom"),
            (("UE (code)", "UE"), "UE (code)"),
        ],
    )
    traiter("Affectations", _affectations)

    return {
        "importes": importes,
        "total": sum(importes.values()),
        "erreurs": erreurs,
        "message": f"{sum(importes.values())} ligne(s) importée(s), {len(erreurs)} erreur(s).",
    }
