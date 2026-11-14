# CIAR-Mali — Gestion des emplois du temps universitaires

Application web complète de gestion, de génération et de suivi des emplois du
temps d'une université, avec calcul des heures effectuées par les enseignants.

**Stack : FastAPI + MySQL (ou SQLite par défaut) + Flutter Web** — interface
entièrement en français.

---

## Fonctionnalités

- Gestion des enseignants, départements, filières, niveaux et groupes.
  Fiche enseignant enrichie : matricule facultatif, date et lieu de naissance,
  statut (Permanent / Vacataire) et grade (Professeur, Maître de Conférences,
  Maître Assistant, Assistant, Ingénieur, Master — Master par défaut).
- Titre abrégé du grade affiché devant le nom de l'enseignant dans l'emploi du
  temps et les exports (`Pr`, `Dr`, `M.`, `Ing.`).
- Gestion des UE et ECUE, des affectations enseignant / ECUE / groupe.
- Gestion des CM communs (mutualisation par ECUE et niveau).
- Gestion des salles, créneaux, semaines et semestres.
- Génération automatique des emplois du temps, avec contrôle des conflits
  (enseignant, salle, groupe) et conservation des séances verrouillées.
- Création manuelle de séances, modification, annulation / rétablissement,
  suppression et verrouillage. Les enseignants et groupes proposés sont filtrés
  selon les affectations de l'ECUE sélectionné.
- Séances régulières : création de la même séance sur plusieurs semaines
  consécutives. Chaque semaine reste indépendante (une annulation ou une
  suppression ne touche que la semaine concernée) et les semaines en conflit
  sont ignorées avec un récapitulatif.
- Affichage des périodes de semaine (par exemple « Semaine 1 · du 12 au
  17 octobre 2026 ») dans les séances, l'emploi du temps, le tableau de bord et
  les exports PDF.
- Affichage du code et de l'intitulé de l'ECUE dans les séances et les exports
  (par exemple « 1MTH1121 — Algèbre »).
- Création rapide d'une séance en cliquant sur un créneau vide de la grille de
  l'emploi du temps (semaine, créneau et contexte pré-remplis).
- Suivi des heures planifiées, effectuées et du taux de réalisation par
  enseignant (export PDF et CSV).
- Importation des données depuis Excel (modèle téléchargeable).
- Export PDF des emplois du temps : global, par niveau, par groupe, par salle.
- Authentification JWT et gestion des rôles :
  `admin`, `gestionnaire`, `enseignant`, `lecteur`.

---

## Démarrage rapide (Windows)

1. **Compiler l'interface** (une seule fois, ou après une modification du
   frontend) :

   ```bat
   build_interface.bat
   ```

2. **Lancer l'application** :

   ```bat
   lancer.bat
   ```

   Le serveur démarre sur <http://127.0.0.1:8000> et le navigateur ouvre
   <http://127.0.0.1:8000/app/>. La base SQLite `backend/edt.db` est créée et
   remplie automatiquement au premier lancement avec des données de
   démonstration.

### Comptes

La page de connexion ne préremplit aucun identifiant : chaque utilisateur
saisit son identifiant et son mot de passe. Les comptes de démonstration créés
par `reset_admin` (voir ci-dessous) utilisent les mots de passe fournis au
moment de leur initialisation ; aucun mot de passe n'est stocké dans le dépôt.

> Les données de démonstration contiennent 12 enseignants, 8 groupes,
> 25 affectations et un emploi du temps déjà généré (415 séances / 830 h).

### Réinitialiser un mot de passe

Si un compte ne peut plus se connecter, réinitialisez son mot de passe depuis
le dossier `backend` (la commande écrit dans la base configurée par `.env`) :

```bat
cd backend
python -m app.reset_admin                    :: recrée le compte admin
python -m app.reset_admin der <mot_de_passe> :: compte « der »
python -m app.reset_admin daouda <mot_de_passe> --role admin
```

Le compte est créé s'il n'existe pas. Cette commande est aussi utilisable sur
la base Neon de production.

---

## Démarrage manuel

### Backend

```bat
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

- Documentation interactive de l'API : <http://127.0.0.1:8000/docs>
- Contrôle de santé : <http://127.0.0.1:8000/api/sante>

### Frontend

```bat
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000/api
```

Pour produire la version servie par FastAPI sous `/app/` :

```bat
cd frontend
flutter build web --release --base-href=/app/
```

ou simplement `build_interface.bat` à la racine du projet (le script ajoute un
numéro de version aux fichiers JavaScript pour éviter les anciens caches).

---

## Base de données

Par défaut, l'application utilise **SQLite** (`backend/edt.db`) : aucun serveur
à installer, idéal pour découvrir l'application.

Pour passer à **MySQL** :

1. Créez la base :

   ```sql
   CREATE DATABASE edt_universitaire
     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   ```

2. Copiez `backend/.env.example` en `backend/.env`, puis renseignez :

   ```env
   MYSQL_HOST=localhost
   MYSQL_PORT=3306
   MYSQL_USER=root
   MYSQL_PASSWORD=votre_mot_de_passe
   MYSQL_DATABASE=edt_universitaire
   SECRET_KEY=une-cle-longue-et-aleatoire
   ```

   Il est aussi possible de fournir directement une URL SQLAlchemy :

   ```env
   DATABASE_URL=mysql+pymysql://root:motdepasse@localhost:3306/edt_universitaire?charset=utf8mb4
   ```

3. Redémarrez le serveur. Les tables et les données de démonstration sont
   créées automatiquement si la base est vide.

Pour **réinitialiser** les données SQLite, arrêtez le serveur, supprimez
`backend/edt.db`, puis relancez-le.

---

## Mise en ligne (Render + PostgreSQL)

Le dépôt contient tout ce qu'il faut pour un déploiement Docker sur
[Render.com](https://render.com) (offre gratuite) avec une base PostgreSQL
managée gratuite ([Neon](https://neon.tech)).

### 1. Base PostgreSQL (Neon)

Le projet Neon **`edt-universitaire`** est déjà créé (organisation
`org-bitter-feather-73486569`, région **AWS eu-west-2 / Londres**).
Les 6 388 lignes de la base locale y ont été copiées.

Pour un nouveau projet, créez-le sur [neon.tech](https://neon.tech) puis
récupérez la chaîne de connexion (**Connect** → *Connection string*).

> Utilisez la connexion **directe** (`DATABASE_URL_UNPOOLED`), pas le pooler
> `-pooler` : PgBouncer casse les requêtes préparées de `psycopg`.

Le script suivant copie cette chaîne dans le presse-papiers sans l'afficher :

```powershell
powershell -ExecutionPolicy Bypass -File .\copier-chaine-neon.ps1
```

Les URL `postgres://` et `postgresql://` sont acceptées telles quelles :
l'application ajoute automatiquement le pilote `psycopg`.

### 2. Service Render

Le service **`ciar-mali`** est déployé : <https://ciar-mali.onrender.com>

Il est créé depuis le dépôt **public miroir**
[`traored/ciar-mali`](https://github.com/traored/ciar-mali), qui ne contient
qu'un instantané du code (aucun historique, aucune donnée locale, aucun
secret). Le dépôt privé d'origine reste la référence de travail.

Après chaque modification, publiez le miroir :

```powershell
git add -A
git commit -m "Description du changement"
git push origin main
powershell -ExecutionPolicy Bypass -File .\publier-miroir.ps1
```

Render reconstruit l'image à partir du `Dockerfile` et vérifie `/api/sante`.

> L'offre gratuite de Render met le service en veille après 15 minutes
> d'inactivité : la première requête suivante prend environ 30 à 60 secondes.
> Pour un service toujours actif, passez au plan payant (à partir de 7 $/mois).

### 3. Copier les données existantes

La base Neon est déjà remplie. Pour la rafraîchir depuis la base locale :

```powershell
powershell -ExecutionPolicy Bypass -File .\migrer-vers-postgres.ps1
```

Le script demande la chaîne Neon (ou l'accepte via `-Cible`), utilise le
Python du projet, puis copie les 25 tables dans l'ordre des dépendances et
réaligne les séquences PostgreSQL. Sans `-Conserver`, la base cible est vidée
avant la copie.

Redéployez ensuite le service Render (*Manual Deploy → Deploy latest commit*)
pour qu'il redémarre sur les données migrées.

### 4. Vérifications

```powershell
powershell -ExecutionPolicy Bypass -File .\verifier-en-ligne.ps1 -Url https://ciar-mali.onrender.com
```

Le script contrôle la santé de l'API, la connexion, la liste des diplômables,
le PDF d'attestation et l'interface `/app/`.

```text
GET https://ciar-mali.onrender.com/api/sante          → {"statut": "ok"}
GET https://ciar-mali.onrender.com/app/               → interface de connexion
```

Connectez-vous avec votre identifiant personnel. Si un compte est perdu,
réinitialisez-le avec `python -m app.reset_admin <identifiant> <mot_de_passe>`
depuis le dossier `backend`, puis **changez le mot de passe** (menu
Utilisateurs).

> La clé API Render et la chaîne Neon sont des secrets. Elles ne doivent
> figurer ni dans le dépôt, ni dans un message. En cas de doute, révoquez la
> clé sur <https://dashboard.render.com/u/settings> et regénérez la chaîne
> dans Neon (*Connect*).

### Variables d'environnement

| Variable | Rôle | Valeur en production |
|----------|------|----------------------|
| `DATABASE_URL` | Connexion à la base | chaîne PostgreSQL Neon |
| `SECRET_KEY` | Signature des jetons JWT | valeur aléatoire longue (générée par `render.yaml`) |
| `TOKEN_EXPIRATION_MINUTES` | Durée d'une session | `480` |
| `CORS_ORIGINS` | Origines autorisées | l'URL publique du service |

### Mettre à jour l'interface

L'interface compilée (`frontend/build/web`) est versionnée pour que l'hébergeur
n'ait pas besoin du SDK Flutter. Après une modification du code Flutter :

```powershell
cd frontend
flutter build web --release --base-href /app/
cd ..
git add frontend/build/web
git commit -m "Interface : nouvelle version"
git push
```

Render redéploie automatiquement à chaque `push` sur `main`.

### Sauvegardes

La base PostgreSQL se sauvegarde depuis le tableau de bord Neon
(*Restore / Backups*). Pour une copie locale :

```powershell
python -m outils.migrer_donnees `
  --source "postgresql://...neon.tech/neondb?sslmode=require" `
  --cible "sqlite:///./sauvegarde.db" --vider
```

---

## API principale

| Méthode | Chemin | Description |
|---------|--------|-------------|
| `POST` | `/api/auth/connexion` | Connexion et obtention du jeton JWT |
| `GET`  | `/api/auth/moi` | Profil de l'utilisateur connecté |
| `POST` | `/api/auth/mot-de-passe` | Changement de mot de passe |
| `GET`  | `/api/tableau-de-bord` | Indicateurs et alertes |
| `POST` | `/api/generer` | Génération automatique de l'emploi du temps |
| `GET/POST/PUT/DELETE` | `/api/seances` | Gestion des séances |
| `POST` | `/api/seances/reguliere` | Création d'une séance répétée sur plusieurs semaines |
| `POST` | `/api/seances/{id}/verrouiller` | Verrouillage / déverrouillage |
| `POST` | `/api/seances/{id}/statut` | Changement de statut (planifiée, effectuée…) |
| `GET`  | `/api/heures` | Heures par enseignant |
| `GET`  | `/api/export/emploi-du-temps` | Export PDF (global, niveau, groupe, salle, enseignant) |
| `GET`  | `/api/export/heures` | Export PDF des heures |
| `GET`  | `/api/export/heures.csv` | Export CSV des heures |
| `GET`  | `/api/importer/modele` | Modèle Excel d'importation |
| `POST` | `/api/importer/excel` | Import d'un fichier Excel |
| `GET/POST/PUT/DELETE` | `/api/{departements,filieres,niveaux,groupes,enseignants,salles,creneaux,semestres,ues,ecues,affectations,utilisateurs}` | Référentiels et comptes |

Les routes d'écriture sont protégées par rôle : `admin` et `gestionnaire` pour
les référentiels, `admin` uniquement pour les utilisateurs.

---

## Structure du projet

```
edt-universitaire/
├── backend/
│   ├── app/
│   │   ├── main.py            # Application FastAPI et service de /app
│   │   ├── config.py          # SQLite / MySQL, sécurité, CORS
│   │   ├── models.py          # Modèles SQLAlchemy
│   │   ├── schemas.py         # Schémas Pydantic
│   │   ├── security.py        # JWT, PBKDF2, permissions
│   │   ├── scheduler.py       # Génération et détection de conflits
│   │   ├── seed.py            # Données de démonstration
│   │   ├── pdf_export.py      # Exports PDF (ReportLab)
│   │   └── routers/           # Auth, CRUD, séances, heures, imports…
│   ├── requirements.txt
│   ├── outils/
│   │   └── migrer_donnees.py  # Copie SQLite/MySQL → PostgreSQL
│   └── .env.example
├── frontend/
│   ├── lib/
│   │   ├── api/               # Client HTTP et gestion du jeton
│   │   ├── crud/              # Configurations et page CRUD générique
│   │   ├── pages/             # Connexion, tableau de bord, emploi du temps…
│   │   ├── state/             # État global (Provider)
│   │   └── widgets/           # Composants d'interface réutilisables
│   ├── test/                  # Tests (formats, navigation mobile)
│   └── build_web.ps1          # Build web versionné
├── build_interface.bat
├── lancer.bat
├── Dockerfile               # Image de production (API + interface compilée)
├── render.yaml              # Blueprint Render.com
└── README.md
```

---

## Notes techniques

- L'interface web est servie par le même serveur que l'API : le client utilise
  automatiquement `/api` sur l'origine courante. Cela évite les problèmes de
  CORS et fonctionne aussi bien avec `localhost` qu'avec une adresse réseau.
- Le jeton JWT est conservé dans le stockage local du navigateur.
- Les séances verrouillées ne sont jamais supprimées lors d'une nouvelle
  génération.
- Une séance marquée « effectuée » ne peut plus être modifiée ni supprimée :
  il faut d'abord la repasser en « planifiée » (ou l'annuler / rétablir).
- Le générateur place en priorité les CM communs une seule fois pour tous les
  groupes d'un même niveau, puis répartit TD et TP en évitant les conflits.
- Une séance régulière est matérialisée par une ligne indépendante pour chaque
  semaine : les annulations et suppressions restent donc strictement
  hebdomadaires, sans table supplémentaire.
- Les exports PDF rappellent la période de la semaine et se terminent par la
  signature du responsable du département concerné.
- Les exports PDF et CSV sont générés côté serveur ; l'interface les télécharge
  directement.
