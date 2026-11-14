"""Calcul des volumes horaires CM/TD/TP déclarés par les affectations."""
from typing import Iterable

from .models import Affectation


def volumes_declares(affectations: Iterable[Affectation]) -> dict[str, float]:
    """Volumes CM, TD et TP d'un ensemble d'affectations d'un même ECUE.

    Les heures portées par une affectation sont celles dues à l'enseignant
    pour un groupe donné. Un CM mutualisé (``cm_commun``) est en revanche
    dispensé une seule fois par niveau : lorsque l'enseignant a plusieurs
    groupes du même niveau, son volume de CM ne doit pas être multiplié par
    le nombre de groupes. Les TD et TP restent, eux, propres à chaque groupe.
    """
    cm = 0.0
    td = 0.0
    tp = 0.0
    cm_communs: dict[int, float] = {}

    for affectation in affectations:
        heures_cm = float(affectation.heures_cm or 0)
        heures_td = float(affectation.heures_td or 0)
        heures_tp = float(affectation.heures_tp or 0)
        if heures_cm + heures_td + heures_tp == 0 and affectation.ecue:
            # Affectation non renseignée : on retombe sur le volume de l'ECUE.
            heures_cm = float(affectation.ecue.heures_cm or 0)
            heures_td = float(affectation.ecue.heures_td or 0)
            heures_tp = float(affectation.ecue.heures_tp or 0)

        td += heures_td
        tp += heures_tp
        if affectation.cm_commun:
            niveau_id = affectation.groupe.niveau_id if affectation.groupe else 0
            cm_communs[niveau_id] = max(cm_communs.get(niveau_id, 0.0), heures_cm)
        else:
            cm += heures_cm

    cm += sum(cm_communs.values())
    return {"cm": round(cm, 1), "td": round(td, 1), "tp": round(tp, 1)}
