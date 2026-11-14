"""Répare les CM mutualisés créés avant la règle « tous les groupes ».

Un CM marqué « CM commun » doit être suivi par tous les groupes des niveaux
concernés. Les séances créées avant cette règle ne contiennent parfois qu'un
seul groupe : ce script ajoute les groupes manquants, sans jamais créer de
conflit d'emploi du temps.

Utilisation (depuis le dossier backend) :

    python reparer_cm_mutualises.py             # simulation, aucune écriture
    python reparer_cm_mutualises.py --appliquer # applique les corrections
"""
from __future__ import annotations

import json
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

from app.database import SessionLocal
from app.models import Affectation, Groupe, Seance


def main() -> int:
    appliquer = "--appliquer" in sys.argv
    verbeux = "--verbeux" in sys.argv
    db = SessionLocal()
    try:
        affectations = (
            db.query(Affectation).filter(Affectation.cm_commun.is_(True)).all()
        )
        niveaux_par_cm: dict[tuple[int, int, int], set[int]] = defaultdict(set)
        for affectation in affectations:
            if affectation.groupe and affectation.groupe.niveau_id:
                niveaux_par_cm[
                    (affectation.ecue_id, affectation.enseignant_id, affectation.semestre_id)
                ].add(affectation.groupe.niveau_id)

        groupes_par_niveau: dict[int, list[Groupe]] = defaultdict(list)
        for groupe in db.query(Groupe).all():
            groupes_par_niveau[groupe.niveau_id].append(groupe)

        # Occupation des créneaux par groupe, pour ne pas créer de conflit.
        occupations: dict[tuple[int, int, int], set[int]] = defaultdict(set)
        seances = db.query(Seance).filter(Seance.statut != "annulee").all()
        for seance in seances:
            for groupe in seance.groupes:
                occupations[(groupe.id, seance.semestre_id, seance.semaine)].add(
                    seance.creneau_id
                )

        modifiees = 0
        groupes_ajoutes = 0
        ignores: list[str] = []
        journal: list[dict] = []
        for seance in seances:
            if seance.type_seance != "CM":
                continue
            niveaux = niveaux_par_cm.get(
                (seance.ecue_id, seance.enseignant_id, seance.semestre_id)
            )
            if not niveaux:
                continue
            cibles = {
                groupe.id: groupe
                for niveau in niveaux
                for groupe in groupes_par_niveau.get(niveau, [])
            }
            actuels = {groupe.id for groupe in seance.groupes}
            manquants = [gid for gid in cibles if gid not in actuels]
            ajouts: list[Groupe] = []
            for gid in manquants:
                if seance.creneau_id in occupations.get(
                    (gid, seance.semestre_id, seance.semaine), set()
                ):
                    ignores.append(
                        f"séance {seance.id} ({seance.ecue.code if seance.ecue else '?'}, "
                        f"semaine {seance.semaine}, créneau {seance.creneau_id}) : "
                        f"le groupe {cibles[gid].nom} a déjà cours"
                    )
                    continue
                ajouts.append(cibles[gid])
            if not ajouts:
                continue
            modifiees += 1
            groupes_ajoutes += len(ajouts)
            noms = ", ".join(groupe.nom for groupe in ajouts)
            journal.append(
                {
                    "seance_id": seance.id,
                    "ecue": seance.ecue.code if seance.ecue else None,
                    "semaine": seance.semaine,
                    "creneau_id": seance.creneau_id,
                    "groupes_avant": sorted(actuels),
                    "groupes_ajoutes": [groupe.id for groupe in ajouts],
                }
            )
            if verbeux or len(journal) <= 20:
                print(
                    f"séance {seance.id} · {seance.ecue.code if seance.ecue else '?'} · "
                    f"semaine {seance.semaine} · créneau {seance.creneau_id} : "
                    f"ajout de {noms}"
                )
            if appliquer:
                seance.groupes.extend(ajouts)

        print(
            f"\n{'Application' if appliquer else 'Simulation'} : "
            f"{modifiees} séance(s) à corriger, {groupes_ajoutes} groupe(s) à ajouter."
        )
        if ignores:
            print(f"{len(ignores)} ajout(s) ignoré(s) pour cause de conflit :")
            for message in ignores[:20]:
                print(f"  - {message}")
        journal_path = Path(tempfile.gettempdir()) / "ciar_reparation_cm_mutualises.json"
        journal_path.write_text(
            json.dumps(journal, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"Journal des modifications : {journal_path}")
        if appliquer:
            db.commit()
            print("Corrections enregistrées.")
        else:
            print("Aucune écriture. Relancez avec --appliquer pour corriger.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
