"""Jeu de données de démonstration."""
from datetime import date

from sqlalchemy.orm import Session

from .database import Base, SessionLocal, engine
from .models import (
    Affectation,
    Creneau,
    Departement,
    ECUE,
    Enseignant,
    Etudiant,
    Filiere,
    Groupe,
    Inscription,
    Niveau,
    ResultatSemestre,
    Salle,
    Semestre,
    UE,
    Utilisateur,
)
from .scheduler import generer_planning
from .security import hacher_mot_de_passe

PROFILS_DEMO = {
    "alain.mbarga@univ.cm": ("Professeur", "Permanent", "ENS-001", date(1968, 4, 12), "Yaoundé"),
    "claire.ngo@univ.cm": ("Maître de Conférences", "Permanent", "ENS-002", date(1975, 9, 3), "Douala"),
    "serge.etoundi@univ.cm": ("Maître Assistant", "Permanent", "ENS-003", date(1980, 1, 22), "Bafoussam"),
    "mireille.abena@univ.cm": ("Assistant", "Permanent", "ENS-004", date(1986, 6, 15), "Ebolowa"),
    "pierre.fotso@univ.cm": ("Ingénieur", "Vacataire", None, date(1983, 11, 8), "Buea"),
    "nadege.tchoumi@univ.cm": ("Master", "Vacataire", None, date(1990, 3, 27), "Ngaoundéré"),
    "eric.nkoulou@univ.cm": ("Maître de Conférences", "Permanent", "ENS-007", date(1978, 7, 19), "Bertoua"),
    "sandrine.mballa@univ.cm": ("Maître Assistant", "Permanent", "ENS-008", date(1982, 12, 5), "Kribi"),
    "joseph.kamdem@univ.cm": ("Professeur", "Permanent", "ENS-009", date(1965, 2, 28), "Dschang"),
    "ariane.ewane@univ.cm": ("Master", "Vacataire", None, date(1991, 8, 14), "Garoua"),
    "thomas.nguefack@univ.cm": ("Ingénieur", "Permanent", "ENS-011", date(1979, 10, 30), "Bamenda"),
    "lea.ndongo@univ.cm": ("Assistant", "Vacataire", None, date(1988, 5, 21), "Edéa"),
}


def _etat_schema() -> dict:
    """Photographie du schéma (tables, colonnes, index).

    Sur PostgreSQL, une seule requête remplace les dizaines d'allers-retours
    de l'inspection SQLAlchemy : sur Neon, chaque aller-retour coûte ~200 ms.
    """
    from sqlalchemy import inspect, text

    if engine.dialect.name != "postgresql":
        inspecteur = inspect(engine)
        tables = set(inspecteur.get_table_names())
        return {
            "tables": tables,
            "colonnes": {t: {c["name"] for c in inspecteur.get_columns(t)} for t in tables},
            "index": {t: {i["name"] for i in inspecteur.get_indexes(t)} for t in tables},
        }

    with engine.connect() as connexion:
        lignes = connexion.execute(
            text(
                "SELECT 'table' AS genre, table_name AS objet, NULL AS detail "
                "FROM information_schema.tables WHERE table_schema = 'public' "
                "UNION ALL "
                "SELECT 'colonne', table_name, column_name "
                "FROM information_schema.columns WHERE table_schema = 'public' "
                "UNION ALL "
                "SELECT 'index', tablename, indexname "
                "FROM pg_indexes WHERE schemaname = 'public'"
            )
        ).all()

    tables, colonnes, index = set(), {}, {}
    for genre, objet, detail in lignes:
        if genre == "table":
            tables.add(objet)
        elif genre == "colonne":
            colonnes.setdefault(objet, set()).add(detail)
        else:
            index.setdefault(objet, set()).add(detail)
    return {"tables": tables, "colonnes": colonnes, "index": index}


def initialiser_base():
    etat = _etat_schema()

    # Sur une base deja migree, create_all couterait une vingtaine de requetes
    # de reflexion : on ne le lance que si le schema n'existe pas encore.
    if "utilisateurs" not in etat["tables"]:
        Base.metadata.create_all(bind=engine)
        etat = _etat_schema()
    _migrer_colonnes_enseignants(etat)
    _migrer_colonnes_ecues(etat)
    _migrer_colonnes_notes(etat)
    _migrer_colonnes_utilisateurs(etat)
    _migrer_colonnes_affectations(etat)
    _migrer_unicite_ecues()
    db = SessionLocal()
    try:
        presence = _presence_donnees(db)
        if presence["utilisateurs"] == 0:
            _creer_donnees(db)
        _creer_donnees_notes(db, presence["etudiants"])
        _creer_exemples_diplomes(db, presence["diplomes"])
        _synchroniser_semestres(db)
        _normaliser_credits_ecues(db)
        _lier_compte_lecteur(db)
    finally:
        db.close()


def _presence_donnees(db: Session) -> dict:
    """Compte en une seule requête les jeux de données dont dépend le seed.

    Les gardes de `_creer_donnees*` coûtaient un aller-retour chacune : sur une
    base distante (Neon), les regrouper économise plusieurs centaines de ms.
    """
    from sqlalchemy import text

    matricules = ", ".join(
        "'" + matricule + "'" for matricule in MATRICULES_DIPLOMES_DEMO.values()
    )
    ligne = db.execute(
        text(
            "SELECT (SELECT COUNT(*) FROM utilisateurs), "
            "(SELECT COUNT(*) FROM etudiants), "
            f"(SELECT COUNT(*) FROM etudiants WHERE matricule IN ({matricules}))"
        )
    ).one()
    return {
        "utilisateurs": ligne[0],
        "etudiants": ligne[1],
        "diplomes": ligne[2],
    }


def _migrer_colonnes_ecues(etat: dict):
    """Ajoute les champs crédits et semestre aux ECUE des bases existantes."""
    from sqlalchemy import text

    if "ecues" not in etat["tables"]:
        return
    existantes = etat["colonnes"].get("ecues", set())
    a_ajouter = [c for c in ("credits", "semestre_id") if c not in existantes]
    if not a_ajouter:
        return
    with engine.begin() as connexion:
        if "credits" in a_ajouter:
            connexion.execute(
                text("ALTER TABLE ecues ADD COLUMN credits INTEGER NOT NULL DEFAULT 1")
            )
        if "semestre_id" in a_ajouter:
            connexion.execute(
                text("ALTER TABLE ecues ADD COLUMN semestre_id INTEGER REFERENCES semestres(id)")
            )
        if "semestre_id" in a_ajouter:
            connexion.execute(
                text(
                    "UPDATE ecues SET semestre_id = ("
                    "SELECT ues.semestre_id FROM ues WHERE ues.id = ecues.ue_id"
                    ") WHERE semestre_id IS NULL"
                )
            )


def _synchroniser_semestres(db: Session):
    """Aligne semestres d'ECUE puis d'affectations, en une transaction."""
    from sqlalchemy import text

    db.execute(
        text(
            "UPDATE ecues SET semestre_id = ("
            "  SELECT ues.semestre_id FROM ues WHERE ues.id = ecues.ue_id"
            ") WHERE semestre_id IS NULL OR semestre_id <> ("
            "  SELECT ues.semestre_id FROM ues WHERE ues.id = ecues.ue_id"
            ")"
        )
    )
    db.execute(
        text(
            "UPDATE affectations SET semestre_id = ("
            "  SELECT ecues.semestre_id FROM ecues WHERE ecues.id = affectations.ecue_id"
            ") WHERE ("
            "  SELECT ecues.semestre_id FROM ecues WHERE ecues.id = affectations.ecue_id"
            ") IS NOT NULL AND ("
            "  affectations.semestre_id IS NULL OR affectations.semestre_id <> ("
            "    SELECT ecues.semestre_id FROM ecues WHERE ecues.id = affectations.ecue_id"
            "  )"
            ")"
        )
    )
    db.commit()


def _migrer_colonnes_affectations(etat: dict):
    """Ajoute le semestre aux affectations des bases existantes et le renseigne."""
    from sqlalchemy import text

    if "affectations" not in etat["tables"]:
        return
    existantes = etat["colonnes"].get("affectations", set())
    index = etat["index"].get("affectations", set())
    manquants = "semestre_id" not in existantes
    if not manquants and "ix_affectations_semestre_id" in index:
        return
    with engine.begin() as connexion:
        if manquants:
            connexion.execute(
                text(
                    "ALTER TABLE affectations ADD COLUMN "
                    "semestre_id INTEGER REFERENCES semestres(id)"
                )
            )
            connexion.execute(
                text(
                    "UPDATE affectations SET semestre_id = ("
                    "SELECT ecues.semestre_id FROM ecues WHERE ecues.id = affectations.ecue_id"
                    ") WHERE semestre_id IS NULL"
                )
            )
        if "ix_affectations_semestre_id" not in index:
            connexion.execute(
                text(
                    "CREATE INDEX ix_affectations_semestre_id "
                    "ON affectations (semestre_id)"
                )
            )


def _migrer_unicite_ecues():
    """Remplace l'unicité globale du code d'ECUE par l'unicité (code, semestre).

    SQLite ne permet pas de supprimer un index d'unicité automatique : la table
    est reconstruite en conservant les identifiants et toutes les données.
    """
    if engine.dialect.name != "sqlite":
        return

    from sqlalchemy import text

    with engine.connect() as connexion:
        definition = connexion.execute(
            text("SELECT sql FROM sqlite_master WHERE type='table' AND name='ecues'")
        ).scalar()
    if not definition:
        return
    compacte = " ".join(definition.split()).lower()
    if (
        "uq_ecue_code_semestre" in compacte
        or "unique (code, semestre_id)" in compacte
        or "unique(code, semestre_id)" in compacte
    ):
        return
    if "unique (code)" not in compacte and "unique(code)" not in compacte:
        return

    colonnes = (
        "id, code, nom, ue_id, heures_cm, heures_td, heures_tp, "
        "credits, points_jury, semestre_id"
    )
    brut = engine.raw_connection()
    try:
        curseur = brut.cursor()
        curseur.execute("PRAGMA foreign_keys=OFF")
        curseur.execute(
            """
            CREATE TABLE ecues_new (
                id INTEGER NOT NULL,
                code VARCHAR(30) NOT NULL,
                nom VARCHAR(180) NOT NULL,
                ue_id INTEGER NOT NULL,
                heures_cm INTEGER NOT NULL,
                heures_td INTEGER NOT NULL,
                heures_tp INTEGER NOT NULL,
                credits INTEGER NOT NULL DEFAULT 1,
                points_jury FLOAT NOT NULL DEFAULT 0,
                semestre_id INTEGER REFERENCES semestres(id),
                PRIMARY KEY (id),
                CONSTRAINT uq_ecue_code_semestre UNIQUE (code, semestre_id),
                FOREIGN KEY(ue_id) REFERENCES ues (id) ON DELETE CASCADE
            )
            """
        )
        curseur.execute(
            f"INSERT INTO ecues_new ({colonnes}) SELECT {colonnes} FROM ecues"
        )
        curseur.execute("DROP TABLE ecues")
        curseur.execute("ALTER TABLE ecues_new RENAME TO ecues")
        curseur.execute("CREATE INDEX IF NOT EXISTS ix_ecues_ue_id ON ecues (ue_id)")
        curseur.execute(
            "CREATE INDEX IF NOT EXISTS ix_ecues_semestre_id ON ecues (semestre_id)"
        )
        brut.commit()
        curseur.execute("PRAGMA foreign_keys=ON")
        brut.commit()
    except Exception:
        brut.rollback()
        raise
    finally:
        brut.close()


def _migrer_colonnes_notes(etat: dict):
    """Ajoute les points jury aux UE, ECUE et résultats des bases existantes."""
    from sqlalchemy import text

    tables = etat["tables"]
    colonnes = (
        ("ues", "points_jury", "FLOAT NOT NULL DEFAULT 0"),
        ("ecues", "points_jury", "FLOAT NOT NULL DEFAULT 0"),
        ("resultats_semestre", "points_jury", "FLOAT NOT NULL DEFAULT 0"),
    )
    manquantes = [
        (table, colonne, definition)
        for table, colonne, definition in colonnes
        if table in tables and colonne not in etat["colonnes"].get(table, set())
    ]
    if not manquantes:
        return
    with engine.begin() as connexion:
        for table, colonne, definition in manquantes:
            connexion.execute(
                text(f"ALTER TABLE {table} ADD COLUMN {colonne} {definition}")
            )


def _migrer_colonnes_utilisateurs(etat: dict):
    """Ajoute le rattachement à un étudiant pour les comptes « lecteur »."""
    from sqlalchemy import text

    if "utilisateurs" not in etat["tables"]:
        return
    if "etudiant_id" in etat["colonnes"].get("utilisateurs", set()):
        return
    with engine.begin() as connexion:
        connexion.execute(text("ALTER TABLE utilisateurs ADD COLUMN etudiant_id INTEGER"))


def _lier_compte_lecteur(db: Session):
    """Associe le compte de démonstration « lecteur » à un étudiant existant."""
    from .models import Etudiant

    compte = db.query(Utilisateur).filter(Utilisateur.identifiant == "lecteur").first()
    if compte is None or compte.etudiant_id:
        return
    etudiant = db.query(Etudiant).order_by(Etudiant.id).first()
    if etudiant is None:
        return
    compte.etudiant_id = etudiant.id
    if not compte.nom_complet or compte.nom_complet == "Consultation":
        compte.nom_complet = etudiant.nom_complet
    db.commit()


def _normaliser_credits_ecues(db: Session):
    """Garantit que le crédit d'une UE = somme des crédits de ses ECUE.

    Les bases existantes (ECUE à 1 crédit par défaut) sont réparties
    équitablement ; les données déjà cohérentes ne sont pas modifiées.
    """
    from sqlalchemy import text

    incoherentes = db.execute(
        text(
            "SELECT COUNT(*) FROM ues WHERE EXISTS ("
            "  SELECT 1 FROM ecues WHERE ecues.ue_id = ues.id"
            ") AND credits <> COALESCE(("
            "  SELECT SUM(credits) FROM ecues WHERE ecues.ue_id = ues.id"
            "), 0)"
        )
    ).scalar()
    if not incoherentes:
        return

    for ue in db.query(UE).all():
        ecues = sorted(ue.ecues, key=lambda e: e.id)
        if not ecues:
            continue
        cible = ue.credits or 0
        total = sum((ecue.credits or 0) for ecue in ecues)
        if total == cible or cible <= 0:
            continue
        base, reste = divmod(cible, len(ecues))
        for index, ecue in enumerate(ecues):
            ecue.credits = base + (1 if index < reste else 0)
        ue.credits = cible
    db.commit()


def _migrer_colonnes_enseignants(etat: dict):
    """Ajoute les nouveaux champs aux bases existantes (SQLite et MySQL)."""
    from sqlalchemy import text

    if "enseignants" not in etat["tables"]:
        return
    existantes = etat["colonnes"].get("enseignants", set())
    colonnes = {
        "date_naissance": "DATE",
        "lieu_naissance": "VARCHAR(120) DEFAULT ''",
        "statut": "VARCHAR(30) NOT NULL DEFAULT 'Permanent'",
        "matricule": "VARCHAR(40)",
        "grade": "VARCHAR(60) NOT NULL DEFAULT 'Master'",
    }
    ajoutees = [nom for nom in colonnes if nom not in existantes]
    if not ajoutees:
        return
    index = etat["index"].get("enseignants", set())
    with engine.begin() as connexion:
        for nom in ajoutees:
            connexion.execute(text(f"ALTER TABLE enseignants ADD COLUMN {nom} {colonnes[nom]}"))
        if "matricule" in ajoutees and "ix_enseignants_matricule" not in index:
            connexion.execute(
                text("CREATE UNIQUE INDEX ix_enseignants_matricule ON enseignants (matricule)")
            )

    # Complète les profils de démonstration sans toucher aux autres enseignants.
    db = SessionLocal()
    try:
        for email, (grade, statut, matricule, naissance, lieu) in PROFILS_DEMO.items():
            enseignant = db.query(Enseignant).filter(Enseignant.email == email).first()
            if enseignant and enseignant.grade == "Master":
                enseignant.grade = grade
                enseignant.statut = statut
                enseignant.matricule = matricule
                enseignant.date_naissance = naissance
                enseignant.lieu_naissance = lieu
        db.commit()
    finally:
        db.close()


def _creer_donnees(db: Session):
    # ---------------------------------------------------------- Départements
    info = Departement(code="INFO", nom="Informatique", chef="Pr. Alain Mbarga", email="info@univ.cm")
    math = Departement(code="MATH", nom="Mathématiques", chef="Pr. Claire Ngo", email="math@univ.cm")
    phys = Departement(code="PHYS", nom="Physique", chef="Pr. Serge Etoundi", email="phys@univ.cm")
    lang = Departement(code="LANG", nom="Langues et Communication", chef="Dr. Mireille Abena", email="lang@univ.cm")
    db.add_all([info, math, phys, lang])
    db.flush()

    # ---------------------------------------------------------- Filières / niveaux / groupes
    gl = Filiere(code="GL", nom="Génie Logiciel", departement_id=info.id)
    res = Filiere(code="RES", nom="Réseaux et Télécommunications", departement_id=info.id)
    ma = Filiere(code="MA", nom="Mathématiques Appliquées", departement_id=math.id)
    phy = Filiere(code="PHY", nom="Sciences Physiques", departement_id=phys.id)
    db.add_all([gl, res, ma, phy])
    db.flush()

    niveaux = {}
    for filiere, noms in [
        (gl, [("Licence 1", 1), ("Licence 2", 2), ("Licence 3", 3)]),
        (res, [("Licence 1", 1), ("Licence 2", 2)]),
        (ma, [("Licence 1", 1)]),
        (phy, [("Licence 1", 1)]),
    ]:
        for nom, ordre in noms:
            niveau = Niveau(nom=nom, ordre=ordre, filiere_id=filiere.id)
            db.add(niveau)
            db.flush()
            niveaux[(filiere.code, nom)] = niveau

    groupes = {}
    for (code_filiere, nom_niveau), noms_groupes in {
        ("GL", "Licence 1"): [("GL-L1-A", 42), ("GL-L1-B", 38)],
        ("GL", "Licence 2"): [("GL-L2-A", 35)],
        ("GL", "Licence 3"): [("GL-L3-A", 28)],
        ("RES", "Licence 1"): [("RES-L1-A", 32)],
        ("RES", "Licence 2"): [("RES-L2-A", 26)],
        ("MA", "Licence 1"): [("MA-L1-A", 30)],
        ("PHY", "Licence 1"): [("PHY-L1-A", 24)],
    }.items():
        niveau = niveaux[(code_filiere, nom_niveau)]
        for nom, effectif in noms_groupes:
            groupe = Groupe(nom=nom, effectif=effectif, niveau_id=niveau.id)
            db.add(groupe)
            db.flush()
            groupes[nom] = groupe

    # ---------------------------------------------------------- Enseignants
    enseignants_data = [
        ("Alain", "Mbarga", "alain.mbarga@univ.cm", info.id, 192),
        ("Claire", "Ngo Bassong", "claire.ngo@univ.cm", math.id, 192),
        ("Serge", "Etoundi", "serge.etoundi@univ.cm", phys.id, 180),
        ("Mireille", "Abena", "mireille.abena@univ.cm", lang.id, 160),
        ("Pierre", "Fotso", "pierre.fotso@univ.cm", info.id, 192),
        ("Nadège", "Tchoumi", "nadege.tchoumi@univ.cm", info.id, 192),
        ("Éric", "Nkoulou", "eric.nkoulou@univ.cm", info.id, 180),
        ("Sandrine", "Mballa", "sandrine.mballa@univ.cm", math.id, 192),
        ("Joseph", "Kamdem", "joseph.kamdem@univ.cm", info.id, 180),
        ("Ariane", "Ewane", "ariane.ewane@univ.cm", lang.id, 160),
        ("Thomas", "Nguefack", "thomas.nguefack@univ.cm", phys.id, 192),
        ("Léa", "Ndongo", "lea.ndongo@univ.cm", info.id, 192),
    ]
    enseignants = []
    for prenom, nom, email, dep_id, maxi in enseignants_data:
        grade, statut, matricule, naissance, lieu = PROFILS_DEMO.get(
            email, ("Master", "Permanent", None, None, "")
        )
        enseignant = Enseignant(
            prenom=prenom,
            nom=nom,
            email=email,
            telephone="+237 6 90 00 00 00",
            date_naissance=naissance,
            lieu_naissance=lieu,
            statut=statut,
            matricule=matricule,
            grade=grade,
            departement_id=dep_id,
            heures_max=maxi,
            actif=True,
        )
        db.add(enseignant)
        db.flush()
        enseignants.append(enseignant)

    # ---------------------------------------------------------- Salles
    salles_data = [
        ("Amphi A", "Bâtiment central", 220, "Amphi"),
        ("Amphi B", "Bâtiment central", 160, "Amphi"),
        ("Salle 101", "Bâtiment A", 45, "Salle TD"),
        ("Salle 102", "Bâtiment A", 45, "Salle TD"),
        ("Salle 201", "Bâtiment B", 35, "Salle TD"),
        ("Labo Info 1", "Bâtiment C", 32, "Labo"),
        ("Labo Info 2", "Bâtiment C", 30, "Labo"),
        ("Labo Réseaux", "Bâtiment C", 28, "Labo"),
    ]
    for nom, batiment, capacite, type_salle in salles_data:
        db.add(Salle(nom=nom, batiment=batiment, capacite=capacite, type_salle=type_salle))
    db.flush()

    # ---------------------------------------------------------- Créneaux
    horaires = [
        ("08:00", "10:00"),
        ("10:15", "12:15"),
        ("13:00", "15:00"),
        ("15:15", "17:15"),
    ]
    for jour in range(5):
        for debut, fin in horaires:
            db.add(Creneau(jour=jour, debut=debut, fin=fin, libelle=f"{debut} - {fin}"))
    for debut, fin in horaires[:2]:
        db.add(Creneau(jour=5, debut=debut, fin=fin, libelle=f"{debut} - {fin}"))
    db.flush()

    # ---------------------------------------------------------- Semestres
    semestre1 = Semestre(
        nom="Semestre 1",
        annee="2025-2026",
        date_debut=date(2025, 9, 29),
        date_fin=date(2025, 12, 19),
        semaines=12,
        actif=True,
    )
    semestre2 = Semestre(
        nom="Semestre 2",
        annee="2025-2026",
        date_debut=date(2026, 1, 12),
        date_fin=date(2026, 4, 3),
        semaines=12,
        actif=False,
    )
    db.add_all([semestre1, semestre2])
    db.flush()

    # ---------------------------------------------------------- UE / ECUE / affectations
    programme = [
        # (filière, niveau, code UE, nom UE, crédits, [(code ECUE, nom, CM, TD, TP, enseignant, groupes, cm_commun)])
        ("GL", "Licence 1", "UE-INF101", "Fondements de la programmation", 8, [
            ("INF1011", "Algorithmique fondamentale", 20, 20, 10, 0, True),
            ("INF1012", "Programmation en Python", 10, 15, 15, 4, False),
        ]),
        ("GL", "Licence 1", "UE-INF102", "Développement web", 6, [
            ("INF1021", "HTML, CSS et JavaScript", 10, 15, 15, 5, False),
        ]),
        ("GL", "Licence 1", "UE-MAT101", "Mathématiques pour l'informatique", 6, [
            ("MAT1011", "Mathématiques discrètes", 20, 20, 0, 1, True),
        ]),
        ("GL", "Licence 2", "UE-INF201", "Bases de données", 8, [
            ("INF2011", "Modélisation et SQL", 20, 15, 15, 4, False),
            ("INF2012", "Administration de bases de données", 10, 10, 10, 6, False),
        ]),
        ("GL", "Licence 2", "UE-INF202", "Génie logiciel", 6, [
            ("INF2021", "Méthodes de conception", 15, 15, 0, 0, False),
            ("INF2022", "Tests et qualité logicielle", 10, 10, 10, 9, False),
        ]),
        ("GL", "Licence 2", "UE-INF203", "Réseaux informatiques", 6, [
            ("INF2031", "Architecture réseau", 15, 10, 10, 6, False),
        ]),
        ("GL", "Licence 3", "UE-INF301", "Intelligence artificielle", 8, [
            ("INF3011", "Apprentissage automatique", 20, 15, 10, 5, False),
            ("INF3012", "Traitement du langage naturel", 10, 10, 10, 11, False),
        ]),
        ("GL", "Licence 3", "UE-INF302", "Sécurité informatique", 6, [
            ("INF3021", "Cryptographie appliquée", 15, 15, 0, 2, False),
            ("INF3022", "Sécurité des systèmes", 10, 10, 10, 6, False),
        ]),
        ("RES", "Licence 1", "UE-RES101", "Introduction aux réseaux", 8, [
            ("RES1011", "Modèles et protocoles", 20, 15, 10, 8, False),
            ("RES1012", "Câblage et commutation", 10, 10, 15, 6, False),
        ]),
        ("RES", "Licence 2", "UE-RES201", "Administration des systèmes", 8, [
            ("RES2011", "Systèmes Linux", 15, 10, 20, 8, False),
            ("RES2012", "Services réseau", 10, 15, 15, 9, False),
        ]),
        ("MA", "Licence 1", "UE-MAT110", "Analyse et algèbre", 10, [
            ("MAT1101", "Analyse réelle", 25, 25, 0, 1, True),
            ("MAT1102", "Algèbre linéaire", 20, 20, 0, 7, True),
        ]),
        ("PHY", "Licence 1", "UE-PHY101", "Physique générale", 8, [
            ("PHY1011", "Mécanique du point", 20, 15, 10, 2, False),
            ("PHY1012", "Électricité et magnétisme", 15, 15, 10, 10, False),
        ]),
    ]

    index_enseignant = 0
    for code_filiere, nom_niveau, code_ue, nom_ue, credits, ecues in programme:
        niveau = niveaux[(code_filiere, nom_niveau)]
        ue = UE(
            code=code_ue,
            nom=nom_ue,
            credits=credits,
            semestre_id=semestre1.id,
            niveau_id=niveau.id,
            departement_id=niveau.filiere.departement_id,
        )
        db.add(ue)
        db.flush()
        groupes_niveau = [g for g in groupes.values() if g.niveau_id == niveau.id]
        for code_ecue, nom_ecue, cm, td, tp, indice, cm_commun in ecues:
            ecue = ECUE(
                code=code_ecue,
                nom=nom_ecue,
                ue_id=ue.id,
                heures_cm=cm,
                heures_td=td,
                heures_tp=tp,
            )
            db.add(ecue)
            db.flush()
            enseignant = enseignants[indice % len(enseignants)]
            for groupe in groupes_niveau:
                db.add(
                    Affectation(
                        semestre_id=ue.semestre_id,
                        enseignant_id=enseignant.id,
                        ecue_id=ecue.id,
                        groupe_id=groupe.id,
                        heures_cm=cm,
                        heures_td=td,
                        heures_tp=tp,
                        cm_commun=cm_commun,
                    )
                )
            index_enseignant += 1
    db.commit()

    # ---------------------------------------------------------- Utilisateurs
    utilisateurs = [
        Utilisateur(
            identifiant="admin",
            mot_de_passe_hash=hacher_mot_de_passe("admin123"),
            nom_complet="Administrateur",
            role="admin",
            actif=True,
        ),
        Utilisateur(
            identifiant="gestionnaire",
            mot_de_passe_hash=hacher_mot_de_passe("gestion123"),
            nom_complet="Service scolarité",
            role="gestionnaire",
            actif=True,
        ),
        Utilisateur(
            identifiant="prof",
            mot_de_passe_hash=hacher_mot_de_passe("prof123"),
            nom_complet=enseignants[0].nom_complet,
            role="enseignant",
            actif=True,
            enseignant_id=enseignants[0].id,
        ),
        Utilisateur(
            identifiant="lecteur",
            mot_de_passe_hash=hacher_mot_de_passe("lecteur123"),
            nom_complet="Consultation",
            role="lecteur",
            actif=True,
        ),
    ]
    db.add_all(utilisateurs)
    db.commit()

    # ---------------------------------------------------------- Emploi du temps de démonstration
    resultat = generer_planning(db, semestre1.id, remplacer=True)
    print(f"Démo : {resultat['crees']} séances générées.")


def _creer_donnees_notes(db: Session, etudiants: int | None = None):
    """Étudiants, inscriptions, évaluations et notes de démonstration."""
    import random

    from .models import Etudiant, Evaluation, Inscription, Note
    from .notes_service import calculer_semestre

    if etudiants is None:
        etudiants = db.query(Etudiant).count()
    if etudiants > 0:
        return

    semestre = (
        db.query(Semestre).filter(Semestre.actif.is_(True)).order_by(Semestre.id).first()
    ) or db.query(Semestre).order_by(Semestre.id).first()
    if semestre is None:
        return

    prenoms_h = ["Ibrahim", "Moussa", "Cheick", "Amadou", "Souleymane", "Bakary", "Oumar"]
    prenoms_f = ["Aminata", "Fatoumata", "Mariam", "Awa", "Kadidia", "Rokia", "Assitan"]
    noms = ["Traoré", "Diallo", "Coulibaly", "Keïta", "Diarra", "Konaté", "Cissé", "Sidibé"]
    aleatoire = random.Random(2026)

    plan = [
        ("GL", "Licence 1", "GL-L1-A", 7),
        ("GL", "Licence 1", "GL-L1-B", 5),
        ("GL", "Licence 2", "GL-L2-A", 6),
        ("RES", "Licence 1", "RES-L1-A", 5),
    ]

    compteur = 0
    inscriptions = []
    for code_filiere, nom_niveau, nom_groupe, effectif in plan:
        niveau = (
            db.query(Niveau)
            .join(Filiere, Niveau.filiere_id == Filiere.id)
            .filter(Filiere.code == code_filiere, Niveau.nom == nom_niveau)
            .first()
        )
        if niveau is None:
            continue
        groupe = db.query(Groupe).filter(Groupe.nom == nom_groupe).first()
        for _ in range(effectif):
            compteur += 1
            feminin = aleatoire.random() < 0.45
            prenom = aleatoire.choice(prenoms_f if feminin else prenoms_h)
            nom = aleatoire.choice(noms)
            etudiant = Etudiant(
                matricule=f"ETU-2025-{compteur:04d}",
                prenom=prenom,
                nom=nom,
                sexe="F" if feminin else "M",
                date_naissance=date(2003 + aleatoire.randint(0, 3), aleatoire.randint(1, 12), aleatoire.randint(1, 28)),
                lieu_naissance=aleatoire.choice(
                    ["Bamako", "Ségou", "Sikasso", "Mopti", "Kayes", "Gao", "Koutiala"]
                ),
                telephone=f"+223 7{aleatoire.randint(1000000, 9999999)}",
                email=f"{prenom.lower().replace(' ', '')}.{nom.lower().replace(' ', '')}{compteur}@ciar.ml",
                filiere_id=niveau.filiere_id,
            )
            db.add(etudiant)
            db.flush()
            inscription = Inscription(
                etudiant_id=etudiant.id,
                annee=semestre.annee,
                niveau_id=niveau.id,
                groupe_id=groupe.id if groupe else None,
                statut="Inscrit",
                date_inscription=date(2025, 10, aleatoire.randint(1, 20)),
            )
            db.add(inscription)
            db.flush()
            inscriptions.append(inscription)
    db.commit()

    # ---------------------------------------------------------- Évaluations
    evaluations = []
    ues = db.query(UE).filter(UE.semestre_id == semestre.id).order_by(UE.code).all()
    for ue in ues:
        for ecue in db.query(ECUE).filter(ECUE.ue_id == ue.id).order_by(ECUE.code).all():
            for nom, type_evaluation, coefficient in [
                ("Devoir 1", "Devoir", 1),
                ("Travaux pratiques", "TP", 1),
                ("Examen final", "Examen", 2),
            ]:
                if type_evaluation == "TP" and (ecue.heures_tp or 0) == 0:
                    continue
                evaluation = Evaluation(
                    ecue_id=ecue.id,
                    semestre_id=semestre.id,
                    nom=nom,
                    type_evaluation=type_evaluation,
                    coefficient=coefficient,
                    note_max=20,
                    date_evaluation=date(2025, 11, aleatoire.randint(1, 28))
                    if type_evaluation != "Examen final"
                    else date(2025, 12, aleatoire.randint(1, 18)),
                    session=1,
                )
                db.add(evaluation)
                evaluations.append(evaluation)
    db.commit()

    # ---------------------------------------------------------- Notes
    capacites = {
        inscription.id: aleatoire.gauss(10.4, 3.3) for inscription in inscriptions
    }
    for inscription in inscriptions:
        for evaluation in evaluations:
            ecue = db.get(ECUE, evaluation.ecue_id)
            if ecue is None or ecue.ue is None:
                continue
            if ecue.ue.niveau_id != inscription.niveau_id:
                continue
            absent = aleatoire.random() < 0.05
            note_brute = capacites[inscription.id] + aleatoire.gauss(0, 2.4)
            note = Note(
                inscription_id=inscription.id,
                evaluation_id=evaluation.id,
                valeur=None if absent else round(min(20.0, max(0.0, note_brute)), 2),
                absent=absent,
                commentaire="Absence justifiée" if absent else "",
            )
            db.add(note)
    db.commit()

    resultats = calculer_semestre(db, semestre.id, 1)
    print(
        f"Démo notes : {len(inscriptions)} étudiants inscrits, "
        f"{len(evaluations)} évaluations, {len(resultats)} résultats calculés."
    )


# ============================================== Exemples de diplômés (attestations)
MATRICULES_DIPLOMES_DEMO = {
    "licence": "ETU-DIP-LIC-001",
    "master": "ETU-DIP-MAS-001",
    "ingenieur": "ETU-DIP-ING-001",
}


def _filiere_ou_creer(db: Session, code: str, nom: str) -> Filiere:
    """Retourne la filière demandée, en la créant si nécessaire."""
    filiere = db.query(Filiere).filter(Filiere.code == code).first()
    if filiere is not None:
        return filiere
    departement = db.query(Departement).filter(Departement.code == "INFO").first()
    if departement is None:
        departement = db.query(Departement).order_by(Departement.id).first()
    if departement is None:
        departement = Departement(code="INFO", nom="Informatique", chef="", email="")
        db.add(departement)
        db.flush()
    filiere = Filiere(code=code, nom=nom, departement_id=departement.id)
    db.add(filiere)
    db.flush()
    return filiere


def _niveau_ou_creer(
    db: Session, filiere: Filiere, nom: str, ordre: int
) -> Niveau:
    """Retourne le niveau demandé dans une filière, en le créant si nécessaire."""
    niveau = (
        db.query(Niveau)
        .filter(Niveau.filiere_id == filiere.id, Niveau.nom == nom)
        .first()
    )
    if niveau is None:
        niveau = Niveau(nom=nom, ordre=ordre, filiere_id=filiere.id)
        db.add(niveau)
        db.flush()
    return niveau


def _semestre_ou_creer(
    db: Session,
    nom: str,
    annee: str,
    date_debut: date,
    date_fin: date,
) -> Semestre:
    """Retourne le semestre identifié par son nom et son année."""
    semestre = (
        db.query(Semestre)
        .filter(Semestre.nom == nom, Semestre.annee == annee)
        .first()
    )
    if semestre is None:
        semestre = Semestre(
            nom=nom,
            annee=annee,
            date_debut=date_debut,
            date_fin=date_fin,
            semaines=12,
            actif=False,
        )
        db.add(semestre)
        db.flush()
    return semestre


def _inscription_ou_creer(
    db: Session,
    etudiant: Etudiant,
    annee: str,
    niveau: Niveau,
    statut: str,
    groupe_nom: str | None = None,
) -> Inscription:
    """Retourne l'inscription d'un étudiant pour une année et un niveau."""
    inscription = (
        db.query(Inscription)
        .filter(
            Inscription.etudiant_id == etudiant.id,
            Inscription.annee == annee,
            Inscription.niveau_id == niveau.id,
        )
        .first()
    )
    if inscription is None:
        groupe = (
            db.query(Groupe).filter(Groupe.nom == groupe_nom).first()
            if groupe_nom
            else None
        )
        inscription = Inscription(
            etudiant_id=etudiant.id,
            annee=annee,
            niveau_id=niveau.id,
            groupe_id=groupe.id if groupe else None,
            statut=statut,
            date_inscription=date(int(annee[:4]), 10, 1),
        )
        db.add(inscription)
        db.flush()
    else:
        inscription.statut = statut
    return inscription


def _resultat_valide(
    db: Session, inscription: Inscription, semestre: Semestre, moyenne: float
) -> ResultatSemestre:
    """Crée ou met à jour un résultat de semestre validé."""
    resultat = (
        db.query(ResultatSemestre)
        .filter(
            ResultatSemestre.inscription_id == inscription.id,
            ResultatSemestre.semestre_id == semestre.id,
            ResultatSemestre.session == 1,
        )
        .first()
    )
    if resultat is None:
        resultat = ResultatSemestre(
            inscription_id=inscription.id,
            semestre_id=semestre.id,
            session=1,
        )
        db.add(resultat)
    resultat.moyenne = moyenne
    resultat.credits_obtenus = 60
    resultat.credits_total = 60
    resultat.points_jury = 0.0
    resultat.statut = "Validé"
    resultat.decision = "Admis"
    resultat.mention = "Très bien" if moyenne >= 16 else "Bien" if moyenne >= 14 else "Assez bien"
    resultat.detail = ""
    db.flush()
    return resultat


def _creer_parcours_diplome(
    db: Session,
    etudiant: Etudiant,
    filiere: Filiere,
    etapes: list[tuple],
    moyennes: list[float],
) -> None:
    """Crée les inscriptions et résultats validés d'un parcours complet.

    Chaque étape est un tuple
    ``(nom_niveau, ordre, annee, groupe_nom, semestres)`` où ``semestres``
    contient des tuples ``(nom, annee, date_debut, date_fin)``.
    """
    index = 0
    derniere_etape = len(etapes) - 1
    for position, (nom_niveau, ordre, annee, groupe_nom, semestres) in enumerate(etapes):
        niveau = _niveau_ou_creer(db, filiere, nom_niveau, ordre)
        inscription = _inscription_ou_creer(
            db,
            etudiant,
            annee,
            niveau,
            statut="Diplômé" if position == derniere_etape else "Inscrit",
            groupe_nom=groupe_nom,
        )
        for nom_semestre, annee_semestre, debut, fin in semestres:
            semestre = _semestre_ou_creer(db, nom_semestre, annee_semestre, debut, fin)
            moyenne = moyennes[index] if index < len(moyennes) else 14.0
            _resultat_valide(db, inscription, semestre, moyenne)
            index += 1


def _creer_exemples_diplomes(db: Session, diplomes: int | None = None):
    """Ajoute des étudiants de démonstration éligibles aux attestations de diplôme.

    Trois parcours complets sont créés, de façon idempotente :
    - Licence : 6 semestres validés (L1, L2, L3) ;
    - Master : 4 semestres validés (M1, M2) ;
    - Grade d'ingénieur : 10 semestres validés (5 années).
    """
    matricules = tuple(MATRICULES_DIPLOMES_DEMO.values())
    if diplomes is None:
        diplomes = (
            db.query(Etudiant).filter(Etudiant.matricule.in_(matricules)).count()
        )
    if diplomes == len(matricules):
        return

    filiere_gl = _filiere_ou_creer(db, "GL", "Génie Logiciel")
    filiere_ia = _filiere_ou_creer(db, "IA", "Intelligence Artificielle")

    parcours = [
        {
            "cle": "licence",
            "prenom": "Aïssata",
            "nom": "Traoré",
            "sexe": "F",
            "naissance": date(2003, 5, 12),
            "lieu": "Bamako",
            "telephone": "+223 76 00 00 01",
            "email": "aissata.traore@ciar.ml",
            "filiere": filiere_gl,
            "etapes": [
                (
                    "Licence 1",
                    1,
                    "2024-2025",
                    "GL-L1-A",
                    [
                        ("Semestre 1", "2024-2025", date(2024, 10, 14), date(2025, 2, 13)),
                        ("Semestre 2", "2024-2025", date(2025, 2, 24), date(2025, 6, 27)),
                    ],
                ),
                (
                    "Licence 2",
                    2,
                    "2025-2026",
                    "GL-L2-A",
                    [
                        ("Semestre 3", "2025-2026", date(2025, 2, 17), date(2025, 6, 28)),
                        ("Semestre 4", "2025-2026", date(2026, 1, 12), date(2026, 6, 20)),
                    ],
                ),
                (
                    "Licence 3",
                    3,
                    "2026-2027",
                    "GL-L3-A",
                    [
                        ("Semestre 5", "2026-2027", date(2026, 10, 12), date(2027, 2, 13)),
                        ("Semestre 6", "2026-2027", date(2027, 2, 22), date(2027, 6, 26)),
                    ],
                ),
            ],
            "moyennes": [13.4, 14.1, 12.8, 13.9, 14.6, 15.2],
        },
        {
            "cle": "master",
            "prenom": "Moussa",
            "nom": "Keïta",
            "sexe": "M",
            "naissance": date(2000, 8, 3),
            "lieu": "Ségou",
            "telephone": "+223 76 00 00 02",
            "email": "moussa.keita@ciar.ml",
            "filiere": filiere_gl,
            "etapes": [
                (
                    "Master 1",
                    4,
                    "2025-2026",
                    None,
                    [
                        (
                            "Master 1 - Semestre 1",
                            "2025-2026",
                            date(2025, 10, 13),
                            date(2026, 2, 14),
                        ),
                        (
                            "Master 1 - Semestre 2",
                            "2025-2026",
                            date(2026, 2, 23),
                            date(2026, 6, 13),
                        ),
                    ],
                ),
                (
                    "Master 2",
                    5,
                    "2026-2027",
                    None,
                    [
                        (
                            "Master 2 - Semestre 1",
                            "2026-2027",
                            date(2026, 10, 12),
                            date(2027, 2, 13),
                        ),
                        (
                            "Master 2 - Semestre 2",
                            "2026-2027",
                            date(2027, 2, 22),
                            date(2027, 6, 26),
                        ),
                    ],
                ),
            ],
            "moyennes": [14.2, 15.0, 15.6, 16.1],
        },
        {
            "cle": "ingenieur",
            "prenom": "Fatoumata",
            "nom": "Diarra",
            "sexe": "F",
            "naissance": date(1999, 11, 21),
            "lieu": "Sikasso",
            "telephone": "+223 76 00 00 03",
            "email": "fatoumata.diarra@ciar.ml",
            "filiere": filiere_ia,
            "etapes": [
                (
                    "1ère année cycle d'ingénieur",
                    3,
                    "2022-2023",
                    None,
                    [
                        (
                            "Ingénieur 1 - Semestre 1",
                            "2022-2023",
                            date(2022, 10, 10),
                            date(2023, 2, 11),
                        ),
                        (
                            "Ingénieur 1 - Semestre 2",
                            "2022-2023",
                            date(2023, 2, 20),
                            date(2023, 6, 24),
                        ),
                    ],
                ),
                (
                    "2e année cycle d'ingénieur",
                    4,
                    "2023-2024",
                    None,
                    [
                        (
                            "Ingénieur 2 - Semestre 1",
                            "2023-2024",
                            date(2023, 10, 9),
                            date(2024, 2, 10),
                        ),
                        (
                            "Ingénieur 2 - Semestre 2",
                            "2023-2024",
                            date(2024, 2, 19),
                            date(2024, 6, 22),
                        ),
                    ],
                ),
                (
                    "3e année cycle d'ingénieur",
                    5,
                    "2024-2025",
                    None,
                    [
                        (
                            "Ingénieur 3 - Semestre 1",
                            "2024-2025",
                            date(2024, 10, 14),
                            date(2025, 2, 13),
                        ),
                        (
                            "Ingénieur 3 - Semestre 2",
                            "2024-2025",
                            date(2025, 2, 24),
                            date(2025, 6, 27),
                        ),
                    ],
                ),
                (
                    "4e année cycle d'ingénieur",
                    6,
                    "2025-2026",
                    None,
                    [
                        (
                            "Ingénieur 4 - Semestre 1",
                            "2025-2026",
                            date(2025, 10, 13),
                            date(2026, 2, 14),
                        ),
                        (
                            "Ingénieur 4 - Semestre 2",
                            "2025-2026",
                            date(2026, 2, 23),
                            date(2026, 6, 13),
                        ),
                    ],
                ),
                (
                    "5e année cycle d'ingénieur",
                    7,
                    "2026-2027",
                    None,
                    [
                        (
                            "Ingénieur 5 - Semestre 1",
                            "2026-2027",
                            date(2026, 10, 12),
                            date(2027, 2, 13),
                        ),
                        (
                            "Ingénieur 5 - Semestre 2",
                            "2026-2027",
                            date(2027, 2, 22),
                            date(2027, 6, 26),
                        ),
                    ],
                ),
            ],
            "moyennes": [12.5, 13.0, 13.4, 13.9, 14.2, 14.5, 14.8, 15.1, 15.4, 15.8],
        },
    ]

    crees = 0
    for donnees in parcours:
        etudiant = (
            db.query(Etudiant)
            .filter(Etudiant.matricule == MATRICULES_DIPLOMES_DEMO[donnees["cle"]])
            .first()
        )
        if etudiant is None:
            etudiant = Etudiant(
                matricule=MATRICULES_DIPLOMES_DEMO[donnees["cle"]],
                prenom=donnees["prenom"],
                nom=donnees["nom"],
                sexe=donnees["sexe"],
                date_naissance=donnees["naissance"],
                lieu_naissance=donnees["lieu"],
                telephone=donnees["telephone"],
                email=donnees["email"],
                filiere_id=donnees["filiere"].id,
            )
            db.add(etudiant)
            db.flush()
            crees += 1
        _creer_parcours_diplome(
            db,
            etudiant,
            donnees["filiere"],
            donnees["etapes"],
            donnees["moyennes"],
        )
    db.commit()
    print(
        "Démo diplômes : 3 étudiants diplômables disponibles "
        f"({crees} créés, {3 - crees} déjà présents)."
    )
