"""Routes CRUD génériques pour les référentiels."""
import unicodedata
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload, selectinload

from ..database import get_db
from ..models import (
    Affectation,
    Creneau,
    Departement,
    ECUE,
    Enseignant,
    Etudiant,
    Evaluation,
    Filiere,
    Groupe,
    Niveau,
    Note,
    ResultatSemestre,
    Salle,
    Seance,
    Semestre,
    UE,
    Utilisateur,
)
from ..schemas import (
    AffectationCreate,
    AffectationOut,
    AffectationUpdate,
    CopieUE,
    CreneauCreate,
    CreneauOut,
    CreneauUpdate,
    DepartementCreate,
    DepartementOut,
    DepartementUpdate,
    ECUECreate,
    ECUEOut,
    ECUEUpdate,
    EnseignantCreate,
    EnseignantOut,
    EnseignantUpdate,
    FiliereCreate,
    FiliereOut,
    FiliereUpdate,
    GroupeCreate,
    GroupeOut,
    GroupeUpdate,
    NiveauCreate,
    NiveauOut,
    NiveauUpdate,
    SalleCreate,
    SalleOut,
    SalleUpdate,
    SemestreCreate,
    SemestreOut,
    SemestreUpdate,
    UECreate,
    UEOut,
    UEUpdate,
    UtilisateurCreate,
    UtilisateurOut,
    UtilisateurUpdate,
)
from ..security import (
    ROLES,
    admin_ou_gestionnaire,
    admin_seul,
    hacher_mot_de_passe,
    utilisateur_courant,
)

router = APIRouter(prefix="/api", tags=["référentiels"])


def _erreur_integrite(exc: IntegrityError):
    message = str(exc.orig)
    if "UNIQUE" in message.upper() or "DUPLICATE" in message.upper():
        raise HTTPException(409, "Un enregistrement avec ces valeurs existe déjà.")
    if "FOREIGN KEY" in message.upper():
        raise HTTPException(400, "Référence liée introuvable ou encore utilisée.")
    raise HTTPException(400, f"Opération impossible : {message}")


def monter_crud(
    chemin: str,
    modele,
    schema_sortie,
    schema_creation,
    schema_maj,
    ordre=None,
    apres_ecriture=None,
    apres_suppression=None,
    avant_suppression=None,
    avant_modification=None,
    options=None,
):
    """Monte les 4 routes CRUD classiques pour un modèle.

    `apres_ecriture(db, element, anciens)` et `apres_suppression(db, anciens)`
    permettent de maintenir des données dérivées (ex. crédits des UE).
    `avant_suppression(db, element)` peut refuser une suppression.
    `avant_modification(db, element, donnees, utilisateur)` peut refuser une
    modification sensible (ex. UE dont les notes sont déjà saisies).
    `options` liste les chargements liés (`joinedload`, `selectinload`) à
    appliquer aux lectures : sans eux, chaque ligne déclenche des requêtes
    supplémentaires pour ses libellés, ce qui est très lent sur une base
    distante.
    """

    @router.get(chemin, response_model=list[schema_sortie])
    def lister(
        db: Session = Depends(get_db),
        _: Utilisateur = Depends(utilisateur_courant),
    ):
        requete = db.query(modele)
        if options:
            requete = requete.options(*options)
        if ordre is not None:
            requete = requete.order_by(ordre)
        return requete.all()

    @router.get(f"{chemin}/{{element_id}}", response_model=schema_sortie)
    def detail(
        element_id: int,
        db: Session = Depends(get_db),
        _: Utilisateur = Depends(utilisateur_courant),
    ):
        requete = db.query(modele).filter(modele.id == element_id)
        if options:
            requete = requete.options(*options)
        element = requete.first()
        if not element:
            raise HTTPException(404, "Élément introuvable")
        return element

    @router.post(chemin, response_model=schema_sortie, status_code=201)
    def creer(
        payload: schema_creation,
        db: Session = Depends(get_db),
        _: Utilisateur = Depends(admin_ou_gestionnaire),
    ):
        donnees = payload.model_dump()
        niveau_ids = donnees.pop("niveau_ids", None)
        if donnees.get("niveau_id") is None:
            donnees.pop("niveau_id", None)
        if niveau_ids and "niveau_id" not in donnees:
            try:
                donnees["niveau_id"] = int(niveau_ids[0])
            except (TypeError, ValueError):
                pass
        element = modele(**donnees)
        db.add(element)
        try:
            db.flush()
            if niveau_ids is not None and hasattr(element, "niveaux"):
                _definir_niveaux_ue(db, element, niveau_ids)
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            _erreur_integrite(exc)
        except HTTPException:
            db.rollback()
            raise
        db.refresh(element)
        if apres_ecriture is not None:
            apres_ecriture(db, element, None)
            db.commit()
            db.refresh(element)
        return element

    @router.put(f"{chemin}/{{element_id}}", response_model=schema_sortie)
    def modifier(
        element_id: int,
        payload: schema_maj,
        db: Session = Depends(get_db),
        utilisateur: Utilisateur = Depends(admin_ou_gestionnaire),
    ):
        element = db.get(modele, element_id)
        if not element:
            raise HTTPException(404, "Élément introuvable")
        anciens = {
            colonne.name: getattr(element, colonne.name)
            for colonne in modele.__table__.columns
        }
        donnees = payload.model_dump(exclude_unset=True)
        niveau_ids = donnees.pop("niveau_ids", None)
        if avant_modification is not None:
            avant_modification(db, element, donnees, utilisateur)
        for cle, valeur in donnees.items():
            setattr(element, cle, valeur)
        try:
            if (
                niveau_ids is not None
                and hasattr(element, "niveaux")
                and niveau_ids
            ):
                _definir_niveaux_ue(db, element, niveau_ids)
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            _erreur_integrite(exc)
        except HTTPException:
            db.rollback()
            raise
        db.refresh(element)
        if apres_ecriture is not None:
            apres_ecriture(db, element, anciens)
            db.commit()
            db.refresh(element)
        return element

    @router.delete(f"{chemin}/{{element_id}}")
    def supprimer(
        element_id: int,
        db: Session = Depends(get_db),
        _: Utilisateur = Depends(admin_ou_gestionnaire),
    ):
        element = db.get(modele, element_id)
        if not element:
            raise HTTPException(404, "Élément introuvable")
        if avant_suppression is not None:
            avant_suppression(db, element)
        anciens = {
            colonne.name: getattr(element, colonne.name)
            for colonne in modele.__table__.columns
        }
        db.delete(element)
        try:
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            _erreur_integrite(exc)
        if apres_suppression is not None:
            apres_suppression(db, anciens)
            db.commit()
        return {"ok": True, "message": "Élément supprimé"}


def _definir_niveaux_ue(db: Session, ue: UE, niveau_ids):
    """Rattache une UE à plusieurs niveaux (mutualisation).

    Le niveau principal (`UE.niveau_id`) reste le propriétaire historique de
    l'UE ; les autres niveaux sont stockés dans la table d'association.
    Les niveaux retenus doivent appartenir au même niveau d'études.
    """
    if niveau_ids is None:
        return
    identifiants: list[int] = []
    for valeur in niveau_ids:
        try:
            identifiant = int(valeur)
        except (TypeError, ValueError):
            continue
        if identifiant not in identifiants:
            identifiants.append(identifiant)
    if not identifiants:
        return

    niveaux = db.query(Niveau).filter(Niveau.id.in_(identifiants)).all()
    if len(niveaux) != len(identifiants):
        raise HTTPException(400, "Niveau introuvable pour la mutualisation")
    if len({niveau.ordre for niveau in niveaux}) > 1:
        raise HTTPException(
            400,
            "Les filières mutualisées doivent appartenir au même niveau d'études.",
        )

    principal = ue.niveau_id
    if principal is None or principal not in identifiants:
        principal = identifiants[0]
    ue.niveau_id = principal
    ue.niveaux = [niveau for niveau in niveaux if niveau.id != principal]
    db.add(ue)


def _avant_suppression_ue(db: Session, element: UE):
    """Refuse la suppression d'une UE mutualisée ou utilisée académiquement."""
    if element.niveaux:
        raise HTTPException(
            400,
            "Cette UE est mutualisée avec d'autres filières. "
            "Retirez les rattachements avant de la supprimer.",
        )
    ecue_ids = [ecue.id for ecue in element.ecues]
    if not ecue_ids:
        return
    evaluation = (
        db.query(Evaluation.id).filter(Evaluation.ecue_id.in_(ecue_ids)).first()
    )
    affectation = (
        db.query(Affectation.id).filter(Affectation.ecue_id.in_(ecue_ids)).first()
    )
    seance = db.query(Seance.id).filter(Seance.ecue_id.in_(ecue_ids)).first()
    if evaluation or affectation or seance:
        raise HTTPException(
            400,
            "Des données académiques (évaluations, notes, séances ou affectations) "
            "dépendent de cette UE : suppression impossible.",
        )


def _notes_existantes_pour_ecues(db: Session, ecue_ids: list[int]) -> bool:
    if not ecue_ids:
        return False
    return (
        db.query(Note.id)
        .join(Evaluation, Note.evaluation_id == Evaluation.id)
        .filter(Evaluation.ecue_id.in_(ecue_ids))
        .first()
        is not None
    )


def _avant_modification_ue(db: Session, element: UE, donnees: dict, utilisateur):
    """Une UE dont des notes existent ne peut être déplacée que par un admin."""
    champs_sensibles = {"semestre_id", "niveau_id"}
    if not champs_sensibles.intersection(donnees):
        return
    if all(getattr(element, champ) == valeur for champ, valeur in donnees.items() if champ in champs_sensibles):
        return
    if not _notes_existantes_pour_ecues(db, [ecue.id for ecue in element.ecues]):
        return
    if getattr(utilisateur, "role", "") != "admin":
        raise HTTPException(
            403,
            "Cette UE comporte des notes déjà saisies : seul un administrateur "
            "peut modifier son semestre ou son niveau.",
        )


def _avant_modification_ecue(db: Session, element: ECUE, donnees: dict, utilisateur):
    """Un ECUE dont des notes existent ne peut être déplacé que par un admin."""
    champs_sensibles = {"ue_id", "semestre_id"}
    if not champs_sensibles.intersection(donnees):
        return
    if all(getattr(element, champ) == valeur for champ, valeur in donnees.items() if champ in champs_sensibles):
        return
    if not _notes_existantes_pour_ecues(db, [element.id]):
        return
    if getattr(utilisateur, "role", "") != "admin":
        raise HTTPException(
            403,
            "Cet ECUE comporte des notes déjà saisies : seul un administrateur "
            "peut le rattacher à une autre UE ou à un autre semestre.",
        )


def _recalculer_credits_ue(db: Session, ue_id: int | None):
    """Le crédit d'une UE est la somme des crédits de ses ECUE.

    Une UE sans ECUE conserve son crédit prévisionnel saisi à la création.
    """
    if ue_id is None:
        return
    ue = db.get(UE, ue_id)
    if ue is None:
        return
    ecues = list(ue.ecues)
    if not ecues:
        return
    ue.credits = sum(ecue.credits or 0 for ecue in ecues)
    db.add(ue)


def _synchroniser_credits_ecue(db: Session, element: ECUE, anciens):
    if element.ue is not None:
        # Le semestre de l'ECUE découle toujours de son UE.
        element.semestre_id = element.ue.semestre_id
        db.add(element)
    _recalculer_credits_ue(db, element.ue_id)
    if anciens and anciens.get("ue_id") != element.ue_id:
        _recalculer_credits_ue(db, anciens.get("ue_id"))


def _synchroniser_credits_ue(db: Session, element: UE, _anciens):
    _recalculer_credits_ue(db, element.id)
    # Les ECUE rattachés suivent le semestre de leur UE.
    for ecue in element.ecues:
        if ecue.semestre_id != element.semestre_id:
            ecue.semestre_id = element.semestre_id
            db.add(ecue)


def _synchroniser_suppression_ecue(db: Session, anciens):
    if anciens:
        _recalculer_credits_ue(db, anciens.get("ue_id"))


monter_crud("/departements", Departement, DepartementOut, DepartementCreate, DepartementUpdate, Departement.nom)
monter_crud(
    "/filieres",
    Filiere,
    FiliereOut,
    FiliereCreate,
    FiliereUpdate,
    Filiere.nom,
    options=(joinedload(Filiere.departement),),
)
monter_crud(
    "/niveaux",
    Niveau,
    NiveauOut,
    NiveauCreate,
    NiveauUpdate,
    Niveau.ordre,
    options=(joinedload(Niveau.filiere),),
)
monter_crud(
    "/groupes",
    Groupe,
    GroupeOut,
    GroupeCreate,
    GroupeUpdate,
    Groupe.nom,
    options=(joinedload(Groupe.niveau).joinedload(Niveau.filiere),),
)
monter_crud(
    "/enseignants",
    Enseignant,
    EnseignantOut,
    EnseignantCreate,
    EnseignantUpdate,
    Enseignant.nom,
    options=(joinedload(Enseignant.departement),),
)
monter_crud("/salles", Salle, SalleOut, SalleCreate, SalleUpdate, Salle.nom)
monter_crud("/creneaux", Creneau, CreneauOut, CreneauCreate, CreneauUpdate, Creneau.jour)
monter_crud("/semestres", Semestre, SemestreOut, SemestreCreate, SemestreUpdate, Semestre.id)
monter_crud(
    "/ues",
    UE,
    UEOut,
    UECreate,
    UEUpdate,
    UE.code,
    apres_ecriture=_synchroniser_credits_ue,
    avant_suppression=_avant_suppression_ue,
    avant_modification=_avant_modification_ue,
    options=(
        selectinload(UE.niveaux),
        joinedload(UE.semestre),
        joinedload(UE.niveau),
        joinedload(UE.departement),
    ),
)
monter_crud(
    "/ecues",
    ECUE,
    ECUEOut,
    ECUECreate,
    ECUEUpdate,
    ECUE.code,
    apres_ecriture=_synchroniser_credits_ecue,
    apres_suppression=_synchroniser_suppression_ecue,
    avant_modification=_avant_modification_ecue,
    options=(
        joinedload(ECUE.ue).joinedload(UE.niveau),
        joinedload(ECUE.semestre),
    ),
)


def _code_ecue_disponible(code: str, utilises: set[str]) -> str:
    """Renvoie un code d'ECUE unique (suffixe numérique si nécessaire)."""
    if code not in utilises:
        return code
    index = 2
    while True:
        suffixe = f"-{index}"
        candidat = f"{code[: 30 - len(suffixe)]}{suffixe}"
        if candidat not in utilises:
            return candidat
        index += 1


@router.post("/ues/copier", tags=["ues"])
def copier_ues(
    payload: CopieUE,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    """Copie les UE et ECUE d'un semestre vers un autre (nouvelle année)."""
    source = db.get(Semestre, payload.semestre_source_id)
    cible = db.get(Semestre, payload.semestre_cible_id)
    if not source or not cible:
        raise HTTPException(404, "Semestre source ou cible introuvable")
    if source.id == cible.id:
        raise HTTPException(400, "Le semestre source et le semestre cible doivent être différents.")

    requete = db.query(UE).filter(UE.semestre_id == source.id)
    ues = requete.order_by(UE.code).all()
    if payload.niveau_ids:
        retenus = set(payload.niveau_ids)
        ues = [ue for ue in ues if retenus.intersection(ue.niveau_ids)]

    codes_ues_cible = {
        ligne[0]
        for ligne in db.query(UE.code).filter(UE.semestre_id == cible.id).all()
    }
    # Un même code d'ECUE peut exister dans plusieurs semestres : seul le
    # semestre de destination impose un suffixe en cas de doublon.
    codes_ecue_cible = {
        ligne[0]
        for ligne in db.query(ECUE.code).filter(ECUE.semestre_id == cible.id).all()
    }

    ues_copiees = 0
    ecues_copies = 0
    ignores = 0
    for ue in ues:
        if ue.code in codes_ues_cible:
            ignores += 1
            continue
        nouvelle = UE(
            code=ue.code,
            nom=ue.nom,
            credits=ue.credits,
            semestre_id=cible.id,
            niveau_id=ue.niveau_id,
            departement_id=ue.departement_id,
        )
        db.add(nouvelle)
        db.flush()
        for niveau in ue.niveaux:
            nouvelle.niveaux.append(niveau)
        for ecue in ue.ecues:
            code_ecue = _code_ecue_disponible(ecue.code, codes_ecue_cible)
            codes_ecue_cible.add(code_ecue)
            db.add(
                ECUE(
                    code=code_ecue,
                    nom=ecue.nom,
                    credits=ecue.credits,
                    ue_id=nouvelle.id,
                    semestre_id=cible.id,
                    heures_cm=ecue.heures_cm,
                    heures_td=ecue.heures_td,
                    heures_tp=ecue.heures_tp,
                )
            )
            ecues_copies += 1
        codes_ues_cible.add(ue.code)
        ues_copiees += 1

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)

    message = (
        f"{ues_copiees} UE et {ecues_copies} ECUE copiés de "
        f"{source.nom} ({source.annee}) vers {cible.nom} ({cible.annee})."
    )
    if ignores:
        message += f" {ignores} UE déjà présente(s) ignorée(s)."
    return {
        "ok": True,
        "ues": ues_copiees,
        "ecues": ecues_copies,
        "ignorees": ignores,
        "message": message,
    }


def _valider_affectation(db: Session, donnees: dict, element: Affectation | None = None):
    """Rattache l'affectation au semestre de son ECUE et contrôle la cohérence.

    Le semestre n'est jamais choisi librement : il découle de l'ECUE. Cela
    garantit qu'un même code d'ECUE présent dans plusieurs semestres possède
    des affectations indépendantes.
    """
    ecue_id = donnees.get("ecue_id", element.ecue_id if element else None)
    ecue = db.get(ECUE, ecue_id) if ecue_id else None
    if ecue is None:
        raise HTTPException(400, "ECUE introuvable.")
    if ecue.semestre_id is None:
        raise HTTPException(
            400,
            "Cet ECUE n'est rattaché à aucun semestre. Rattachez-le à une UE "
            "avant de créer une affectation.",
        )
    semestre_demande = donnees.get("semestre_id")
    if semestre_demande is not None and semestre_demande != ecue.semestre_id:
        raise HTTPException(
            400,
            "Le semestre de l'affectation doit correspondre à celui de l'ECUE.",
        )
    donnees["semestre_id"] = ecue.semestre_id

    groupe_id = donnees.get("groupe_id", element.groupe_id if element else None)
    groupe = db.get(Groupe, groupe_id) if groupe_id else None
    if groupe is None:
        raise HTTPException(400, "Groupe introuvable.")
    niveau_ids = set(ecue.ue.niveau_ids) if ecue.ue is not None else set()
    if niveau_ids and groupe.niveau_id not in niveau_ids:
        raise HTTPException(
            400,
            "Le groupe sélectionné n'appartient pas au niveau de l'ECUE.",
        )
    return donnees


@router.get("/affectations", response_model=list[AffectationOut], tags=["affectations"])
def lister_affectations(
    enseignant_id: Optional[int] = Query(None),
    groupe_id: Optional[int] = Query(None),
    ecue_id: Optional[int] = Query(None),
    semestre_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(utilisateur_courant),
):
    requete = db.query(Affectation).options(
        joinedload(Affectation.semestre),
        joinedload(Affectation.enseignant),
        joinedload(Affectation.ecue).joinedload(ECUE.ue),
        joinedload(Affectation.groupe),
    )
    if enseignant_id:
        requete = requete.filter(Affectation.enseignant_id == enseignant_id)
    if groupe_id:
        requete = requete.filter(Affectation.groupe_id == groupe_id)
    if ecue_id:
        requete = requete.filter(Affectation.ecue_id == ecue_id)
    if semestre_id:
        requete = requete.filter(Affectation.semestre_id == semestre_id)
    return requete.order_by(
        Affectation.semestre_id, Affectation.enseignant_id, Affectation.ecue_id
    ).all()


@router.post("/affectations", response_model=AffectationOut, status_code=201, tags=["affectations"])
def creer_affectation(
    payload: AffectationCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    donnees = _valider_affectation(db, payload.model_dump())
    element = Affectation(**donnees)
    db.add(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.put("/affectations/{element_id}", response_model=AffectationOut, tags=["affectations"])
def modifier_affectation(
    element_id: int,
    payload: AffectationUpdate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Affectation, element_id)
    if not element:
        raise HTTPException(404, "Affectation introuvable")
    donnees = _valider_affectation(
        db, payload.model_dump(exclude_unset=True), element
    )
    for cle, valeur in donnees.items():
        setattr(element, cle, valeur)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.delete("/affectations/{element_id}", tags=["affectations"])
def supprimer_affectation(
    element_id: int,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_ou_gestionnaire),
):
    element = db.get(Affectation, element_id)
    if not element:
        raise HTTPException(404, "Affectation introuvable")
    db.delete(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    return {"ok": True, "message": "Affectation supprimée"}


# ------------------------------------------------------------------ Utilisateurs
@router.get("/utilisateurs", response_model=list[UtilisateurOut], tags=["utilisateurs"])
def lister_utilisateurs(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_seul),
):
    return db.query(Utilisateur).order_by(Utilisateur.identifiant).all()


@router.post("/utilisateurs", response_model=UtilisateurOut, status_code=201, tags=["utilisateurs"])
def creer_utilisateur(
    payload: UtilisateurCreate,
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_seul),
):
    if payload.role not in ROLES:
        raise HTTPException(400, "Rôle invalide")
    element = Utilisateur(
        identifiant=payload.identifiant,
        mot_de_passe_hash=hacher_mot_de_passe(payload.mot_de_passe),
        nom_complet=payload.nom_complet or payload.identifiant,
        role=payload.role,
        actif=payload.actif,
        enseignant_id=payload.enseignant_id,
    )
    db.add(element)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


def _identifiant_disponible(db: Session, base: str, utilises: set[str]) -> str:
    """Construit un identifiant unique à partir d'un prénom."""
    normalise = unicodedata.normalize("NFKD", base or "")
    normalise = normalise.encode("ascii", "ignore").decode("ascii").lower()
    racine = "".join(caractere for caractere in normalise if caractere.isalnum())
    if len(racine) < 2:
        racine = "compte"
    racine = racine[:70]
    candidat = racine
    suffixe = 2
    while candidat in utilises or db.query(Utilisateur).filter(
        Utilisateur.identifiant == candidat
    ).first():
        candidat = f"{racine}{suffixe}"
        suffixe += 1
    utilises.add(candidat)
    return candidat


@router.post("/utilisateurs/comptes-par-defaut", tags=["utilisateurs"])
def creer_comptes_par_defaut(
    db: Session = Depends(get_db),
    _: Utilisateur = Depends(admin_seul),
):
    """Crée un compte pour chaque étudiant et enseignant qui n'en a pas.

    L'identifiant reprend le prénom, le mot de passe est le matricule.
    L'opération est idempotente : les personnes déjà rattachées à un compte
    sont ignorées, de même que les enseignants dépourvus de matricule.
    """
    identifiants_utilises = {
        identifiant for (identifiant,) in db.query(Utilisateur.identifiant).all()
    }
    comptes = []
    ignores = []

    etudiants = (
        db.query(Etudiant)
        .filter(Etudiant.id.notin_(db.query(Utilisateur.etudiant_id).filter(
            Utilisateur.etudiant_id.isnot(None)
        )))
        .order_by(Etudiant.prenom, Etudiant.nom, Etudiant.id)
        .all()
    )
    for etudiant in etudiants:
        identifiant = _identifiant_disponible(db, etudiant.prenom, identifiants_utilises)
        db.add(
            Utilisateur(
                identifiant=identifiant,
                mot_de_passe_hash=hacher_mot_de_passe(etudiant.matricule),
                nom_complet=etudiant.nom_complet,
                role="lecteur",
                actif=True,
                etudiant_id=etudiant.id,
            )
        )
        comptes.append(
            {
                "identifiant": identifiant,
                "nom_complet": etudiant.nom_complet,
                "role": "lecteur",
                "mot_de_passe": etudiant.matricule,
            }
        )

    enseignants = (
        db.query(Enseignant)
        .filter(Enseignant.id.notin_(db.query(Utilisateur.enseignant_id).filter(
            Utilisateur.enseignant_id.isnot(None)
        )))
        .order_by(Enseignant.prenom, Enseignant.nom, Enseignant.id)
        .all()
    )
    for enseignant in enseignants:
        if not (enseignant.matricule or "").strip():
            ignores.append(
                {
                    "nom_complet": f"{enseignant.prenom} {enseignant.nom}".strip(),
                    "motif": "Aucun matricule renseigné",
                }
            )
            continue
        identifiant = _identifiant_disponible(
            db, enseignant.prenom, identifiants_utilises
        )
        db.add(
            Utilisateur(
                identifiant=identifiant,
                mot_de_passe_hash=hacher_mot_de_passe(enseignant.matricule),
                nom_complet=f"{enseignant.prenom} {enseignant.nom}".strip(),
                role="enseignant",
                actif=True,
                enseignant_id=enseignant.id,
            )
        )
        comptes.append(
            {
                "identifiant": identifiant,
                "nom_complet": f"{enseignant.prenom} {enseignant.nom}".strip(),
                "role": "enseignant",
                "mot_de_passe": enseignant.matricule,
            }
        )

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)

    etudiants_crees = sum(1 for compte in comptes if compte["role"] == "lecteur")
    enseignants_crees = len(comptes) - etudiants_crees
    return {
        "ok": True,
        "etudiants_crees": etudiants_crees,
        "enseignants_crees": enseignants_crees,
        "total_crees": len(comptes),
        "ignores": ignores,
        "comptes": comptes,
        "message": (
            f"{len(comptes)} compte(s) créé(s) : {etudiants_crees} étudiant(s), "
            f"{enseignants_crees} enseignant(s)."
        ),
    }


@router.put("/utilisateurs/{element_id}", response_model=UtilisateurOut, tags=["utilisateurs"])
def modifier_utilisateur(
    element_id: int,
    payload: UtilisateurUpdate,
    db: Session = Depends(get_db),
    courant: Utilisateur = Depends(admin_seul),
):
    element = db.get(Utilisateur, element_id)
    if not element:
        raise HTTPException(404, "Utilisateur introuvable")
    donnees = payload.model_dump(exclude_unset=True)
    if "role" in donnees and donnees["role"] not in ROLES:
        raise HTTPException(400, "Rôle invalide")
    if "mot_de_passe" in donnees:
        mot_de_passe = donnees.pop("mot_de_passe")
        if mot_de_passe:
            element.mot_de_passe_hash = hacher_mot_de_passe(mot_de_passe)
    if element.id == courant.id and donnees.get("actif") is False:
        raise HTTPException(400, "Vous ne pouvez pas désactiver votre propre compte")
    for cle, valeur in donnees.items():
        setattr(element, cle, valeur)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        _erreur_integrite(exc)
    db.refresh(element)
    return element


@router.delete("/utilisateurs/{element_id}", tags=["utilisateurs"])
def supprimer_utilisateur(
    element_id: int,
    db: Session = Depends(get_db),
    courant: Utilisateur = Depends(admin_seul),
):
    if element_id == courant.id:
        raise HTTPException(400, "Vous ne pouvez pas supprimer votre propre compte")
    element = db.get(Utilisateur, element_id)
    if not element:
        raise HTTPException(404, "Utilisateur introuvable")
    db.delete(element)
    db.commit()
    return {"ok": True, "message": "Utilisateur supprimé"}
