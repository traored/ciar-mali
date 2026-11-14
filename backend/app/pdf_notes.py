"""Génération des PDF de notes : relevés, PV de délibération et attestations."""
import re
from datetime import datetime
from io import BytesIO
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_RIGHT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    Image,
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from sqlalchemy.orm import Session

from .models import Etudiant, Inscription, Niveau, Semestre
from .notes_service import libelle_signataire, lire_signataires, resultat_inscription

LOGO_CIAR = Path(__file__).resolve().parent / "assets" / "logo_ciar.png"

BLEU = colors.HexColor("#1e3a8a")
BLEU_CLAIR = colors.HexColor("#e0e7ff")
VERT_CLAIR = colors.HexColor("#dcfce7")
ROUGE_CLAIR = colors.HexColor("#fee2e2")
GRIS = colors.HexColor("#f1f5f9")
GRIS_BORD = colors.HexColor("#94a3b8")
TEXTE = colors.HexColor("#0f172a")
TEXTE_DOUX = colors.HexColor("#334155")

MOIS_FR = (
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
)


def _styles(compact: bool = False):
    base = getSampleStyleSheet()

    def taille(normale: float, reduite: float) -> float:
        return reduite if compact else normale

    return {
        "universite": ParagraphStyle(
            "universite", parent=base["Normal"], fontSize=taille(14, 12.5), textColor=BLEU,
            alignment=TA_CENTER, fontName="Helvetica-Bold", leading=taille(17, 15),
        ),
        "ministere": ParagraphStyle(
            "ministere", parent=base["Normal"], fontSize=taille(8.5, 7.6),
            textColor=TEXTE_DOUX, alignment=TA_CENTER, leading=taille(11, 9.5),
        ),
        "departement": ParagraphStyle(
            "departement", parent=base["Normal"], fontSize=taille(11, 9.8),
            textColor=TEXTE, alignment=TA_CENTER, fontName="Helvetica-Bold",
            leading=taille(14, 12),
        ),
        "titre": ParagraphStyle(
            "titre", parent=base["Title"], fontSize=taille(17, 15), textColor=BLEU,
            alignment=TA_CENTER, spaceBefore=taille(6, 4), spaceAfter=2,
        ),
        "sous_titre": ParagraphStyle(
            "sous_titre", parent=base["Normal"], fontSize=taille(9.5, 8.5),
            textColor=TEXTE_DOUX, alignment=TA_CENTER, spaceAfter=taille(8, 6),
        ),
        "libelle": ParagraphStyle(
            "libelle", parent=base["Normal"], fontSize=taille(9, 8),
            textColor=TEXTE_DOUX, leading=taille(11, 9.5),
        ),
        "date_lieu": ParagraphStyle(
            "date_lieu", parent=base["Normal"], fontSize=taille(9.8, 8.8),
            textColor=TEXTE, alignment=TA_RIGHT, leading=taille(12, 10.5),
        ),
        "valeur": ParagraphStyle(
            "valeur", parent=base["Normal"], fontSize=taille(10.5, 9.2), fontName="Helvetica-Bold",
            textColor=TEXTE, leading=taille(12.5, 10.8),
        ),
        "entete": ParagraphStyle(
            "entete", parent=base["Normal"], fontSize=taille(8.6, 7.6), textColor=colors.white,
            alignment=TA_CENTER, fontName="Helvetica-Bold", leading=taille(10.5, 9.2),
        ),
        "cellule": ParagraphStyle(
            "cellule", parent=base["Normal"], fontSize=taille(8.6, 7.6),
            textColor=TEXTE, leading=taille(10.5, 9.2),
        ),
        "cellule_centre": ParagraphStyle(
            "cellule_centre", parent=base["Normal"], fontSize=taille(8.6, 7.6),
            textColor=TEXTE, leading=taille(10.5, 9.2), alignment=TA_CENTER,
        ),
        "ue": ParagraphStyle(
            "ue", parent=base["Normal"], fontSize=taille(8.8, 7.8), textColor=TEXTE,
            leading=taille(10.6, 9.4), fontName="Helvetica-Bold",
        ),
        "total_libelle": ParagraphStyle(
            "total_libelle", parent=base["Normal"], fontSize=taille(9.5, 8.5),
            fontName="Helvetica-Bold", textColor=TEXTE_DOUX, alignment=TA_CENTER,
            leading=taille(11.5, 10),
        ),
        "total_valeur": ParagraphStyle(
            "total_valeur", parent=base["Normal"], fontSize=taille(11.5, 10.2),
            fontName="Helvetica-Bold", textColor=BLEU, alignment=TA_CENTER,
            leading=taille(13.5, 12),
        ),
        "paragraphe": ParagraphStyle(
            "paragraphe", parent=base["Normal"], fontSize=taille(10, 9.2), leading=taille(15, 13),
            alignment=TA_JUSTIFY, textColor=TEXTE,
        ),
        "section": ParagraphStyle(
            "section", parent=base["Normal"], fontSize=taille(11, 9.8),
            textColor=BLEU, fontName="Helvetica-Bold", spaceBefore=taille(4, 3),
            spaceAfter=taille(5, 4), leading=taille(13.5, 11.8),
        ),
        "signature_titre": ParagraphStyle(
            "signature_titre", parent=base["Normal"], fontSize=taille(8.6, 7.8),
            textColor=TEXTE_DOUX, alignment=TA_RIGHT, leading=taille(10.5, 9.5),
        ),
        "signature_nom": ParagraphStyle(
            "signature_nom", parent=base["Normal"], fontSize=taille(10.5, 9.4),
            fontName="Helvetica-Bold", textColor=TEXTE, alignment=TA_RIGHT,
            leading=taille(12.5, 11),
        ),
        "signature_grade": ParagraphStyle(
            "signature_grade", parent=base["Normal"], fontSize=taille(8.8, 8),
            textColor=TEXTE_DOUX, alignment=TA_RIGHT, leading=taille(10.8, 9.8),
        ),
    }


def _pied_de_page(canvas, doc):
    canvas.saveState()
    largeur = doc.pagesize[0]
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(TEXTE_DOUX)
    canvas.drawString(1.2 * cm, 0.7 * cm, "CIAR-Mali · Gestion des notes universitaires")
    canvas.drawRightString(largeur - 1.2 * cm, 0.7 * cm, f"Page {doc.page}")
    canvas.restoreState()


def _nombre(valeur, decimales: int = 2) -> str:
    if valeur is None:
        return "—"
    texte = f"{float(valeur):.{decimales}f}"
    return texte.replace(".", ",")


def _date_fr(valeur) -> str:
    if not valeur:
        return "—"
    if isinstance(valeur, datetime):
        return valeur.strftime("%d/%m/%Y")
    return valeur.strftime("%d/%m/%Y")


def _date_longue_fr(valeur: datetime) -> str:
    """« 05 novembre 2026 » : date lisible sur un document officiel."""
    return f"{valeur.day:02d} {MOIS_FR[valeur.month - 1]} {valeur.year}"


def _nombre_pages(contenu: bytes) -> int:
    return len(re.findall(rb"/Type\s*/Page[^s]", contenu))


def _entete(
    elements,
    styles,
    titre: str,
    sous_titre: str,
    *,
    avec_ministere: bool = True,
    logo_largeur: float = 3.0,
):
    if LOGO_CIAR.exists():
        largeur = logo_largeur * cm
        hauteur = largeur * 337 / 540  # conserve les proportions du logo 540 × 337
        logo = Image(str(LOGO_CIAR), width=largeur, height=hauteur)
        logo.hAlign = "CENTER"
        elements.append(logo)
    if avec_ministere:
        elements.extend(
            [
                Paragraph("RÉPUBLIQUE DU MALI", styles["ministere"]),
                Paragraph(
                    "Ministère de l’Enseignement Supérieur et de la Recherche",
                    styles["ministere"],
                ),
            ]
        )
    elements.extend(
        [
            Paragraph(
                "Centre d’Intelligence Artificielle et de Robotique du Mali (CIAR-Mali)",
                styles["universite"],
            ),
            Paragraph("Département de la Formation", styles["departement"]),
            Spacer(1, 8),
            Paragraph(titre, styles["titre"]),
            Paragraph(sous_titre, styles["sous_titre"]),
        ]
    )


def _date_lieu(etudiant) -> str:
    date_texte = _date_fr(etudiant.date_naissance) if etudiant.date_naissance else ""
    lieu = (etudiant.lieu_naissance or "").strip()
    if date_texte and lieu:
        return f"{date_texte} à {lieu}"
    return date_texte or lieu or "—"


def _identite(inscription: Inscription, semestre: Semestre, styles):
    etudiant = inscription.etudiant
    gauche = [
        [Paragraph("Étudiant(e)", styles["libelle"]), Paragraph(escape(etudiant.nom_complet), styles["valeur"])],
        [Paragraph("Matricule", styles["libelle"]), Paragraph(escape(etudiant.matricule), styles["valeur"])],
        [Paragraph("Filière", styles["libelle"]),
         Paragraph(escape(inscription.filiere_nom or "—"), styles["valeur"])],
    ]
    droite = [
        [Paragraph("Date et Lieu de Naissance", styles["libelle"]),
         Paragraph(escape(_date_lieu(etudiant)), styles["valeur"])],
        [Paragraph("Niveau", styles["libelle"]), Paragraph(escape(inscription.niveau_nom), styles["valeur"])],
        [Paragraph("Semestre", styles["libelle"]),
         Paragraph(escape(f"{semestre.nom} · {semestre.annee}"), styles["valeur"])],
    ]
    tableau = Table(
        [[Table(gauche, colWidths=[3.0 * cm, 5.8 * cm]), Table(droite, colWidths=[4.6 * cm, 4.6 * cm])]],
        colWidths=[8.8 * cm, 9.2 * cm],
    )
    tableau.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
            ]
        )
    )
    return tableau


def _bloc_signature(
    styles, signataire: dict | None, largeur: float = 8.5 * cm, espace: int = 26
):
    """Bloc « fonction / espace de signature / grade abrégé + nom / grade complet »."""
    signataire = signataire or {}
    fonction = (signataire.get("fonction") or "").strip()
    nom = libelle_signataire(signataire)
    grade = (signataire.get("grade") or "").strip()
    lignes = [
        [Paragraph(escape(fonction) if fonction else "&nbsp;", styles["signature_titre"])],
        [Spacer(1, espace)],
        [Paragraph("&nbsp;", styles["signature_nom"])],
        [Paragraph(escape(nom) if nom else "&nbsp;", styles["signature_nom"])],
        [Paragraph(escape(grade) if grade else "&nbsp;", styles["signature_grade"])],
    ]
    tableau = Table(lignes, colWidths=[largeur])
    tableau.setStyle(
        TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
                ("LINEBELOW", (0, 2), (-1, 2), 0.7, colors.HexColor("#64748b")),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
            ]
        )
    )
    tableau.hAlign = "RIGHT"
    return tableau


def _resultat_pour(db: Session, inscription: Inscription, semestre_id: int, session: int) -> dict:
    from .models import ResultatSemestre

    donnees = resultat_inscription(db, inscription, semestre_id, session)
    resultat = (
        db.query(ResultatSemestre)
        .filter(
            ResultatSemestre.inscription_id == inscription.id,
            ResultatSemestre.semestre_id == semestre_id,
            ResultatSemestre.session == session,
        )
        .first()
    )
    donnees["decision"] = resultat.decision if resultat and resultat.decision else donnees["statut"]
    donnees["verrouille"] = bool(resultat.verrouille) if resultat else False
    donnees["deliberation"] = resultat
    return donnees


def generer_pdf_releve(
    db: Session, inscription_id: int, semestre_id: int, session: int = 1
) -> tuple[BytesIO, str]:
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise ValueError("Inscription introuvable")
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise ValueError("Semestre introuvable")

    donnees = _resultat_pour(db, inscription, semestre_id, session)
    signataires = lire_signataires(db)

    def construire(compact: bool) -> BytesIO:
        styles = _styles(compact=compact)
        elements = []
        _entete(
            elements,
            styles,
            "RELEVÉ DE NOTES",
            f"{escape(semestre.nom)} · Année universitaire {escape(semestre.annee)} · Session {session}",
            avec_ministere=False,
            logo_largeur=3.8 if compact else 4.4,
        )
        elements.append(_identite(inscription, semestre, styles))
        elements.append(Spacer(1, 7 if compact else 10))

        points_final = float(donnees.get("points_jury") or 0)
        # Sans pondération, seuls les coefficients des UE sont affichés.
        afficher_coefficient_ecue = bool(donnees.get("ponderation_ecue"))
        afficher_colonne_jury = any(
            abs(float(bloc.get("points_jury") or 0)) > 1e-9
            or any(
                abs(float(ecue.get("points_jury") or 0)) > 1e-9
                for ecue in bloc.get("ecues", [])
            )
            for bloc in donnees["ues"]
        )
        afficher_synthese_jury = abs(points_final) > 1e-9

        if afficher_colonne_jury:
            largeurs = [
                2.1 * cm,
                4.5 * cm,
                1.35 * cm,
                1.2 * cm,
                1.6 * cm,
                2.05 * cm,
                1.6 * cm,
                1.25 * cm,
                2.35 * cm,
            ]
        else:
            largeurs = [
                2.0 * cm,
                5.1 * cm,
                1.45 * cm,
                1.05 * cm,
                1.8 * cm,
                2.1 * cm,
                1.95 * cm,
                2.55 * cm,
            ]

        entetes = [
            "Code",
            "Intitulé",
            "Crédits",
            "Coef.",
            "CC /20",
            "Examen /20",
            "Moy. /20",
        ]
        if afficher_colonne_jury:
            entetes.append("Points jury")
        entetes.append("Statut")
        lignes = [[Paragraph(libelle, styles["entete"]) for libelle in entetes]]

        def points_affiches(valeur) -> str:
            if valeur is None or abs(float(valeur)) < 1e-9:
                return "—"
            return _nombre(valeur)

        fonds = []
        for bloc in donnees["ues"]:
            index = len(lignes)
            cellules = [
                Paragraph(escape(bloc["code"]), styles["ue"]),
                Paragraph(escape(bloc["nom"]), styles["ue"]),
                Paragraph(str(bloc["credits"]), styles["cellule_centre"]),
                Paragraph(str(bloc["coefficient"] or "—"), styles["cellule_centre"]),
                # Les UE n'affichent que leur moyenne : ni CC, ni examen.
                Paragraph("", styles["cellule_centre"]),
                Paragraph("", styles["cellule_centre"]),
                Paragraph(_nombre(bloc["moyenne"]), styles["cellule_centre"]),
            ]
            if afficher_colonne_jury:
                cellules.append(
                    Paragraph(
                        points_affiches(bloc.get("points_jury")),
                        styles["cellule_centre"],
                    )
                )
            cellules.append(Paragraph(escape(bloc["statut"]), styles["cellule_centre"]))
            lignes.append(cellules)
            fonds.append(("BACKGROUND", (0, index), (-1, index), BLEU_CLAIR))
            for ecue in bloc["ecues"]:
                index = len(lignes)
                statut_ecue = ""
                moyenne_validation = ecue.get("moyenne_jury", ecue["moyenne"])
                if not donnees.get("compensation_ecue", True) and moyenne_validation is not None:
                    statut_ecue = "Validé" if moyenne_validation >= 10 else "Non validé"
                cellules = [
                    Paragraph(f"&nbsp;&nbsp;{escape(ecue['code'])}", styles["cellule"]),
                    Paragraph(escape(ecue["nom"]), styles["cellule"]),
                    Paragraph(str(ecue.get("credits") or "—"), styles["cellule_centre"]),
                    Paragraph(
                        str(ecue["coefficient"] or "—")
                        if afficher_coefficient_ecue
                        else "",
                        styles["cellule_centre"],
                    ),
                    Paragraph(_nombre(ecue.get("cc")), styles["cellule_centre"]),
                    Paragraph(_nombre(ecue.get("examen")), styles["cellule_centre"]),
                    Paragraph(_nombre(ecue["moyenne"]), styles["cellule_centre"]),
                ]
                if afficher_colonne_jury:
                    cellules.append(
                        Paragraph(
                            points_affiches(ecue.get("points_jury")),
                            styles["cellule_centre"],
                        )
                    )
                cellules.append(Paragraph(statut_ecue, styles["cellule_centre"]))
                lignes.append(cellules)

        padding = 2.6 if compact else 3.6
        tableau = Table(lignes, colWidths=largeurs, repeatRows=1)
        style = [
            ("BACKGROUND", (0, 0), (-1, 0), BLEU),
            ("GRID", (0, 0), (-1, -1), 0.5, GRIS_BORD),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), padding),
            ("BOTTOMPADDING", (0, 0), (-1, -1), padding),
            ("LEFTPADDING", (0, 0), (-1, -1), 3.5),
            ("RIGHTPADDING", (0, 0), (-1, -1), 3.5),
        ]
        style.extend(fonds)
        tableau.setStyle(TableStyle(style))
        elements.append(tableau)
        elements.append(Spacer(1, 7 if compact else 9))

        blocs_synthese = [
            [
                Paragraph("Moyenne générale", styles["total_libelle"]),
                Paragraph(f"{_nombre(donnees['moyenne'])} / 20", styles["total_valeur"]),
            ],
            [
                Paragraph("Crédits obtenus", styles["total_libelle"]),
                Paragraph(
                    f"{donnees['credits_obtenus']} / {donnees['credits_total']}",
                    styles["total_valeur"],
                ),
            ],
        ]
        if afficher_synthese_jury:
            blocs_synthese.append(
                [
                    Paragraph("Points jury", styles["total_libelle"]),
                    Paragraph(_nombre(points_final), styles["total_valeur"]),
                ]
            )
        blocs_synthese.append(
            [
                Paragraph("Décision", styles["total_libelle"]),
                Paragraph(escape(donnees["decision"]), styles["total_valeur"]),
            ]
        )
        largeur_synthese = 18.0 / len(blocs_synthese) * cm
        synthese = Table(
            [blocs_synthese],
            colWidths=[largeur_synthese] * len(blocs_synthese),
        )
        synthese.setStyle(
            TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("TOPPADDING", (0, 0), (-1, -1), 6 if compact else 7),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 6 if compact else 7),
                    ("LEFTPADDING", (0, 0), (-1, -1), 4),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                    ("LINEABOVE", (0, 0), (-1, 0), 0.9, BLEU),
                    ("GRID", (0, 0), (-1, -1), 0.5, GRIS_BORD),
                    ("BACKGROUND", (0, 0), (-1, -1), GRIS),
                ]
            )
        )
        elements.append(synthese)
        elements.append(Spacer(1, 10 if compact else 14))

        date_ligne = Table(
            [
                [
                    Paragraph(
                        "Fait à Bamako, le " + _date_longue_fr(datetime.now()),
                        styles["date_lieu"],
                    )
                ]
            ],
            colWidths=[9 * cm],
        )
        date_ligne.setStyle(
            TableStyle(
                [
                    ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ]
            )
        )
        date_ligne.hAlign = "RIGHT"
        elements.append(date_ligne)
        elements.append(Spacer(1, 6))
        elements.append(
            _bloc_signature(
                styles,
                signataires.get("releve"),
                largeur=9 * cm,
                espace=16 if compact else 22,
            )
        )

        tampon = BytesIO()
        doc = SimpleDocTemplate(
            tampon,
            pagesize=A4,
            leftMargin=1.4 * cm,
            rightMargin=1.4 * cm,
            topMargin=1.0 * cm,
            bottomMargin=1.15 * cm,
            title="Relevé de notes",
        )
        doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
        tampon.seek(0)
        return tampon

    tampon = construire(False)
    # Un relevé doit tenir sur une seule page : on resserre la mise en page
    # si le contenu déborde légèrement sur une deuxième page.
    if _nombre_pages(tampon.getvalue()) > 1:
        tampon = construire(True)
    return tampon, f"releve_{inscription.etudiant.matricule}_{semestre_id}_S{session}.pdf"


def generer_pdf_pv(
    db: Session, semestre_id: int, niveau_id: int | None = None, session: int = 1
) -> tuple[BytesIO, str]:
    from .notes_service import calculer_semestre

    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise ValueError("Semestre introuvable")
    resultats = calculer_semestre(db, semestre_id, session, niveau_id)
    signataires = lire_signataires(db)
    styles = _styles()
    elements = []
    sous_titre = f"{escape(semestre.nom)} · {escape(semestre.annee)} · Session {session}"
    _entete(elements, styles, "PROCÈS-VERBAL DE DÉLIBÉRATION", sous_titre,avec_ministere=False,)
    elements.append(
        Paragraph(
            f"Le jury, réuni le {datetime.now().strftime('%d/%m/%Y')}, après examen des résultats, "
            f"arrête les décisions suivantes pour {len(resultats)} étudiant(s).",
            styles["paragraphe"],
        )
    )
    elements.append(Spacer(1, 10))

    lignes = [
        [
            Paragraph("Rang", styles["entete"]),
            Paragraph("Matricule", styles["entete"]),
            Paragraph("Étudiant", styles["entete"]),
            Paragraph("Niveau", styles["entete"]),
            Paragraph("Moyenne", styles["entete"]),
            Paragraph("Crédits", styles["entete"]),
            Paragraph("Statut", styles["entete"]),
            Paragraph("Décision", styles["entete"]),
        ]
    ]
    tries = sorted(resultats, key=lambda r: r.moyenne, reverse=True)
    for rang, resultat in enumerate(tries, start=1):
        lignes.append(
            [
                Paragraph(str(rang), styles["cellule_centre"]),
                Paragraph(escape(resultat.matricule), styles["cellule"]),
                Paragraph(escape(resultat.etudiant_nom), styles["cellule"]),
                Paragraph(escape(resultat.niveau_nom or "—"), styles["cellule"]),
                Paragraph(_nombre(resultat.moyenne), styles["cellule_centre"]),
                Paragraph(f"{resultat.credits_obtenus}/{resultat.credits_total}", styles["cellule_centre"]),
                Paragraph(escape(resultat.statut), styles["cellule_centre"]),
                Paragraph(escape(resultat.decision or "—"), styles["cellule_centre"]),
            ]
        )
    tableau = Table(
        lignes,
        colWidths=[1.3 * cm, 2.8 * cm, 5.5 * cm, 3.6 * cm, 2.0 * cm, 1.9 * cm, 3.6 * cm, 3.0 * cm],
        repeatRows=1,
    )
    tableau.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), BLEU),
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(tableau)
    elements.append(Spacer(1, 26))
    elements.append(_bloc_signature(styles, signataires.get("pv"), largeur=9 * cm))

    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=landscape(A4),
        leftMargin=1.2 * cm,
        rightMargin=1.2 * cm,
        topMargin=1.2 * cm,
        bottomMargin=1.2 * cm,
        title="Procès-verbal de délibération",
    )
    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    suffixe = f"niveau_{niveau_id}" if niveau_id else "tous_niveaux"
    return tampon, f"pv_deliberation_{semestre_id}_{suffixe}_S{session}.pdf"


def generer_pdf_attestation(
    db: Session, inscription_id: int, semestre_id: int, session: int = 1
) -> tuple[BytesIO, str]:
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise ValueError("Inscription introuvable")
    semestre = db.get(Semestre, semestre_id)
    if not semestre:
        raise ValueError("Semestre introuvable")
    donnees = _resultat_pour(db, inscription, semestre_id, session)
    etudiant = inscription.etudiant
    signataires = lire_signataires(db)
    fonction = signataires.get("attestation").get("fonction")
    styles = _styles()
    elements = []
    _entete(
        elements,
        styles,
        "ATTESTATION DE RÉSULTATS",
        f"{escape(semestre.nom)} · Année universitaire {escape(semestre.annee)}",
        avec_ministere=False,
    )
    elements.append(Spacer(1, 16))
    elements.append(
        Paragraph(
            #"Le Centre d’Intelligence Artificielle et de Robotique du Mali (CIAR-Mali) atteste que "
            f"<b>{escape(fonction)}</b> du Centre d’Intelligence Artificielle et de Robotique du Mali (CIAR-Mali), atteste que, "
            f"<b>{escape(etudiant.nom_complet)}</b>, matricule "
            f"<b>{escape(etudiant.matricule)}</b>, "
            f"inscrit(e) en <b>{escape(inscription.niveau_nom)}</b> "
            f"({escape(inscription.filiere_nom or '—')}), a obtenu les résultats suivants "
            f"au titre du <b>{escape(semestre.nom)}</b> de l’année universitaire "
            f"<b>{escape(semestre.annee)}</b> :",
            styles["paragraphe"],
        )
    )
    elements.append(Spacer(1, 14))

    lignes = [
        ["Moyenne générale", f"{_nombre(donnees['moyenne'])} / 20"],
        ["Crédits obtenus", f"{donnees['credits_obtenus']} / {donnees['credits_total']}"],
        ["Mention", donnees["mention"] or "—"],
        ["Décision du jury", donnees["decision"]],
        ["Session", str(session)],
    ]
    tableau = Table(lignes, colWidths=[7 * cm, 9 * cm])
    tableau.setStyle(
        TableStyle(
            [
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("TEXTCOLOR", (0, 0), (0, -1), colors.HexColor("#475569")),
                ("FONTNAME", (1, 0), (1, -1), "Helvetica-Bold"),
                ("BACKGROUND", (0, 0), (0, -1), GRIS),
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(tableau)
    elements.append(Spacer(1, 20))
    elements.append(
        Paragraph(
            "La présente attestation est délivrée à l’intéressé(e) pour servir et valoir ce que de droit.",
            styles["paragraphe"],
        )
    )
    elements.append(Spacer(1, 34))
    signature = _bloc_signature(styles, signataires.get("attestation"), largeur=9 * cm)
    elements.append(KeepTogether([signature]))

    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=A4,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=1.4 * cm,
        bottomMargin=1.3 * cm,
        title="Attestation de résultats",
    )
    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    return (
        tampon,
        f"attestation_{etudiant.matricule}_{semestre_id}_S{session}.pdf",
    )


# ============================================ Passages et attestations de diplôme
def _libelle_niveau(niveau: Niveau | None) -> str:
    if niveau is None:
        return ""
    nom = (niveau.nom or "").strip()
    filiere = niveau.filiere.nom if niveau.filiere else ""
    if filiere and filiere.lower() not in nom.lower():
        return f"{nom} — {filiere}"
    return nom


def _texte_semestres(resultat: dict) -> str:
    noms = [detail.get("semestre") or "" for detail in resultat.get("semestres", [])]
    return " / ".join(nom for nom in noms if nom) or "—"


def generer_pdf_passages(
    db: Session,
    annee: str,
    session: int = 1,
    mode: str = "10",
    seuil_dettes: float = 80,
    moyenne_passage: float = 10,
    niveau_id: int | None = None,
) -> tuple[BytesIO, str]:
    """Liste globale des étudiants admis en classe supérieure."""
    from .notes_service import resultats_passage

    resultats = resultats_passage(
        db,
        annee=annee,
        session=session,
        mode=mode,
        seuil_dettes=seuil_dettes,
        moyenne_passage=moyenne_passage,
        niveau_id=niveau_id,
    )
    admis = [resultat for resultat in resultats if resultat["admis"]]
    niveau = db.get(Niveau, niveau_id) if niveau_id else None
    libelle = _libelle_niveau(niveau) if niveau else "toutes filières"
    titre = (
        f"Liste des étudiants de {niveau.nom} admis en classe supérieure"
        if niveau
        else "Liste des étudiants admis en classe supérieure"
    )
    sous_titre = f"{libelle} · Année universitaire {annee} · Session {session}"

    styles = _styles()
    elements = []
    _entete(elements, styles, escape(titre), escape(sous_titre), avec_ministere=False)
    elements.append(Spacer(1, 10))
    elements.append(
        Paragraph(
            f"{len(admis)} étudiant(s) admis sur {len(resultats)} inscrit(s). "
            f"Mode de passage : {escape(str(mode))}.",
            styles["paragraphe"],
        )
    )
    elements.append(Spacer(1, 10))

    entetes = [
        "Matricule",
        "Étudiant",
        "Semestre",
        "Moyenne annuelle",
        "Crédit",
        "% crédit",
        "Décision",
        "Passage",
    ]
    lignes = [[Paragraph(escape(entete), styles["entete"]) for entete in entetes]]
    for resultat in admis:
        lignes.append(
            [
                Paragraph(escape(resultat.get("matricule") or "—"), styles["cellule_centre"]),
                Paragraph(escape(resultat.get("etudiant") or "—"), styles["cellule"]),
                Paragraph(escape(_texte_semestres(resultat)), styles["cellule_centre"]),
                Paragraph(_nombre(resultat.get("moyenne_annee")), styles["cellule_centre"]),
                Paragraph(
                    f"{resultat.get('credits_obtenus', 0)} / {resultat.get('credits_total', 0)}",
                    styles["cellule_centre"],
                ),
                Paragraph(
                    f"{_nombre(resultat.get('pourcentage_credits'), 1)} %",
                    styles["cellule_centre"],
                ),
                Paragraph(escape(resultat.get("decision") or "—"), styles["cellule"]),
                Paragraph(escape(resultat.get("niveau_suivant") or "—"), styles["cellule"]),
            ]
        )
    tableau = Table(
        lignes,
        colWidths=[
            2.6 * cm, 4.4 * cm, 3.0 * cm, 2.5 * cm,
            2.2 * cm, 2.0 * cm, 4.2 * cm, 4.6 * cm,
        ],
        repeatRows=1,
    )
    tableau.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), BLEU),
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    elements.append(tableau)
    elements.append(Spacer(1, 18))

    signataires = lire_signataires(db)
    signature = _bloc_signature(styles, signataires.get("attestation"), largeur=9 * cm)
    elements.append(KeepTogether([signature]))
    elements.append(Spacer(1, 10))
    elements.append(
        Paragraph(
            f"Année universitaire : <b>{escape(annee)}</b>",
            styles["paragraphe"],
        )
    )

    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=landscape(A4),
        leftMargin=1.4 * cm,
        rightMargin=1.4 * cm,
        topMargin=1.2 * cm,
        bottomMargin=1.1 * cm,
        title="Liste des étudiants admis en classe supérieure",
    )
    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    suffixe = f"niveau_{niveau_id}" if niveau_id else "tous_niveaux"
    return tampon, f"passages_{suffixe}_{annee}.pdf"


def _resultat_passage_inscription(
    db: Session,
    inscription: Inscription,
    session: int,
    mode: str,
    seuil_dettes: float,
    moyenne_passage: float,
) -> dict | None:
    from .notes_service import resultats_passage

    resultats = resultats_passage(
        db,
        annee=inscription.annee,
        session=session,
        mode=mode,
        seuil_dettes=seuil_dettes,
        moyenne_passage=moyenne_passage,
        niveau_id=inscription.niveau_id,
        inscription_id=inscription.id,
    )
    return next(
        (
            resultat
            for resultat in resultats
            if resultat["inscription_id"] == inscription.id
        ),
        None,
    )


def generer_pdf_releve_passage(
    db: Session,
    inscription_id: int,
    session: int = 1,
    mode: str = "10",
    seuil_dettes: float = 80,
    moyenne_passage: float = 10,
) -> tuple[BytesIO, str]:
    """Relevé récapitulatif de passage d'un étudiant."""
    inscription = db.get(Inscription, inscription_id)
    if not inscription:
        raise ValueError("Inscription introuvable")
    resultat = _resultat_passage_inscription(
        db, inscription, session, mode, seuil_dettes, moyenne_passage
    )
    if resultat is None:
        raise ValueError("Aucun résultat de passage pour cet étudiant")

    etudiant = inscription.etudiant
    styles = _styles()
    elements = []
    _entete(
        elements,
        styles,
        "RELEVÉ RÉCAPITULATIF DE PASSAGE",
        f"{escape(inscription.niveau_nom or '—')} · "
        f"Année universitaire {escape(inscription.annee)}",
        avec_ministere=False,
    )
    elements.append(Spacer(1, 12))

    identite = [
        ["Année universitaire", inscription.annee],
        ["Filière", inscription.filiere_nom or "—"],
        ["Niveau", inscription.niveau_nom or "—"],
        ["Matricule", etudiant.matricule if etudiant else "—"],
        ["Prénom et nom", etudiant.nom_complet if etudiant else "—"],
        ["Date de naissance", _date_fr(etudiant.date_naissance) if etudiant else "—"],
    ]
    tableau_identite = Table(
        [
            [
                Paragraph(escape(libelle), styles["libelle"]),
                Paragraph(escape(str(valeur)), styles["valeur"]),
            ]
            for libelle, valeur in identite
        ],
        colWidths=[5 * cm, 11 * cm],
    )
    tableau_identite.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("BACKGROUND", (0, 0), (0, -1), GRIS),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
            ]
        )
    )
    elements.append(tableau_identite)
    elements.append(Spacer(1, 14))

    details = resultat.get("semestres", [])
    noms_semestres = [
        str(detail.get("semestre") or "—") for detail in details
    ]
    elements.append(Paragraph("Détail des semestres", styles["section"]))
    lignes = [
        [
            Paragraph("Semestre", styles["entete"]),
            Paragraph("Moyenne", styles["entete"]),
            Paragraph("Crédits obtenus", styles["entete"]),
            Paragraph("Crédits total", styles["entete"]),
            Paragraph("Statut", styles["entete"]),
        ]
    ]
    for detail in details:
        lignes.append(
            [
                Paragraph(escape(detail.get("semestre") or "—"), styles["cellule_centre"]),
                Paragraph(_nombre(detail.get("moyenne")), styles["cellule_centre"]),
                Paragraph(str(detail.get("credits_obtenus", 0)), styles["cellule_centre"]),
                Paragraph(str(detail.get("credits_total", 0)), styles["cellule_centre"]),
                Paragraph(escape(detail.get("statut") or "—"), styles["cellule_centre"]),
            ]
        )
    tableau = Table(
        lignes,
        colWidths=[4.2 * cm, 3.2 * cm, 3.4 * cm, 3.2 * cm, 4.0 * cm],
        repeatRows=1,
    )
    tableau.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), BLEU),
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    elements.append(tableau)
    elements.append(Spacer(1, 12))

    elements.append(
        Paragraph("Récapitulatif des deux semestres", styles["section"])
    )
    if noms_semestres:
        elements.append(
            Paragraph(
                escape(
                    "Semestres pris en compte : " + " + ".join(noms_semestres)
                ),
                styles["libelle"],
            )
        )
        elements.append(Spacer(1, 6))

    recapitulatif = [
        ["Moyenne annuelle des deux semestres", _nombre(resultat.get("moyenne_annee"))],
        [
            "Crédits obtenus",
            f"{resultat.get('credits_obtenus', 0)} / {resultat.get('credits_total', 0)}",
        ],
        [
            "Pourcentage de crédits obtenus",
            f"{_nombre(resultat.get('pourcentage_credits'), 1)} %",
        ],
        ["Décision du jury", resultat.get("decision") or "—"],
        [
            "Passage",
            (resultat.get("niveau_suivant") or "—")
            if resultat.get("admis")
            else "—",
        ],
    ]
    tableau_recap = Table(
        [
            [
                Paragraph(escape(libelle), styles["libelle"]),
                Paragraph(escape(str(valeur)), styles["valeur"]),
            ]
            for libelle, valeur in recapitulatif
        ],
        colWidths=[7 * cm, 9 * cm],
    )
    tableau_recap.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("BACKGROUND", (0, 0), (0, -1), GRIS),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
            ]
        )
    )
    elements.append(tableau_recap)
    elements.append(Spacer(1, 24))

    signataires = lire_signataires(db)
    signature = _bloc_signature(styles, signataires.get("releve"), largeur=9 * cm)
    elements.append(KeepTogether([signature]))

    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=A4,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=1.4 * cm,
        bottomMargin=1.3 * cm,
        title="Relevé récapitulatif de passage",
    )
    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    return tampon, f"passage_{etudiant.matricule if etudiant else inscription_id}.pdf"


def generer_pdf_diplome(
    db: Session, etudiant_id: int, cycle: str | None = None
) -> tuple[BytesIO, str]:
    """Attestation de réussite d'un diplôme (Licence, Master, Grade d'ingénieur)."""
    from .notes_service import diplome_etudiant

    diplomes = [
        diplome
        for diplome in diplome_etudiant(db, etudiant_id)
        if diplome["eligible"]
    ]
    if cycle:
        diplomes = [diplome for diplome in diplomes if diplome["cycle"] == cycle]
    if not diplomes:
        raise ValueError("Aucun diplôme validé pour cet étudiant")
    diplome = diplomes[0]
    etudiant = db.get(Etudiant, etudiant_id)
    if etudiant is None:
        raise ValueError("Étudiant introuvable")

    signataires = lire_signataires(db)
    signataire = signataires.get("attestation")
    fonction = (signataire or {}).get("fonction") or "L’autorité compétente"
    styles = _styles()
    elements = []
    _entete(
        elements,
        styles,
        "ATTESTATION DE RÉUSSITE DE DIPLÔME",
        f"Diplôme : {escape(diplome['diplome'])}",
        avec_ministere=False,
    )
    elements.append(Spacer(1, 18))
    elements.append(
        Paragraph(
            f"<b>{escape(fonction)}</b> du Centre d’Intelligence Artificielle et de "
            "Robotique du Mali (CIAR-Mali), atteste que, "
            f"<b>{escape(etudiant.nom_complet)}</b>, matricule "
            f"<b>{escape(etudiant.matricule)}</b>, né(e) le "
            f"<b>{escape(_date_fr(etudiant.date_naissance))}</b>, "
            f"a validé les conditions du diplôme de <b>{escape(diplome['diplome'])}</b> "
            f"au titre de l’année universitaire "
            f"<b>{escape(diplome['annee_validation'] or '—')}</b>.",
            styles["paragraphe"],
        )
    )
    elements.append(Spacer(1, 14))
    lignes = [
        ["Diplôme obtenu", diplome["diplome"]],
        [
            "Semestres validés",
            f"{diplome['semestres_valides']} / {diplome['semestres_requis']}",
        ],
        ["Année universitaire de validation", diplome["annee_validation"] or "—"],
    ]
    tableau = Table(
        [
            [
                Paragraph(escape(libelle), styles["libelle"]),
                Paragraph(escape(str(valeur)), styles["valeur"]),
            ]
            for libelle, valeur in lignes
        ],
        colWidths=[7 * cm, 9 * cm],
    )
    tableau.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.4, GRIS_BORD),
                ("BACKGROUND", (0, 0), (0, -1), GRIS),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    elements.append(tableau)
    elements.append(Spacer(1, 20))
    elements.append(
        Paragraph(
            "La présente attestation est délivrée à l’intéressé(e) pour servir "
            "et valoir ce que de droit.",
            styles["paragraphe"],
        )
    )
    elements.append(Spacer(1, 34))
    signature = _bloc_signature(styles, signataire, largeur=9 * cm)
    elements.append(KeepTogether([signature]))

    tampon = BytesIO()
    doc = SimpleDocTemplate(
        tampon,
        pagesize=A4,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=1.4 * cm,
        bottomMargin=1.3 * cm,
        title="Attestation de réussite de diplôme",
    )
    doc.build(elements, onFirstPage=_pied_de_page, onLaterPages=_pied_de_page)
    tampon.seek(0)
    return tampon, f"attestation_diplome_{etudiant.matricule}_{diplome['cycle']}.pdf"
