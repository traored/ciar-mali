"""Crée les semestres manquants de l'année universitaire 2026-2027.

Le relevé annuel regroupe les deux semestres d'une année d'inscription. Or la
base ne contenait que les semestres impairs (1, 3 et 5) de 2026-2027 : les
semestres 2 et 4 n'existaient pas, si bien qu'une inscription en MPSI 2 ne
pouvait afficher que « Semestre 3 ».

Utilisation (depuis le dossier backend) :

    python creer_semestres_manquants.py             # simulation, aucune écriture
    python creer_semestres_manquants.py --appliquer # crée les semestres
"""
from __future__ import annotations

import sys
from datetime import date

from app.database import SessionLocal
from app.models import Semestre

MANQUANTS = [
    {
        "nom": "Semestre 2",
        "annee": "2026-2027",
        "date_debut": date(2027, 2, 22),
        "date_fin": date(2027, 6, 26),
        "semaines": 16,
    },
    {
        "nom": "Semestre 4",
        "annee": "2026-2027",
        "date_debut": date(2027, 2, 22),
        "date_fin": date(2027, 6, 26),
        "semaines": 16,
    },
]


def main() -> int:
    appliquer = "--appliquer" in sys.argv
    db = SessionLocal()
    try:
        crees = 0
        for donnees in MANQUANTS:
            existant = (
                db.query(Semestre)
                .filter(
                    Semestre.nom == donnees["nom"],
                    Semestre.annee == donnees["annee"],
                )
                .first()
            )
            if existant is not None:
                print(
                    f"{donnees['nom']} {donnees['annee']} : déjà présent "
                    f"(id {existant.id})."
                )
                continue
            print(
                f"{donnees['nom']} {donnees['annee']} : à créer "
                f"({donnees['date_debut']} → {donnees['date_fin']})."
            )
            crees += 1
            if appliquer:
                db.add(
                    Semestre(
                        nom=donnees["nom"],
                        annee=donnees["annee"],
                        date_debut=donnees["date_debut"],
                        date_fin=donnees["date_fin"],
                        semaines=donnees["semaines"],
                        actif=True,
                    )
                )

        if appliquer and crees:
            db.commit()
            print(f"\n{crees} semestre(s) créé(s).")
        elif appliquer:
            print("\nAucun semestre à créer.")
        else:
            print(
                f"\nSimulation : {crees} semestre(s) à créer. "
                "Relancez avec --appliquer pour les enregistrer."
            )
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
