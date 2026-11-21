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


def _description_export_heures(
    donnees: dict,
    *,
    semestre_numero: int | None,
    parite: str | None,
    extension: str,
) -> tuple[str, str]:
    """Libellé et nom de fichier d'un export d'heures.

    Le libellé et le nom suivent la période réellement calculée par
    :func:`app.routers.heures.rapport_heures`, afin que le fichier exporté
    corresponde toujours aux volumes affichés à l'écran.
    """
    from ..routers.heures import libelle_periode

    periode = (parite or "").strip().lower()
    annee_cible = donnees.get("annee") or ""
    if semestre_numero is not None:
        return (
            libelle_periode(annee_cible, numero=semestre_numero),
            f"heures_enseignants_{annee_cible}_semestre_{semestre_numero}.{extension}",
        )
    if periode in ("impairs", "pairs"):
        return (
            libelle_periode(annee_cible, parite=periode),
            f"heures_enseignants_{annee_cible}_{periode}.{extension}",
        )
    semestre = donnees.get("semestre") or {}
    libelle = " · ".join(
        str(valeur) for valeur in (semestre.get("nom"), semestre.get("annee")) if valeur
    ) or "Heures enseignants"
    identifiant = semestre.get("id")
    nom = (
        f"heures_enseignants_{identifiant}.{extension}"
        if identifiant
        else f"heures_enseignants.{extension}"
    )
    return libelle, nom


def _rapport_heures_export(
    db: Session,
    utilisateur: Utilisateur,
    *,
    semestre_id: int | None,
    semestre_numero: int | None,
    annee: str | None,
    parite: str | None,
) -> dict:
    """Rapport d'heures calculé exactement comme la page « Heures »."""
    from ..routers.heures import rapport_heures

    return rapport_heures(
        semestre_id=semestre_id,
        semestre_numero=semestre_numero,
        enseignant_id=None,
        annee=annee,
        parite=parite,
        db=db,
        utilisateur=utilisateur,
    )


@router.get("/heures")
def export_heures(
    semestre_id: int | None = Query(None),
    semestre_numero: int | None = Query(None, ge=1, le=10),
    annee: str | None = Query(None),
    parite: str | None = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    donnees = _rapport_heures_export(
        db,
        utilisateur,
        semestre_id=semestre_id,
        semestre_numero=semestre_numero,
        annee=annee,
        parite=parite,
    )
    libelle, nom = _description_export_heures(
        donnees,
        semestre_numero=semestre_numero,
        parite=parite,
        extension="pdf",
    )
    tampon, nom = generer_pdf_heures(
        lignes=donnees["lignes"],
        libelle=libelle,
        nom_fichier=nom,
    )
    return StreamingResponse(
        tampon,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


@router.get("/heures.csv")
def export_heures_csv(
    semestre_id: int | None = Query(None),
    semestre_numero: int | None = Query(None, ge=1, le=10),
    annee: str | None = Query(None),
    parite: str | None = Query(None),
    db: Session = Depends(get_db),
    utilisateur: Utilisateur = Depends(utilisateur_courant),
):
    donnees = _rapport_heures_export(
        db,
        utilisateur,
        semestre_id=semestre_id,
        semestre_numero=semestre_numero,
        annee=annee,
        parite=parite,
    )
    sortie = StringIO()
    sortie.write("\ufeff")
    writer = csv.writer(sortie, delimiter=";")
    writer.writerow(
        [
            "Enseignant",
            "Département",
            "Heures max",
            "Heures planifiées",
            "Heures effectuées",
            "Reste à faire",
            "Taux (%)",
        ]
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
    totaux = donnees.get("totaux") or {}
    if donnees["lignes"]:
        writer.writerow(
            [
                "Total",
                "",
                "",
                str(totaux.get("planifiees", 0)).replace(".", ","),
                str(totaux.get("effectuees", 0)).replace(".", ","),
                str(totaux.get("reste_a_faire", 0)).replace(".", ","),
                str(totaux.get("taux", 0)).replace(".", ","),
            ]
        )
    contenu = sortie.getvalue().encode("utf-8")
    _, nom = _description_export_heures(
        donnees,
        semestre_numero=semestre_numero,
        parite=parite,
        extension="csv",
    )
    return StreamingResponse(
        BytesIO(contenu),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )
