"""Réinitialise le mot de passe d'un compte (administrateur par défaut).

Utilisation, depuis le dossier `backend` :

    python -m app.reset_admin
    python -m app.reset_admin der der246
    python -m app.reset_admin daouda daouda246 --role admin

Sans argument, le compte `admin` retrouve le mot de passe `admin123`.
Le compte est créé s'il n'existe pas.
"""

import argparse

from .database import SessionLocal
from .models import Utilisateur
from .security import hacher_mot_de_passe


def reinitialiser_admin(
    identifiant: str = "admin",
    mot_de_passe: str = "admin123",
    role: str = "admin",
) -> None:
    db = SessionLocal()
    try:
        utilisateur = (
            db.query(Utilisateur)
            .filter(Utilisateur.identifiant == identifiant)
            .first()
        )

        if utilisateur:
            utilisateur.mot_de_passe_hash = hacher_mot_de_passe(mot_de_passe)
            utilisateur.role = role
            utilisateur.actif = True
            print(f"Compte « {identifiant} » réinitialisé (rôle {role}).")
        else:
            utilisateur = Utilisateur(
                identifiant=identifiant,
                mot_de_passe_hash=hacher_mot_de_passe(mot_de_passe),
                nom_complet=identifiant,
                role=role,
                actif=True,
            )
            db.add(utilisateur)
            print(f"Compte « {identifiant} » créé (rôle {role}).")

        db.commit()
        print("Opération terminée avec succès.")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    analyseur = argparse.ArgumentParser(
        description="Réinitialise le mot de passe d'un compte."
    )
    analyseur.add_argument("identifiant", nargs="?", default="admin")
    analyseur.add_argument("mot_de_passe", nargs="?", default="admin123")
    analyseur.add_argument("--role", default="admin")
    options = analyseur.parse_args()
    reinitialiser_admin(options.identifiant, options.mot_de_passe, options.role)
