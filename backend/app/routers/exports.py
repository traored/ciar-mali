"""Exports PDF et export CSV des heures."""
import csv
from io import BytesIO, StringIO

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Utilisateur
from ..pdf_export import generer_pdf_emploi, generer_pdf_heures
from ..security import utilisateur_courant

router = APIRouter(prefix="/api/export", tags=["exports"])


@router.get("/emploi-du-temps")
def export_emploi(
    type_cible: str = Query("groupe", alias="type"),
    cible_id: int | None = Query(None),
    semestre_id: int = Query(...),
    semaine: int = Query(1),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(utilisateur_courant),
):
    if type_cible != "global" and cible_id is None:
        raise HTTPException(422, "Le paramètre cible_id est requis pour ce type d'export")
    try:
        tampon, nom = generer_pdf_emploi(db, semestre_id, semaine, type_cible, cible_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/heures")
def export_heures(
    semestre_id: int = Query(...),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(utilisateur_courant),
):
    try:
        tampon, nom = generer_pdf_heures(db, semestre_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/heures.csv")
def export_heures_csv(
    semestre_id: int = Query(...),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(utilisateur_courant),
):
    from ..routers.heures import rapport_heures

    donnees = rapport_heures(semestre_id=semestre_id, enseignant_id=None, db=db, utilisateur=_)
    sortie = StringIO()
    sortie.write("\ufeff")
    writer = csv.writer(sortie, delimiter=";")
    writer.writerow(
        ["Enseignant", "Département", "Heures max", "Heures planifiées", "Heures effectuées", "Reste à faire", "Taux (%)"]
    )
    for ligne in donnees["lignes"]:
        writer.writerow(
            [
                ligne["nom"],
                ligne["departement"],
                ligne["heures_max"],
                str(ligne["planifiees"]).replace(".", ","),
                str(ligne["effectuees"]).replace(".", ","),
                str(ligne["reste_a_faire"]).replace(".", ","),
                str(ligne["taux"]).replace(".", ","),
            ]
        )
    contenu = sortie.getvalue().encode("utf-8")
    return StreamingResponse(
        BytesIO(contenu),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="heures_enseignants.csv"'},
    )
