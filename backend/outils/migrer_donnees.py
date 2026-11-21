"""Copie les données d'une base source (SQLite/MySQL) vers une base cible.

Utilisation, depuis le dossier ``backend`` :

    python -m outils.migrer_donnees \
        --source "sqlite:///./edt.db" \
        --cible "postgresql+psycopg://user:motdepasse@hote/base?sslmode=require"

Le script crée le schéma sur la cible, copie toutes les tables dans l'ordre des
dépendances puis réaligne les séquences PostgreSQL. Il refuse d'écrire dans une
base cible déjà remplie, sauf avec ``--vider``.
"""
from __future__ import annotations

import argparse
import sys

try:
    from sqlalchemy import create_engine, inspect, select, text
    from sqlalchemy.engine import make_url
except ModuleNotFoundError:  # pragma: no cover - message destiné à l'utilisateur
    from pathlib import Path

    python_projet = Path(__file__).resolve().parents[2].parent / ".venv" / "Scripts" / "python.exe"
    print(
        "Les dependances Python du projet ne sont pas installees pour cet interpreteur.\n"
        "Utilisez le Python du projet :\n"
        f'  "{python_projet}" -m outils.migrer_donnees ...\n'
        "ou lancez simplement :  powershell -ExecutionPolicy Bypass -File .\\migrer-vers-postgres.ps1",
        file=sys.stderr,
    )
    raise SystemExit(1)

from app import models  # noqa: F401  (enregistre les tables dans Base.metadata)
from app.database import Base


def normaliser(url: str) -> str:
    """Ajoute le pilote explicite aux URL fournies par les hébergeurs."""
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url[len("postgres://") :]
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url[len("postgresql://") :]
    if url.startswith("mysql://"):
        return "mysql+pymysql://" + url[len("mysql://") :]
    return url


def masquer(url: str) -> str:
    """Cache le mot de passe pour les traces console."""
    try:
        propre = make_url(url)
    except Exception:
        return url
    return propre.render_as_string(hide_password=True)


def vider_cible(engine) -> None:
    with engine.begin() as connexion:
        if engine.dialect.name == "postgresql":
            noms = ", ".join(f'"{table.name}"' for table in Base.metadata.sorted_tables)
            connexion.execute(text(f"TRUNCATE {noms} RESTART IDENTITY CASCADE"))
            return
        connexion.execute(text("SET FOREIGN_KEY_CHECKS=0"))
        for table in reversed(Base.metadata.sorted_tables):
            connexion.execute(text(f"DELETE FROM {table.name}"))
        connexion.execute(text("SET FOREIGN_KEY_CHECKS=1"))


def realigner_sequences(engine) -> None:
    """Remet les séquences PostgreSQL au niveau des identifiants copiés."""
    if engine.dialect.name != "postgresql":
        return
    with engine.begin() as connexion:
        for table in Base.metadata.sorted_tables:
            if [colonne.name for colonne in table.primary_key.columns] != ["id"]:
                continue
            connexion.execute(
                text(
                    "SELECT setval("
                    f"pg_get_serial_sequence('{table.name}', 'id'), "
                    f"COALESCE((SELECT MAX(id) FROM \"{table.name}\"), 1), "
                    f"(SELECT MAX(id) FROM \"{table.name}\") IS NOT NULL)"
                )
            )


def main() -> int:
    analyseur = argparse.ArgumentParser(description=__doc__)
    analyseur.add_argument("--source", required=True, help="URL SQLAlchemy de la base source")
    analyseur.add_argument("--cible", required=True, help="URL SQLAlchemy de la base cible")
    analyseur.add_argument("--vider", action="store_true", help="Vide la base cible avant la copie")
    options = analyseur.parse_args()

    url_source = normaliser(options.source)
    url_cible = normaliser(options.cible)
    if url_source == url_cible:
        print("La source et la cible sont identiques.", file=sys.stderr)
        return 2

    source = create_engine(url_source, pool_pre_ping=True)
    cible = create_engine(url_cible, pool_pre_ping=True)

    print(f"Source : {masquer(url_source)}")
    print(f"Cible  : {masquer(url_cible)}")

    Base.metadata.create_all(bind=cible)

    if options.vider:
        print("Suppression des données existantes sur la cible…")
        vider_cible(cible)
    else:
        inspecteur = inspect(cible)
        tables_existantes = set(inspecteur.get_table_names())
        for table in Base.metadata.sorted_tables:
            if table.name not in tables_existantes:
                continue
            with cible.connect() as connexion:
                if connexion.execute(select(table).limit(1)).first() is not None:
                    print(
                        f"La table « {table.name} » contient déjà des données. "
                        "Relancez avec --vider pour remplacer le contenu.",
                        file=sys.stderr,
                    )
                    return 3

    total = 0
    for table in Base.metadata.sorted_tables:
        with source.connect() as connexion:
            lignes = [dict(ligne) for ligne in connexion.execute(select(table)).mappings()]
        if lignes:
            with cible.begin() as connexion:
                connexion.execute(table.insert(), lignes)
        total += len(lignes)
        print(f"  {table.name:<24} {len(lignes):>6} ligne(s)")

    realigner_sequences(cible)
    print(f"Terminé : {total} ligne(s) copiée(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
