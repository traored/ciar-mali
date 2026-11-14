"""Exports PDF des emplois du temps et des heures enseignants."""
from datetime import datetime, timedelta
from io import BytesIO
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from sqlalchemy.orm import Session

from .models import Creneau, Enseignant, Groupe, Niveau, Salle, Seance, Semestre

BLEU = colors.HexColor("#1e3a8a")
BLEU_CLAIR = colors.HexColor("#e0e7ff")
VERT_CLAIR = colors.HexColor("#dcfce7")
ORANGE_CLAIR = colors.HexColor("#ffedd5")
GRIS = colors.HexColor("#f1f5f9")
GRIS_BORD = colors.HexColor("#cbd5e1")
TYPES_COULEURS = {"CM": BLEU_CLAIR, "TD": VERT_CLAIR, "TP": ORANGE_CLAIR}
JOURS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
MOIS_FR = [
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
]


def _styles():
    base = getSampleStyleSheet()
    return {
        "titre": ParagraphStyle(
            "titre", parent=base["Title"], fontSize=16, textColor=BLEU, spaceAfter=2, alignment=TA_CENTER
        ),
        "sous_titre": ParagraphStyle(
            "sous_titre", parent=base["Normal"], fontSize=10, textColor=colors.HexColor("#475569"),
            alignment=TA_CENTER, spaceAfter=8,
        ),
        "entete": ParagraphStyle(
            "entete", parent=base["Normal"], fontSize=8, textColor=colors.white,
            alignment=TA_CENTER, fontName="Helvetica-Bold",
        ),
        "horaire": ParagraphStyle(
            "horaire", parent=base["Normal"], fontSize=7.5, alignment=TA_CENTER, leading=9
        ),
        "cellule": ParagraphStyle("cellule", parent=base["Normal"], fontSize=6.8, leading=8.2),
        "vide": ParagraphStyle(
            "vide", parent=base["Normal"], fontSize=7, textColor=colors.HexColor("#94a3b8"),
            alignment=TA_CENTER,
        ),
        "signature_titre": ParagraphStyle(
            "signature_titre", parent=base["Normal"], fontSize=7.5,
            textColor=colors.HexColor("#475569"), alignment=TA_RIGHT, leading=9,
        ),
        "signature_nom": ParagraphStyle(
            "signature_nom", parent=base["Normal"], fontSize=9.5, fontName="Helvetica-Bold",
            textColor=colors.HexColor("#0f172a"), alignment=TA_RIGHT, leading=11,
        ),
        "signature_dept": ParagraphStyle(
            "signature_dept", parent=base["Normal"], fontSize=7.5,
            textColor=colors.HexColor("#475569"), alignment=TA_RIGHT, leading=9,
        ),
    }


def _pied_de_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(colors.HexColor("#64748b"))
    canvas.drawString(1.2 * cm, 0.7 * cm, "CIAR-Mali · Gestion des emplois du temps universitaires")
    canvas.drawRightString(landscape(A4)[0] - 1.2 * cm, 0.7 * cm, f"Page {doc.page}")
    canvas.restoreState()


def _periode_semaine(semestre: Semestre, semaine: int) -> str:
    """Période du lundi au samedi correspondant à une semaine du semestre."""
    debut = semestre.date_debut + timedelta(days=(semaine - 1) * 7)
    fin = debut + timedelta(days=5)
    if debut.year == fin.year and debut.month == fin.month:
        return f"du {debut.day} au {fin.day} {MOIS_FR[fin.month - 1]} {fin.year}"
    if debut.year == fin.year:
        return (
            f"du {debut.day} {MOIS_FR[debut.month - 1]} au "
            f"{fin.day} {MOIS_FR[fin.month - 1]} {fin.year}"
        )
    return (
        f"du {debut.day} {MOIS_FR[debut.month - 1]} {debut.year} au "
        f"{fin.day} {MOIS_FR[fin.month - 1]} {fin.year}"
    )


def _departement_groupe(groupe: Groupe | None):
    """Département de rattachement d'un groupe (via sa filière)."""
    if groupe and groupe.niveau and groupe.niveau.filiere:
        return groupe.niveau.filiere.departement
    return None


def _departement_depuis_seances(seances: list[Seance]):
    """Département majoritaire des séances (utilisé pour l'export par salle)."""
    departements: dict[int, object] = {}
    compteurs: dict[int, int] = {}
    for seance in seances:
        departement = None
        if seance.ecue and seance.ecue.ue:
            departement = seance.ecue.ue.departement
        if departement is None and seance.enseignant:
            departement = seance.enseignant.departement
        if departement is not None:
            departements[departement.id] = departement
            compteurs[departement.id] = compteurs.get(departement.id, 0) + 1
    if not compteurs:
        return None
    return departements[max(compteurs, key=compteurs.get)]


def _bloc_signature(departement, styles):
    """Bloc de signature du responsable du département concerné."""
    chef = (departement.chef or "").strip()
    nom_departement = (departement.nom or "").strip()
    lignes = [
        [Paragraph("Le Responsable du département", styles["signature_titre"])],
        [""],
        [Paragraph(escape(chef) if chef else "&nbsp;", styles["signature_nom"])],
    ]
    if nom_departement:
        lignes.append(
            [Paragraph(f"Responsable du département : {escape(nom_departement)}", styles["signature_dept"])]
        )
    bloc = Table(
        lignes,
        colWidths=[8.2 * cm],
        rowHeights=[None, 1.2 * cm] + [None] * (len(lignes) - 2),
    )
    bloc.setStyle(
        TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
                ("VALIGN", (0, 0), (-1, -1), "BOTTOM"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
                ("LINEBELOW", (0, 1), (-1, 1), 0.6, colors.HexColor("#64748b")),
            ]
        )
    )
    bloc.hAlign = "RIGHT"
    return bloc


def _texte_seance(seance: Seance, avec_groupes: bool = True) -> str:
    code = escape(seance.ecue.code if seance.ecue else "?")
    nom_ecue = escape(seance.ecue.nom) if seance.ecue and seance.ecue.nom else ""
    lignes = [f"<b>{code}" + (f" — {nom_ecue}" if nom_ecue else "") + "</b>"]
    infos = [seance.type_seance]
    if seance.salle:
        infos.append(escape(seance.salle.nom))
    lignes.append(" · ".join(infos))
    if seance.enseignant:
        lignes.append(escape(seance.enseignant.nom_affichage))
    if avec_groupes and seance.groupes:
        lignes.append(escape(", ".join(g.nom for g in seance.groupes)))
    return "<br/>".join(lignes)


def _page_emploi(
    db: Session,
    semestre: Semestre,
    semaine: int,
    titre: str,
    seances: list[Seance],
    styles,
    departement=None,
    largeur_utile: float | None = None,
    hauteur_utile: float | None = None,
):
    creneaux = db.query(Creneau).order_by(Creneau.jour, Creneau.debut).all()
    horaires = sorted({(c.debut, c.fin) for c in creneaux})
    if not horaires:
        horaires = [("08:00", "10:00")]

    donnees = [
        [Paragraph("Horaire", styles["entete"])]
        + [Paragraph(jour, styles["entete"]) for jour in JOURS]
    ]
    styles_cellules = []
    for ligne_index, (debut, fin) in enumerate(horaires, start=1):
        ligne = [Paragraph(f"{debut}<br/>{fin}", styles["horaire"])]
        for jour_index, _jour in enumerate(JOURS):
            trouvees = [
                s
                for s in seances
                if s.creneau
                and s.creneau.jour == jour_index
                and s.creneau.debut == debut
            ]
            if trouvees:
                texte = "<br/><br/>".join(_texte_seance(s) for s in trouvees)
                ligne.append(Paragraph(texte, styles["cellule"]))
                couleur = TYPES_COULEURS.get(trouvees[0].type_seance, GRIS)
                styles_cellules.append(("BACKGROUND", (jour_index + 1, ligne_index), (jour_index + 1, ligne_index), couleur))
            else:
                ligne.append(Paragraph("—", styles["vide"]))
        donnees.append(ligne)

    largeur = (landscape(A4)[0] - 2.4 * cm) / 7
    tableau = Table(donnees, colWidths=[2.2 * cm] + [largeur] * 6, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), BLEU),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("GRID", (0, 0), (-1, -1), 0.5, GRIS_BORD),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BACKGROUND", (0, 1), (0, -1), GRIS),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("VALIGN", (0, 0), (0, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]
    style.extend(styles_cellules)
    tableau.setStyle(TableStyle(style))

    elements = [
        Paragraph(titre, styles["titre"]),
        Paragraph(
            f"{escape(semestre.nom)} · {escape(semestre.annee)} · Semaine {semaine} — "
            f"{_periode_semaine(semestre, semaine)}",
            styles["sous_titre"],
        ),
        tableau,
        Spacer(1, 6),
        Paragraph(
            "<b>Légende :</b> CM (bleu) · TD (vert) · TP (orange) — Document généré le "
            + datetime.now().strftime("%d/%m/%Y à %H:%M"),
            ParagraphStyle("legende", fontSize=7, textColor=colors.HexColor("#64748b")),
        ),
    ]
    if departement is None:
        departement = _departement_depuis_seances(seances)
    if departement is not None:
        bloc = _bloc_signature(departement, styles)
        espace = 12.0
        if largeur_utile and hauteur_utile:
            # Pousse la signature vers le bas de la page lorsque la place le permet.
            utilisee = 0.0
            for element in elements:
                _, hauteur = element.wrap(largeur_utile, hauteur_utile)
                utilisee += hauteur + element.getSpaceBefore() + element.getSpaceAfter()
            _, hauteur_bloc = bloc.wrap(largeur_utile, hauteur_utile)
            espace = max(12.0, hauteur_utile - utilisee - hauteur_bloc - 4.0)
        elements.append(Spacer(1, espace))
        elements.append(bloc)
    return elements


def _cibles(db: Session, cible: str, cible_id: int | None):
    if cible == "global":
        groupes = (
            db.query(Groupe)
            .join(Niveau, Groupe.niveau_id == Niveau.id)
            .order_by(Niveau.nom, Groupe.nom)
            .all()
        )
        if not groupes:
            raise ValueError("Aucun groupe à exporter")
        return [
            (
                f"Emploi du temps — {g.nom} ({g.filiere_code} / {g.niveau_nom})",
                Seance.groupes.any(Groupe.id == g.id),
                True,
                _departement_groupe(g),
            )
            for g in groupes
        ]
    if cible_id is None:
        raise ValueError("Identifiant de la cible manquant")
    if cible == "groupe":
        groupe = db.get(Groupe, cible_id)
        if not groupe:
            raise ValueError("Groupe introuvable")
        titre = f"Emploi du temps — {groupe.nom} ({groupe.filiere_code} / {groupe.niveau_nom})"
        return [(titre, Seance.groupes.any(Groupe.id == groupe.id), True, _departement_groupe(groupe))]
    if cible == "enseignant":
        enseignant = db.get(Enseignant, cible_id)
        if not enseignant:
            raise ValueError("Enseignant introuvable")
        return [
            (
                f"Emploi du temps — {enseignant.nom_complet}",
                Seance.enseignant_id == cible_id,
                True,
                enseignant.departement,
            )
        ]
    if cible == "salle":
        salle = db.get(Salle, cible_id)
        if not salle:
            raise ValueError("Salle introuvable")
        return [(f"Emploi du temps — Salle {salle.nom}", Seance.salle_id == cible_id, True, None)]
    if cible == "niveau":
        niveau = db.get(Niveau, cible_id)
        if not niveau:
            raise ValueError("Niveau introuvable")
        departement = niveau.filiere.departement if niveau.filiere else None
        groupes = db.query(Groupe).filter(Groupe.niveau_id == cible_id).order_by(Groupe.nom).all()
        return [
            (
                f"Emploi du temps — {g.nom} ({niveau.nom} / {niveau.filiere_code})",
                Seance.groupes.any(Groupe.id == g.id),
                True,
                departement,
            )
            for g in groupes
        ]
    raise ValueError("Type d'export inconnu")


def generer_pdf_emploi(
    db: Session, semestre_id: int, semaine: int, cible: str, cible_id: int | None = None
) -> tuple[BytesIO, str]:
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise ValueError("Semestre introuvable")
    semaine = max(1, min(semaine, semestre.semaines))
    styles = _styles()
    cibles = _cibles(db, cible, cible_id)

    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=landscape(A4),
        leftMargin=1.2 * cm,
        rightMargin=1.2 * cm,
        topMargin=1.0 * cm,
        bottomMargin=1.1 * cm,
        title="Emploi du temps",
    )
    elements = []
    for index, (titre, filtre, avec_groupes, departement) in enumerate(cibles):
        seances = (
            db.query(Seance)
            .filter(
                Seance.semestre_id == semestre.id,
                Seance.semaine == semaine,
                Seance.statut != "annulee",
            )
            .filter(filtre)
            .all()
        )
        if index:
            elements.append(PageBreak())
        elements.extend(
            _page_emploi(
                db,
                semestre,
                semaine,
                titre,
                seances,
                styles,
                departement,
                doc.width - 12,  # marges internes du cadre ReportLab
                doc.height - 12,
            )
        )

    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    suffixe = cible if cible_id is None else f"{cible}_{cible_id}"
    nom = f"emploi_du_temps_{suffixe}_semaine_{semaine}.pdf"
    return tampon, nom


def generer_pdf_heures(db: Session, semestre_id: int) -> tuple[BytesIO, str]:
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise ValueError("Semestre introuvable")

    # Recalcul direct (sans dépendance FastAPI)
    seances = (
        db.query(Seance)
        .filter(Seance.semestre_id == semestre.id, Seance.statut != "annulee")
        .all()
    )
    par_enseignant: dict[int, list[Seance]] = {}
    for seance in seances:
        par_enseignant.setdefault(seance.enseignant_id, []).append(seance)

    styles = getSampleStyleSheet()
    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=A4,
        leftMargin=1.5 * cm,
        rightMargin=1.5 * cm,
        topMargin=1.4 * cm,
        bottomMargin=1.4 * cm,
        title="Suivi des heures enseignants",
    )
    elements = [
        Paragraph("Suivi des heures enseignants", _styles()["titre"]),
        Paragraph(
            f"{escape(semestre.nom)} · {escape(semestre.annee)} — généré le {datetime.now().strftime('%d/%m/%Y')}",
            _styles()["sous_titre"],
        ),
        Spacer(1, 6),
    ]
    donnees = [["Enseignant", "Département", "Max", "Planifiées", "Effectuées", "Reste", "Taux"]]
    enseignants = db.query(Enseignant).order_by(Enseignant.nom).all()
    for enseignant in enseignants:
        ses = par_enseignant.get(enseignant.id, [])
        planifiees = round(sum(s.duree for s in ses), 1)
        effectuees = round(sum(s.duree for s in ses if s.statut == "effectuee"), 1)
        if not ses:
            continue
        donnees.append(
            [
                enseignant.nom_complet,
                enseignant.departement_nom or "—",
                f"{enseignant.heures_max} h",
                f"{planifiees:g} h",
                f"{effectuees:g} h",
                f"{max(0, planifiees - effectuees):g} h",
                f"{(effectuees / planifiees * 100) if planifiees else 0:.0f} %",
            ]
        )
    tableau = Table(donnees, colWidths=[5 * cm, 4 * cm, 1.8 * cm, 2.2 * cm, 2.2 * cm, 1.8 * cm, 1.6 * cm])
    tableau.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), BLEU),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("GRID", (0, 0), (-1, -1), 0.5, GRIS_BORD),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    elements.append(tableau)
    elements.append(Spacer(1, 8))
    elements.append(
        Paragraph(
            "Les heures planifiées correspondent aux séances non annulées ; les heures effectuées "
            "aux séances marquées « effectuée ».",
            ParagraphStyle("note", fontSize=7.5, textColor=colors.HexColor("#64748b")),
        )
    )
    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    return tampon, f"heures_enseignants_{semestre.id}.pdf"

