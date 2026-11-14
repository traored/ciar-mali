"""Modèles de données de l'application de gestion des emplois du temps."""
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Table,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from .database import Base

seance_groupes = Table(
    "seance_groupes",
    Base.metadata,
    Column("seance_id", Integer, ForeignKey("seances.id", ondelete="CASCADE"), primary_key=True),
    Column("groupe_id", Integer, ForeignKey("groupes.id", ondelete="CASCADE"), primary_key=True),
)

# Mutualisation : une même UE peut être rattachée à plusieurs niveaux (filières).
ue_niveaux = Table(
    "ue_niveaux",
    Base.metadata,
    Column("ue_id", Integer, ForeignKey("ues.id", ondelete="CASCADE"), primary_key=True),
    Column("niveau_id", Integer, ForeignKey("niveaux.id", ondelete="CASCADE"), primary_key=True),
)


class Utilisateur(Base):
    __tablename__ = "utilisateurs"

    id = Column(Integer, primary_key=True)
    identifiant = Column(String(80), unique=True, nullable=False, index=True)
    mot_de_passe_hash = Column(String(255), nullable=False)
    nom_complet = Column(String(150), nullable=False, default="")
    role = Column(String(30), nullable=False, default="lecteur")
    actif = Column(Boolean, nullable=False, default=True)
    enseignant_id = Column(Integer, ForeignKey("enseignants.id", ondelete="SET NULL"), nullable=True)
    etudiant_id = Column(Integer, ForeignKey("etudiants.id", ondelete="SET NULL"), nullable=True)
    cree_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    enseignant = relationship("Enseignant")
    etudiant = relationship("Etudiant")


class Parametre(Base):
    """Paramètres modifiables de l'espace « Gestion des notes »."""

    __tablename__ = "parametres"

    cle = Column(String(60), primary_key=True)
    valeur = Column(String(255), nullable=False, default="")

    @property
    def actif(self) -> bool:
        return self.valeur not in ("", "0", "false", "False")


class Departement(Base):
    __tablename__ = "departements"

    id = Column(Integer, primary_key=True)
    code = Column(String(20), unique=True, nullable=False)
    nom = Column(String(150), nullable=False)
    chef = Column(String(150), default="")
    email = Column(String(150), default="")

    filieres = relationship("Filiere", back_populates="departement", cascade="all, delete-orphan")
    enseignants = relationship("Enseignant", back_populates="departement")
    ues = relationship("UE", back_populates="departement")


class Filiere(Base):
    __tablename__ = "filieres"

    id = Column(Integer, primary_key=True)
    code = Column(String(20), unique=True, nullable=False)
    nom = Column(String(150), nullable=False)
    departement_id = Column(
        Integer, ForeignKey("departements.id", ondelete="CASCADE"), nullable=False, index=True
    )

    departement = relationship("Departement", back_populates="filieres")
    niveaux = relationship("Niveau", back_populates="filiere", cascade="all, delete-orphan")

    @property
    def departement_nom(self) -> str:
        return self.departement.nom if self.departement else ""


class Niveau(Base):
    __tablename__ = "niveaux"

    id = Column(Integer, primary_key=True)
    nom = Column(String(80), nullable=False)
    ordre = Column(Integer, nullable=False, default=1)
    filiere_id = Column(
        Integer, ForeignKey("filieres.id", ondelete="CASCADE"), nullable=False, index=True
    )

    filiere = relationship("Filiere", back_populates="niveaux")
    groupes = relationship("Groupe", back_populates="niveau", cascade="all, delete-orphan")
    ues = relationship("UE", back_populates="niveau")

    @property
    def filiere_nom(self) -> str:
        return self.filiere.nom if self.filiere else ""

    @property
    def filiere_code(self) -> str:
        return self.filiere.code if self.filiere else ""


class Groupe(Base):
    __tablename__ = "groupes"
    __table_args__ = (UniqueConstraint("niveau_id", "nom", name="uq_groupe_niveau_nom"),)

    id = Column(Integer, primary_key=True)
    nom = Column(String(80), nullable=False)
    effectif = Column(Integer, nullable=False, default=30)
    niveau_id = Column(Integer, ForeignKey("niveaux.id", ondelete="CASCADE"), nullable=False, index=True)

    niveau = relationship("Niveau", back_populates="groupes")
    affectations = relationship("Affectation", back_populates="groupe", cascade="all, delete-orphan")

    @property
    def niveau_nom(self) -> str:
        return self.niveau.nom if self.niveau else ""

    @property
    def filiere_nom(self) -> str:
        return self.niveau.filiere.nom if self.niveau and self.niveau.filiere else ""

    @property
    def filiere_code(self) -> str:
        return self.niveau.filiere.code if self.niveau and self.niveau.filiere else ""


TITRES_GRADE = {
    "Professeur": "Pr",
    "Maître de Conférences": "Dr",
    "Maître Assistant": "Dr",
    "Assistant": "M.",
    "Ingénieur": "Ing.",
    "Master": "M.",
}
GRADES_ENSEIGNANT = tuple(TITRES_GRADE)
STATUTS_ENSEIGNANT = ("Permanent", "Vacataire")


class Enseignant(Base):
    __tablename__ = "enseignants"

    id = Column(Integer, primary_key=True)
    prenom = Column(String(80), nullable=False)
    nom = Column(String(80), nullable=False)
    email = Column(String(150), unique=True, nullable=False)
    telephone = Column(String(40), default="")
    date_naissance = Column(Date, nullable=True)
    lieu_naissance = Column(String(120), default="")
    statut = Column(String(30), nullable=False, default="Permanent")
    matricule = Column(String(40), unique=True, nullable=True, index=True)
    grade = Column(String(60), nullable=False, default="Master")
    departement_id = Column(
        Integer, ForeignKey("departements.id", ondelete="SET NULL"), nullable=True, index=True
    )
    heures_max = Column(Integer, nullable=False, default=192)
    actif = Column(Boolean, nullable=False, default=True)

    departement = relationship("Departement", back_populates="enseignants")
    affectations = relationship("Affectation", back_populates="enseignant", cascade="all, delete-orphan")
    seances = relationship("Seance", back_populates="enseignant", cascade="all, delete-orphan")

    @property
    def nom_complet(self) -> str:
        return f"{self.prenom} {self.nom}"

    @property
    def titre(self) -> str:
        return TITRES_GRADE.get(self.grade, "M.")

    @property
    def nom_affichage(self) -> str:
        return f"{self.titre} {self.nom_complet}".strip()

    @property
    def departement_nom(self) -> str:
        return self.departement.nom if self.departement else ""


class Salle(Base):
    __tablename__ = "salles"

    id = Column(Integer, primary_key=True)
    nom = Column(String(80), unique=True, nullable=False)
    batiment = Column(String(100), default="")
    capacite = Column(Integer, nullable=False, default=40)
    type_salle = Column(String(30), nullable=False, default="Salle TD")

    seances = relationship("Seance", back_populates="salle")


class Creneau(Base):
    __tablename__ = "creneaux"
    __table_args__ = (UniqueConstraint("jour", "debut", name="uq_creneau_jour_debut"),)

    id = Column(Integer, primary_key=True)
    jour = Column(Integer, nullable=False, default=0)  # 0 = lundi ... 5 = samedi
    debut = Column(String(5), nullable=False)
    fin = Column(String(5), nullable=False)
    libelle = Column(String(50), default="")

    seances = relationship("Seance", back_populates="creneau", cascade="all, delete-orphan")

    @property
    def duree(self) -> float:
        try:
            h1, m1 = [int(v) for v in self.debut.split(":")]
            h2, m2 = [int(v) for v in self.fin.split(":")]
            return round(((h2 * 60 + m2) - (h1 * 60 + m1)) / 60, 2)
        except (ValueError, AttributeError):
            return 2.0


class Semestre(Base):
    __tablename__ = "semestres"

    id = Column(Integer, primary_key=True)
    nom = Column(String(100), nullable=False)
    annee = Column(String(20), nullable=False, default="2025-2026")
    date_debut = Column(Date, nullable=False, default=date.today)
    date_fin = Column(Date, nullable=False, default=date.today)
    semaines = Column(Integer, nullable=False, default=12)
    actif = Column(Boolean, nullable=False, default=True)

    ues = relationship("UE", back_populates="semestre", cascade="all, delete-orphan")
    seances = relationship("Seance", back_populates="semestre", cascade="all, delete-orphan")


class UE(Base):
    __tablename__ = "ues"
    __table_args__ = (UniqueConstraint("code", "semestre_id", name="uq_ue_code_semestre"),)

    id = Column(Integer, primary_key=True)
    code = Column(String(30), nullable=False)
    nom = Column(String(180), nullable=False)
    credits = Column(Integer, nullable=False, default=6)
    points_jury = Column(Float, nullable=False, default=0.0)
    semestre_id = Column(
        Integer, ForeignKey("semestres.id", ondelete="CASCADE"), nullable=False, index=True
    )
    niveau_id = Column(Integer, ForeignKey("niveaux.id", ondelete="CASCADE"), nullable=False, index=True)
    departement_id = Column(
        Integer, ForeignKey("departements.id", ondelete="SET NULL"), nullable=True, index=True
    )

    semestre = relationship("Semestre", back_populates="ues")
    niveau = relationship("Niveau", back_populates="ues")
    departement = relationship("Departement", back_populates="ues")
    ecues = relationship("ECUE", back_populates="ue", cascade="all, delete-orphan")
    niveaux = relationship(
        "Niveau", secondary=ue_niveaux, backref="ues_mutualisees"
    )

    @property
    def niveau_ids(self) -> list[int]:
        """Niveaux rattachés, le niveau principal étant toujours inclus."""
        ids = [self.niveau_id] if self.niveau_id else []
        for niveau in self.niveaux or []:
            if niveau.id not in ids:
                ids.append(niveau.id)
        return ids

    @property
    def niveaux_noms(self) -> list[str]:
        resultat = []
        for niveau in [self.niveau, *(self.niveaux or [])]:
            if niveau is None:
                continue
            nom = (
                f"{niveau.nom} · {niveau.filiere.code}"
                if niveau.filiere
                else niveau.nom
            )
            if nom not in resultat:
                resultat.append(nom)
        return resultat

    @property
    def semestre_nom(self) -> str:
        return self.semestre.nom if self.semestre else ""

    @property
    def niveau_nom(self) -> str:
        if not self.niveau:
            return ""
        return f"{self.niveau.nom} - {self.niveau.filiere.code}" if self.niveau.filiere else self.niveau.nom

    @property
    def departement_nom(self) -> str:
        return self.departement.nom if self.departement else ""


class ECUE(Base):
    __tablename__ = "ecues"
    __table_args__ = (
        UniqueConstraint("code", "semestre_id", name="uq_ecue_code_semestre"),
    )

    id = Column(Integer, primary_key=True)
    code = Column(String(30), nullable=False)
    nom = Column(String(180), nullable=False)
    credits = Column(Integer, nullable=False, default=1)
    points_jury = Column(Float, nullable=False, default=0.0)
    ue_id = Column(Integer, ForeignKey("ues.id", ondelete="CASCADE"), nullable=False, index=True)
    semestre_id = Column(
        Integer, ForeignKey("semestres.id", ondelete="SET NULL"), nullable=True, index=True
    )
    heures_cm = Column(Integer, nullable=False, default=0)
    heures_td = Column(Integer, nullable=False, default=0)
    heures_tp = Column(Integer, nullable=False, default=0)

    ue = relationship("UE", back_populates="ecues")
    semestre = relationship("Semestre")
    affectations = relationship("Affectation", back_populates="ecue", cascade="all, delete-orphan")
    seances = relationship("Seance", back_populates="ecue", cascade="all, delete-orphan")

    @property
    def ue_code(self) -> str:
        return self.ue.code if self.ue else ""

    @property
    def ue_nom(self) -> str:
        return self.ue.nom if self.ue else ""

    @property
    def total_heures(self) -> int:
        return (self.heures_cm or 0) + (self.heures_td or 0) + (self.heures_tp or 0)

    @property
    def niveau_id(self):
        return self.ue.niveau_id if self.ue else None

    @property
    def niveau_nom(self) -> str:
        return self.ue.niveau_nom if self.ue else ""

    @property
    def semestre_nom(self) -> str:
        return self.semestre.nom if self.semestre else ""

    @property
    def annee(self) -> str:
        return self.semestre.annee if self.semestre else ""


class Affectation(Base):
    __tablename__ = "affectations"
    __table_args__ = (
        UniqueConstraint("enseignant_id", "ecue_id", "groupe_id", name="uq_affectation"),
    )

    id = Column(Integer, primary_key=True)
    semestre_id = Column(
        Integer, ForeignKey("semestres.id", ondelete="CASCADE"), nullable=False, index=True
    )
    enseignant_id = Column(
        Integer, ForeignKey("enseignants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ecue_id = Column(Integer, ForeignKey("ecues.id", ondelete="CASCADE"), nullable=False, index=True)
    groupe_id = Column(Integer, ForeignKey("groupes.id", ondelete="CASCADE"), nullable=False, index=True)
    heures_cm = Column(Integer, nullable=False, default=0)
    heures_td = Column(Integer, nullable=False, default=0)
    heures_tp = Column(Integer, nullable=False, default=0)
    cm_commun = Column(Boolean, nullable=False, default=False)

    semestre = relationship("Semestre")
    enseignant = relationship("Enseignant", back_populates="affectations")
    ecue = relationship("ECUE", back_populates="affectations")
    groupe = relationship("Groupe", back_populates="affectations")
    seances = relationship("Seance", back_populates="affectation")

    @property
    def semestre_nom(self) -> str:
        return self.semestre.nom if self.semestre else ""

    @property
    def annee(self) -> str:
        return self.semestre.annee if self.semestre else ""

    @property
    def enseignant_nom(self) -> str:
        return self.enseignant.nom_affichage if self.enseignant else ""

    @property
    def ecue_code(self) -> str:
        return self.ecue.code if self.ecue else ""

    @property
    def ecue_nom(self) -> str:
        return self.ecue.nom if self.ecue else ""

    @property
    def groupe_nom(self) -> str:
        return self.groupe.nom if self.groupe else ""

    @property
    def total_heures(self) -> int:
        return (self.heures_cm or 0) + (self.heures_td or 0) + (self.heures_tp or 0)


class Seance(Base):
    __tablename__ = "seances"

    id = Column(Integer, primary_key=True)
    semestre_id = Column(
        Integer, ForeignKey("semestres.id", ondelete="CASCADE"), nullable=False, index=True
    )
    semaine = Column(Integer, nullable=False, default=1, index=True)
    creneau_id = Column(
        Integer, ForeignKey("creneaux.id", ondelete="CASCADE"), nullable=False, index=True
    )
    salle_id = Column(Integer, ForeignKey("salles.id", ondelete="SET NULL"), nullable=True, index=True)
    enseignant_id = Column(
        Integer, ForeignKey("enseignants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ecue_id = Column(Integer, ForeignKey("ecues.id", ondelete="CASCADE"), nullable=False, index=True)
    affectation_id = Column(
        Integer, ForeignKey("affectations.id", ondelete="SET NULL"), nullable=True, index=True
    )
    type_seance = Column(String(10), nullable=False, default="CM")
    statut = Column(String(20), nullable=False, default="planifiee")
    verrouillee = Column(Boolean, nullable=False, default=False)
    notes = Column(Text, default="")
    cree_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    semestre = relationship("Semestre", back_populates="seances")
    creneau = relationship("Creneau", back_populates="seances")
    salle = relationship("Salle", back_populates="seances")
    enseignant = relationship("Enseignant", back_populates="seances")
    ecue = relationship("ECUE", back_populates="seances")
    affectation = relationship("Affectation", back_populates="seances")
    groupes = relationship("Groupe", secondary=seance_groupes, lazy="selectin")

    @property
    def duree(self) -> float:
        return self.creneau.duree if self.creneau else 2.0

    @property
    def groupes_noms(self) -> str:
        return ", ".join(g.nom for g in self.groupes)

    @property
    def groupe_ids(self) -> list[int]:
        return [g.id for g in self.groupes]

    presences = relationship(
        "Presence", back_populates="seance", cascade="all, delete-orphan"
    )

    @property
    def salle_nom(self) -> str:
        return self.salle.nom if self.salle else ""

    @property
    def enseignant_nom(self) -> str:
        return self.enseignant.nom_affichage if self.enseignant else ""

    @property
    def ecue_code(self) -> str:
        return self.ecue.code if self.ecue else ""

    @property
    def ecue_nom(self) -> str:
        return self.ecue.nom if self.ecue else ""

    @property
    def niveau_nom(self) -> str:
        """Niveau(x) concerné(s) par la séance, d'après ses groupes.

        Un CM mutualisé peut viser plusieurs groupes d'un même niveau : le
        niveau n'est alors affiché qu'une fois. À défaut de groupe, on retombe
        sur le niveau de l'UE de l'ECUE.
        """
        noms: list[str] = []
        for groupe in self.groupes:
            niveau = groupe.niveau
            if niveau is None:
                continue
            nom = (
                f"{niveau.nom} - {niveau.filiere.code}"
                if niveau.filiere
                else niveau.nom
            )
            if nom not in noms:
                noms.append(nom)
        if noms:
            return ", ".join(noms)
        return self.ecue.niveau_nom if self.ecue else ""

    @property
    def creneau_jour(self) -> int:
        return self.creneau.jour if self.creneau else 0

    @property
    def creneau_debut(self) -> str:
        return self.creneau.debut if self.creneau else ""

    @property
    def creneau_fin(self) -> str:
        return self.creneau.fin if self.creneau else ""


# =================================================================== Gestion des notes
TYPES_EVALUATION = ("Devoir", "TP", "CC", "Examen")
STATUTS_INSCRIPTION = ("Inscrit", "Redoublant", "Rattrapage", "Diplômé", "Abandon")
MENTIONS = (
    (18, "Excellent"),
    (16, "Très bien"),
    (14, "Bien"),
    (12, "Assez bien"),
    (10, "Passable"),
    (0, "Insuffisant"),
)


class Etudiant(Base):
    __tablename__ = "etudiants"

    id = Column(Integer, primary_key=True)
    matricule = Column(String(40), unique=True, nullable=False, index=True)
    prenom = Column(String(80), nullable=False)
    nom = Column(String(80), nullable=False)
    sexe = Column(String(10), nullable=False, default="")
    date_naissance = Column(Date, nullable=True)
    lieu_naissance = Column(String(120), default="")
    telephone = Column(String(40), default="")
    email = Column(String(150), default="")
    filiere_id = Column(
        Integer, ForeignKey("filieres.id", ondelete="SET NULL"), nullable=True, index=True
    )
    cree_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    filiere = relationship("Filiere")
    inscriptions = relationship(
        "Inscription", back_populates="etudiant", cascade="all, delete-orphan"
    )

    @property
    def nom_complet(self) -> str:
        return f"{self.prenom} {self.nom}".strip()

    @property
    def filiere_nom(self) -> str:
        return self.filiere.nom if self.filiere else ""

    @property
    def filiere_code(self) -> str:
        return self.filiere.code if self.filiere else ""

    @property
    def nb_inscriptions(self) -> int:
        return len(self.inscriptions or [])


class Inscription(Base):
    __tablename__ = "inscriptions"
    __table_args__ = (
        UniqueConstraint("etudiant_id", "annee", "niveau_id", name="uq_inscription_parcours"),
    )

    id = Column(Integer, primary_key=True)
    etudiant_id = Column(
        Integer, ForeignKey("etudiants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    annee = Column(String(20), nullable=False, default="2025-2026")
    niveau_id = Column(
        Integer, ForeignKey("niveaux.id", ondelete="CASCADE"), nullable=False, index=True
    )
    groupe_id = Column(
        Integer, ForeignKey("groupes.id", ondelete="SET NULL"), nullable=True, index=True
    )
    statut = Column(String(30), nullable=False, default="Inscrit")
    date_inscription = Column(Date, nullable=False, default=date.today)

    etudiant = relationship("Etudiant", back_populates="inscriptions")
    niveau = relationship("Niveau")
    groupe = relationship("Groupe")
    notes = relationship("Note", back_populates="inscription", cascade="all, delete-orphan")
    resultats = relationship(
        "ResultatSemestre", back_populates="inscription", cascade="all, delete-orphan"
    )

    @property
    def etudiant_nom(self) -> str:
        return self.etudiant.nom_complet if self.etudiant else ""

    @property
    def matricule(self) -> str:
        return self.etudiant.matricule if self.etudiant else ""

    @property
    def niveau_nom(self) -> str:
        return self.niveau.nom if self.niveau else ""

    @property
    def filiere_nom(self) -> str:
        return self.niveau.filiere.nom if self.niveau and self.niveau.filiere else ""

    @property
    def filiere_code(self) -> str:
        return self.niveau.filiere.code if self.niveau and self.niveau.filiere else ""

    @property
    def groupe_nom(self) -> str:
        return self.groupe.nom if self.groupe else ""


class Evaluation(Base):
    __tablename__ = "evaluations"

    id = Column(Integer, primary_key=True)
    ecue_id = Column(
        Integer, ForeignKey("ecues.id", ondelete="CASCADE"), nullable=False, index=True
    )
    semestre_id = Column(
        Integer, ForeignKey("semestres.id", ondelete="CASCADE"), nullable=False, index=True
    )
    nom = Column(String(150), nullable=False)
    type_evaluation = Column(String(30), nullable=False, default="Devoir")
    coefficient = Column(Integer, nullable=False, default=1)
    note_max = Column(Integer, nullable=False, default=20)
    date_evaluation = Column(Date, nullable=True)
    session = Column(Integer, nullable=False, default=1)
    cree_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    ecue = relationship("ECUE")
    semestre = relationship("Semestre")
    notes = relationship("Note", back_populates="evaluation", cascade="all, delete-orphan")

    @property
    def ecue_code(self) -> str:
        return self.ecue.code if self.ecue else ""

    @property
    def ecue_nom(self) -> str:
        return self.ecue.nom if self.ecue else ""

    @property
    def ue_code(self) -> str:
        return self.ecue.ue.code if self.ecue and self.ecue.ue else ""

    @property
    def nb_notes(self) -> int:
        return len(self.notes or [])


class Note(Base):
    __tablename__ = "notes"
    __table_args__ = (
        UniqueConstraint("inscription_id", "evaluation_id", name="uq_note_evaluation"),
    )

    id = Column(Integer, primary_key=True)
    inscription_id = Column(
        Integer, ForeignKey("inscriptions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    evaluation_id = Column(
        Integer, ForeignKey("evaluations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    valeur = Column(Float, nullable=True)
    absent = Column(Boolean, nullable=False, default=False)
    commentaire = Column(String(250), default="")
    maj_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    inscription = relationship("Inscription", back_populates="notes")
    evaluation = relationship("Evaluation", back_populates="notes")

    @property
    def sur_20(self):
        if self.valeur is None:
            return None
        note_max = (self.evaluation.note_max if self.evaluation else 20) or 20
        return round(self.valeur / note_max * 20, 2)


class PointJuryUE(Base):
    """Points complémentaires accordés par le jury à un étudiant pour une UE."""

    __tablename__ = "points_jury_ue"
    __table_args__ = (
        UniqueConstraint("inscription_id", "ue_id", name="uq_point_jury_ue"),
    )

    id = Column(Integer, primary_key=True)
    inscription_id = Column(
        Integer, ForeignKey("inscriptions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ue_id = Column(
        Integer, ForeignKey("ues.id", ondelete="CASCADE"), nullable=False, index=True
    )
    points = Column(Float, nullable=False, default=0.0)
    maj_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    inscription = relationship("Inscription")
    ue = relationship("UE")


class PointJuryECUE(Base):
    """Points complémentaires accordés par le jury à un étudiant pour une ECUE."""

    __tablename__ = "points_jury_ecue"
    __table_args__ = (
        UniqueConstraint("inscription_id", "ecue_id", name="uq_point_jury_ecue"),
    )

    id = Column(Integer, primary_key=True)
    inscription_id = Column(
        Integer, ForeignKey("inscriptions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ecue_id = Column(
        Integer, ForeignKey("ecues.id", ondelete="CASCADE"), nullable=False, index=True
    )
    points = Column(Float, nullable=False, default=0.0)
    maj_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    inscription = relationship("Inscription")
    ecue = relationship("ECUE")


class Presence(Base):
    """Présence d'un étudiant à une séance (feuille de présence)."""

    __tablename__ = "presences"
    __table_args__ = (
        UniqueConstraint("seance_id", "inscription_id", name="uq_presence_seance_inscription"),
    )

    id = Column(Integer, primary_key=True)
    seance_id = Column(
        Integer, ForeignKey("seances.id", ondelete="CASCADE"), nullable=False, index=True
    )
    inscription_id = Column(
        Integer, ForeignKey("inscriptions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    present = Column(Boolean, nullable=False, default=True)
    commentaire = Column(String(250), default="")
    maj_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    seance = relationship("Seance", back_populates="presences")
    inscription = relationship("Inscription")

    @property
    def etudiant_nom(self) -> str:
        return self.inscription.etudiant_nom if self.inscription else ""

    @property
    def matricule(self) -> str:
        return self.inscription.matricule if self.inscription else ""

    @property
    def groupe_nom(self) -> str:
        return self.inscription.groupe_nom if self.inscription else ""


class ResultatSemestre(Base):
    __tablename__ = "resultats_semestre"
    __table_args__ = (
        UniqueConstraint("inscription_id", "semestre_id", "session", name="uq_resultat_session"),
    )

    id = Column(Integer, primary_key=True)
    inscription_id = Column(
        Integer, ForeignKey("inscriptions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    semestre_id = Column(
        Integer, ForeignKey("semestres.id", ondelete="CASCADE"), nullable=False, index=True
    )
    session = Column(Integer, nullable=False, default=1)
    moyenne = Column(Float, nullable=False, default=0)
    credits_obtenus = Column(Integer, nullable=False, default=0)
    credits_total = Column(Integer, nullable=False, default=0)
    points_jury = Column(Float, nullable=False, default=0.0)
    statut = Column(String(40), nullable=False, default="En attente")
    decision = Column(String(40), nullable=False, default="")
    mention = Column(String(40), nullable=False, default="")
    detail = Column(Text, default="")
    verrouille = Column(Boolean, nullable=False, default=False)
    calcule_le = Column(DateTime, default=datetime.utcnow, nullable=False)

    inscription = relationship("Inscription", back_populates="resultats")
    semestre = relationship("Semestre")
    deliberations = relationship(
        "Deliberation", back_populates="resultat", cascade="all, delete-orphan"
    )

    @property
    def etudiant_nom(self) -> str:
        return self.inscription.etudiant_nom if self.inscription else ""

    @property
    def matricule(self) -> str:
        return self.inscription.matricule if self.inscription else ""

    @property
    def niveau_nom(self) -> str:
        return self.inscription.niveau_nom if self.inscription else ""

    @property
    def filiere_nom(self) -> str:
        return self.inscription.filiere_nom if self.inscription else ""

    @property
    def groupe_nom(self) -> str:
        return self.inscription.groupe_nom if self.inscription else ""

    @property
    def annee(self) -> str:
        return self.inscription.annee if self.inscription else ""


class Deliberation(Base):
    __tablename__ = "deliberations"

    id = Column(Integer, primary_key=True)
    resultat_id = Column(
        Integer,
        ForeignKey("resultats_semestre.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    decision = Column(String(40), nullable=False)
    commentaire = Column(Text, default="")
    jury = Column(String(150), default="")
    date_decision = Column(DateTime, default=datetime.utcnow, nullable=False)

    resultat = relationship("ResultatSemestre", back_populates="deliberations")

