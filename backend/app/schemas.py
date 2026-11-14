"""Schémas Pydantic (validation des entrées / sérialisation des sorties)."""
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------- Authentification
class LoginRequest(BaseModel):
    identifiant: str
    mot_de_passe: str


class UtilisateurOut(ORMModel):
    id: int
    identifiant: str
    nom_complet: str
    role: str
    actif: bool
    enseignant_id: Optional[int] = None
    etudiant_id: Optional[int] = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    utilisateur: UtilisateurOut


class UtilisateurCreate(BaseModel):
    identifiant: str = Field(min_length=3, max_length=80)
    mot_de_passe: str = Field(min_length=4)
    nom_complet: str = ""
    role: str = "lecteur"
    actif: bool = True
    enseignant_id: Optional[int] = None
    etudiant_id: Optional[int] = None


class UtilisateurUpdate(BaseModel):
    identifiant: Optional[str] = None
    mot_de_passe: Optional[str] = None
    nom_complet: Optional[str] = None
    role: Optional[str] = None
    actif: Optional[bool] = None
    enseignant_id: Optional[int] = None
    etudiant_id: Optional[int] = None


# ---------------------------------------------------------------- Structure
class DepartementCreate(BaseModel):
    code: str
    nom: str
    chef: str = ""
    email: str = ""


class DepartementUpdate(BaseModel):
    code: Optional[str] = None
    nom: Optional[str] = None
    chef: Optional[str] = None
    email: Optional[str] = None


class DepartementOut(ORMModel):
    id: int
    code: str
    nom: str
    chef: str
    email: str


class FiliereCreate(BaseModel):
    code: str
    nom: str
    departement_id: int


class FiliereUpdate(BaseModel):
    code: Optional[str] = None
    nom: Optional[str] = None
    departement_id: Optional[int] = None


class FiliereOut(ORMModel):
    id: int
    code: str
    nom: str
    departement_id: int
    departement_nom: str = ""


class NiveauCreate(BaseModel):
    nom: str
    ordre: int = 1
    filiere_id: int


class NiveauUpdate(BaseModel):
    nom: Optional[str] = None
    ordre: Optional[int] = None
    filiere_id: Optional[int] = None


class NiveauOut(ORMModel):
    id: int
    nom: str
    ordre: int
    filiere_id: int
    filiere_nom: str = ""
    filiere_code: str = ""


class GroupeCreate(BaseModel):
    nom: str
    effectif: int = 30
    niveau_id: int


class GroupeUpdate(BaseModel):
    nom: Optional[str] = None
    effectif: Optional[int] = None
    niveau_id: Optional[int] = None


class GroupeOut(ORMModel):
    id: int
    nom: str
    effectif: int
    niveau_id: int
    niveau_nom: str = ""
    filiere_nom: str = ""
    filiere_code: str = ""


# ---------------------------------------------------------------- Enseignants / salles
GRADES_ENSEIGNANT = (
    "Professeur",
    "Maître de Conférences",
    "Maître Assistant",
    "Assistant",
    "Ingénieur",
    "Master",
)
STATUTS_ENSEIGNANT = ("Permanent", "Vacataire")


class _ValidationEnseignant(BaseModel):
    @field_validator("grade", check_fields=False)
    @classmethod
    def _grade_valide(cls, valeur: str | None) -> str | None:
        if valeur is None:
            return valeur
        if valeur not in GRADES_ENSEIGNANT:
            raise ValueError(f"Grade invalide. Valeurs possibles : {', '.join(GRADES_ENSEIGNANT)}")
        return valeur

    @field_validator("statut", check_fields=False)
    @classmethod
    def _statut_valide(cls, valeur: str | None) -> str | None:
        if valeur is None:
            return valeur
        if valeur not in STATUTS_ENSEIGNANT:
            raise ValueError(f"Statut invalide. Valeurs possibles : {', '.join(STATUTS_ENSEIGNANT)}")
        return valeur

    @field_validator("matricule", check_fields=False)
    @classmethod
    def _matricule_normalise(cls, valeur: str | None) -> str | None:
        if valeur is None:
            return None
        valeur = valeur.strip()
        return valeur or None


class EnseignantCreate(_ValidationEnseignant):
    prenom: str
    nom: str
    email: str
    telephone: str = ""
    date_naissance: Optional[date] = None
    lieu_naissance: str = ""
    statut: str = "Permanent"
    matricule: Optional[str] = None
    grade: str = "Master"
    departement_id: Optional[int] = None
    heures_max: int = 192
    actif: bool = True


class EnseignantUpdate(_ValidationEnseignant):
    prenom: Optional[str] = None
    nom: Optional[str] = None
    email: Optional[str] = None
    telephone: Optional[str] = None
    date_naissance: Optional[date] = None
    lieu_naissance: Optional[str] = None
    statut: Optional[str] = None
    matricule: Optional[str] = None
    grade: Optional[str] = None
    departement_id: Optional[int] = None
    heures_max: Optional[int] = None
    actif: Optional[bool] = None


class EnseignantOut(ORMModel):
    id: int
    prenom: str
    nom: str
    email: str
    telephone: str
    date_naissance: Optional[date] = None
    lieu_naissance: str
    statut: str
    matricule: Optional[str] = None
    grade: str
    departement_id: Optional[int] = None
    heures_max: int
    actif: bool
    nom_complet: str = ""
    nom_affichage: str = ""
    titre: str = ""
    departement_nom: str = ""


class SalleCreate(BaseModel):
    nom: str
    batiment: str = ""
    capacite: int = 40
    type_salle: str = "Salle TD"


class SalleUpdate(BaseModel):
    nom: Optional[str] = None
    batiment: Optional[str] = None
    capacite: Optional[int] = None
    type_salle: Optional[str] = None


class SalleOut(ORMModel):
    id: int
    nom: str
    batiment: str
    capacite: int
    type_salle: str


class CreneauCreate(BaseModel):
    jour: int = Field(ge=0, le=5)
    debut: str
    fin: str
    libelle: str = ""


class CreneauUpdate(BaseModel):
    jour: Optional[int] = None
    debut: Optional[str] = None
    fin: Optional[str] = None
    libelle: Optional[str] = None


class CreneauOut(ORMModel):
    id: int
    jour: int
    debut: str
    fin: str
    libelle: str
    duree: float


# ---------------------------------------------------------------- Semestres / UE / ECUE
class SemestreCreate(BaseModel):
    nom: str
    annee: str = "2025-2026"
    date_debut: date
    date_fin: date
    semaines: int = 12
    actif: bool = True


class SemestreUpdate(BaseModel):
    nom: Optional[str] = None
    annee: Optional[str] = None
    date_debut: Optional[date] = None
    date_fin: Optional[date] = None
    semaines: Optional[int] = None
    actif: Optional[bool] = None


class SemestreOut(ORMModel):
    id: int
    nom: str
    annee: str
    date_debut: date
    date_fin: date
    semaines: int
    actif: bool


class UECreate(BaseModel):
    code: str
    nom: str
    credits: int = 6
    semestre_id: int
    niveau_id: Optional[int] = None
    niveau_ids: Optional[list[int]] = None
    departement_id: Optional[int] = None


class UEUpdate(BaseModel):
    code: Optional[str] = None
    nom: Optional[str] = None
    credits: Optional[int] = None
    semestre_id: Optional[int] = None
    niveau_id: Optional[int] = None
    niveau_ids: Optional[list[int]] = None
    departement_id: Optional[int] = None


class UEOut(ORMModel):
    id: int
    code: str
    nom: str
    credits: int
    semestre_id: int
    niveau_id: int
    departement_id: Optional[int] = None
    niveau_ids: list[int] = []
    niveaux_noms: list[str] = []
    semestre_nom: str = ""
    niveau_nom: str = ""
    departement_nom: str = ""


class CopieUE(BaseModel):
    semestre_source_id: int
    semestre_cible_id: int
    niveau_ids: Optional[list[int]] = None


class ECUECreate(BaseModel):
    code: str
    nom: str
    credits: int = 1
    ue_id: int
    semestre_id: Optional[int] = None
    heures_cm: int = 0
    heures_td: int = 0
    heures_tp: int = 0


class ECUEUpdate(BaseModel):
    code: Optional[str] = None
    nom: Optional[str] = None
    credits: Optional[int] = None
    ue_id: Optional[int] = None
    semestre_id: Optional[int] = None
    heures_cm: Optional[int] = None
    heures_td: Optional[int] = None
    heures_tp: Optional[int] = None


class ECUEOut(ORMModel):
    id: int
    code: str
    nom: str
    credits: int
    ue_id: int
    heures_cm: int
    heures_td: int
    heures_tp: int
    total_heures: int = 0
    ue_code: str = ""
    ue_nom: str = ""
    niveau_id: Optional[int] = None
    niveau_nom: str = ""
    semestre_id: Optional[int] = None
    semestre_nom: str = ""
    annee: str = ""


class AffectationCreate(BaseModel):
    semestre_id: Optional[int] = None
    enseignant_id: int
    ecue_id: int
    groupe_id: int
    heures_cm: int = 0
    heures_td: int = 0
    heures_tp: int = 0
    cm_commun: bool = False


class AffectationUpdate(BaseModel):
    semestre_id: Optional[int] = None
    enseignant_id: Optional[int] = None
    ecue_id: Optional[int] = None
    groupe_id: Optional[int] = None
    heures_cm: Optional[int] = None
    heures_td: Optional[int] = None
    heures_tp: Optional[int] = None
    cm_commun: Optional[bool] = None


class AffectationOut(ORMModel):
    id: int
    semestre_id: int
    enseignant_id: int
    ecue_id: int
    groupe_id: int
    heures_cm: int
    heures_td: int
    heures_tp: int
    cm_commun: bool
    total_heures: int = 0
    semestre_nom: str = ""
    annee: str = ""
    enseignant_nom: str = ""
    ecue_code: str = ""
    ecue_nom: str = ""
    groupe_nom: str = ""


# ---------------------------------------------------------------- Séances
class SeanceCreate(BaseModel):
    semestre_id: int
    semaine: int = Field(ge=1)
    creneau_id: int
    salle_id: Optional[int] = None
    enseignant_id: int
    ecue_id: int
    affectation_id: Optional[int] = None
    type_seance: str = "CM"
    statut: str = "planifiee"
    verrouillee: bool = False
    notes: str = ""
    groupe_ids: list[int] = Field(min_length=1)


class SeanceReguliereCreate(SeanceCreate):
    """Création d'une séance répétée sur plusieurs semaines consécutives."""

    semaine_fin: Optional[int] = None


class ConflitSemaine(BaseModel):
    semaine: int
    messages: list[str]


class SeanceReguliereOut(BaseModel):
    creees: int
    semaines: list[int]
    conflits: list[ConflitSemaine] = []
    message: str


class SeanceUpdate(BaseModel):
    semestre_id: Optional[int] = None
    semaine: Optional[int] = None
    creneau_id: Optional[int] = None
    salle_id: Optional[int] = None
    enseignant_id: Optional[int] = None
    ecue_id: Optional[int] = None
    affectation_id: Optional[int] = None
    type_seance: Optional[str] = None
    statut: Optional[str] = None
    verrouillee: Optional[bool] = None
    notes: Optional[str] = None
    groupe_ids: Optional[list[int]] = None


class SeanceOut(ORMModel):
    id: int
    semestre_id: int
    semaine: int
    creneau_id: int
    salle_id: Optional[int] = None
    enseignant_id: int
    ecue_id: int
    affectation_id: Optional[int] = None
    type_seance: str
    statut: str
    verrouillee: bool
    notes: str
    duree: float = 0
    salle_nom: str = ""
    enseignant_nom: str = ""
    ecue_code: str = ""
    ecue_nom: str = ""
    niveau_nom: str = ""
    creneau_jour: int = 0
    creneau_debut: str = ""
    creneau_fin: str = ""
    groupe_ids: list[int] = []
    groupes_noms: str = ""


class StatutUpdate(BaseModel):
    statut: str


# ---------------------------------------------------------------- Génération
class GenerationRequest(BaseModel):
    semestre_id: int
    remplacer: bool = True


class GenerationResult(BaseModel):
    crees: int
    non_placees: list[dict]
    message: str


# =================================================================== Gestion des notes
class EtudiantCreate(BaseModel):
    matricule: Optional[str] = None
    prenom: str
    nom: str
    sexe: str = ""
    date_naissance: Optional[date] = None
    lieu_naissance: str = ""
    telephone: str = ""
    email: str = ""
    filiere_id: Optional[int] = None


class EtudiantUpdate(BaseModel):
    matricule: Optional[str] = None
    prenom: Optional[str] = None
    nom: Optional[str] = None
    sexe: Optional[str] = None
    date_naissance: Optional[date] = None
    lieu_naissance: Optional[str] = None
    telephone: Optional[str] = None
    email: Optional[str] = None
    filiere_id: Optional[int] = None


class EtudiantOut(ORMModel):
    id: int
    matricule: str
    prenom: str
    nom: str
    sexe: str
    date_naissance: Optional[date] = None
    lieu_naissance: str
    telephone: str
    email: str
    filiere_id: Optional[int] = None
    nom_complet: str = ""
    filiere_nom: str = ""
    filiere_code: str = ""
    nb_inscriptions: int = 0


class InscriptionCreate(BaseModel):
    etudiant_id: int
    annee: str = "2025-2026"
    niveau_id: int
    groupe_id: Optional[int] = None
    statut: str = "Inscrit"
    date_inscription: Optional[date] = None


class InscriptionUpdate(BaseModel):
    etudiant_id: Optional[int] = None
    annee: Optional[str] = None
    niveau_id: Optional[int] = None
    groupe_id: Optional[int] = None
    statut: Optional[str] = None
    date_inscription: Optional[date] = None


class InscriptionOut(ORMModel):
    id: int
    etudiant_id: int
    annee: str
    niveau_id: int
    groupe_id: Optional[int] = None
    statut: str
    date_inscription: date
    etudiant_nom: str = ""
    matricule: str = ""
    niveau_nom: str = ""
    filiere_nom: str = ""
    filiere_code: str = ""
    groupe_nom: str = ""


class EvaluationCreate(BaseModel):
    ecue_id: int
    nom: str
    type_evaluation: str = "Devoir"
    coefficient: Optional[int] = None
    note_max: int = 20
    date_evaluation: Optional[date] = None
    session: int = 1

    @model_validator(mode="after")
    def _coefficient_par_defaut(self):
        """Un devoir (CC/TP) compte pour 1, un examen pour 2."""
        if self.coefficient is None:
            self.coefficient = 2 if self.type_evaluation.strip().lower() == "examen" else 1
        return self


class GenerationEvaluations(BaseModel):
    semestre_id: int
    niveau_id: int


class EvaluationUpdate(BaseModel):
    ecue_id: Optional[int] = None
    nom: Optional[str] = None
    type_evaluation: Optional[str] = None
    coefficient: Optional[int] = None
    note_max: Optional[int] = None
    date_evaluation: Optional[date] = None
    session: Optional[int] = None

    @model_validator(mode="after")
    def _coefficient_par_defaut(self):
        if self.coefficient is None and self.type_evaluation is not None:
            self.coefficient = 2 if self.type_evaluation.strip().lower() == "examen" else 1
        return self


class EvaluationOut(ORMModel):
    id: int
    ecue_id: int
    semestre_id: int
    nom: str
    type_evaluation: str
    coefficient: int
    note_max: int
    date_evaluation: Optional[date] = None
    session: int
    ecue_code: str = ""
    ecue_nom: str = ""
    ue_code: str = ""
    nb_notes: int = 0


class NoteSaisie(BaseModel):
    inscription_id: int
    valeur: Optional[float] = None
    absent: bool = False
    commentaire: str = ""


class NoteMasse(BaseModel):
    evaluation_id: int
    notes: list[NoteSaisie] = []


class ParametresNotes(BaseModel):
    compensation_ecue: Optional[bool] = None
    compensation_inter_ue: Optional[bool] = None
    ponderation_ecue: Optional[bool] = None
    coefficient_devoir: Optional[float] = None
    coefficient_examen: Optional[float] = None
    session2_mode: Optional[str] = None


class SignataireNote(BaseModel):
    prenom_nom: str = ""
    grade: str = ""
    fonction: str = ""


class SignatairesNotes(BaseModel):
    releve: SignataireNote = Field(default_factory=SignataireNote)
    pv: SignataireNote = Field(default_factory=SignataireNote)
    attestation: SignataireNote = Field(default_factory=SignataireNote)


class PresenceLigne(BaseModel):
    inscription_id: int
    present: bool = True
    commentaire: str = ""


class PresencesMasse(BaseModel):
    seance_id: int
    presences: list[PresenceLigne] = []


class PresenceOut(ORMModel):
    id: int
    seance_id: int
    inscription_id: int
    present: bool
    commentaire: str
    etudiant_nom: str = ""
    matricule: str = ""
    groupe_nom: str = ""


class NoteOut(ORMModel):
    id: int
    inscription_id: int
    evaluation_id: int
    valeur: Optional[float] = None
    absent: bool
    commentaire: str
    sur_20: Optional[float] = None


class ResultatOut(ORMModel):
    id: int
    inscription_id: int
    semestre_id: int
    session: int
    moyenne: float
    credits_obtenus: int
    credits_total: int
    points_jury: float = 0.0
    statut: str
    decision: str
    mention: str
    verrouille: bool
    etudiant_nom: str = ""
    matricule: str = ""
    niveau_nom: str = ""
    filiere_nom: str = ""
    groupe_nom: str = ""
    annee: str = ""
    detail: str = ""


class PointJuryLigne(BaseModel):
    inscription_id: int
    points: Optional[float] = None


class PointsJuryUEMasse(BaseModel):
    ue_id: int
    points: list[PointJuryLigne] = []


class PointsJuryECUEMasse(BaseModel):
    ecue_id: int
    points: list[PointJuryLigne] = []


class DeliberationCreate(BaseModel):
    resultat_id: int
    decision: str
    commentaire: str = ""
    jury: str = ""
    points_jury: Optional[float] = None


class DeliberationOut(ORMModel):
    id: int
    resultat_id: int
    decision: str
    commentaire: str
    jury: str
    date_decision: datetime
