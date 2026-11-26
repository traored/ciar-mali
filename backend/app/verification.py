"""Signature et vérification des relevés de notes (QR codes).

Le QR code contient les informations essentielles du relevé et une signature
HMAC calculée avec une sous-clé dérivée de SECRET_KEY. L'endpoint public
`/api/notes/verification` vérifie cette signature sans accéder à la base : le
relevé reste authentifiable même si les notes sont modifiées plus tard.

Le format v2 (liste compacte) remplace le format v1 (JSON) pour réduire le
nombre de modules du QR et le rendre lisible sans zoom. Les codes v1 déjà
émis restent acceptés.
"""
import base64
import binascii
import hashlib
import hmac
import json
from typing import Any

from .config import SECRET_KEY

VERSION = "v2"
VERSION_V1 = "v1"
# La clé JWT n'est jamais utilisée directement : une sous-clé dédiée limite
# l'impact d'une fuite d'un code signé.
_CLE = hashlib.sha256(f"ciar-mali:releve:{SECRET_KEY}".encode("utf-8")).digest()
_CHAMPS = ("m", "n", "s", "a", "e", "v", "c", "t", "d", "g")
_SEPARATEUR = "|"


def _encoder(bruts: bytes) -> str:
    return base64.urlsafe_b64encode(bruts).rstrip(b"=").decode("ascii")


def _decoder(texte: str) -> bytes:
    return base64.urlsafe_b64decode(texte + "=" * (-len(texte) % 4))


def _signature(charge: str, version: str = VERSION) -> str:
    message = f"{version}.{charge}".encode("utf-8")
    empreinte = hmac.new(_CLE, message, hashlib.sha256).digest()[:18]
    return _encoder(empreinte)


def _valeurs_normalisees(donnees: dict[str, Any]) -> dict[str, Any]:
    propres: dict[str, Any] = {}
    for cle in _CHAMPS:
        valeur = donnees.get(cle)
        if cle in ("e", "c", "t"):
            propres[cle] = int(valeur or 0)
        elif cle == "v":
            propres[cle] = round(float(valeur or 0), 2)
        else:
            propres[cle] = str(valeur or "").strip()
    return propres


def _serialiser(donnees: dict[str, Any]) -> str:
    """Liste compacte séparée par `|` (échappement des `|` et `\\`)."""
    parties = []
    for cle in _CHAMPS:
        valeur = donnees[cle]
        if cle in ("e", "c", "t"):
            texte = str(valeur)
        elif cle == "v":
            texte = f"{valeur:.2f}"
        else:
            texte = valeur
        parties.append(texte.replace("\\", "\\\\").replace(_SEPARATEUR, "\\" + _SEPARATEUR))
    return _SEPARATEUR.join(parties)


def _deserialiser(texte: str) -> dict[str, Any]:
    parties: list[str] = []
    courant: list[str] = []
    echappe = False
    for caractere in texte:
        if echappe:
            courant.append(caractere)
            echappe = False
        elif caractere == "\\":
            echappe = True
        elif caractere == _SEPARATEUR:
            parties.append("".join(courant))
            courant = []
        else:
            courant.append(caractere)
    parties.append("".join(courant))
    if len(parties) != len(_CHAMPS):
        raise ValueError("Nombre de champs incorrect")
    donnees: dict[str, Any] = {}
    for cle, valeur in zip(_CHAMPS, parties):
        if cle in ("e", "c", "t"):
            donnees[cle] = int(valeur)
        elif cle == "v":
            donnees[cle] = float(valeur)
        else:
            donnees[cle] = valeur
    return donnees


def construire_code(donnees: dict[str, Any]) -> str:
    """Construit un code signé à partir des données du relevé (format v2)."""
    propres = _valeurs_normalisees(donnees)
    charge = _encoder(_serialiser(propres).encode("utf-8"))
    return f"{VERSION}.{charge}.{_signature(charge)}"


def verifier_code(code: str) -> tuple[bool, dict[str, Any]]:
    """Vérifie la signature d'un code et retourne les données signées.

    Aucune exception ne sort de cette fonction : un code invalide, tronqué ou
    falsifié retourne simplement ``(False, {})``. Les codes v1 restent lisibles.
    """
    try:
        parties = (code or "").strip().split(".")
        if len(parties) != 3:
            return False, {}
        version, charge, signature = parties
        if version not in (VERSION, VERSION_V1):
            return False, {}
        if not hmac.compare_digest(signature, _signature(charge, version)):
            return False, {}
        if version == VERSION_V1:
            donnees = json.loads(_decoder(charge).decode("utf-8"))
            if not isinstance(donnees, dict) or any(cle not in donnees for cle in _CHAMPS):
                return False, {}
            if not all(isinstance(donnees[cle], str) for cle in ("m", "n", "s", "a", "d", "g")):
                return False, {}
            if not all(isinstance(donnees[cle], int) for cle in ("e", "c", "t")):
                return False, {}
            if not isinstance(donnees["v"], (int, float)):
                return False, {}
            return True, donnees
        donnees = _deserialiser(_decoder(charge).decode("utf-8"))
        return True, donnees
    except (ValueError, TypeError, KeyError, UnicodeDecodeError, binascii.Error):
        return False, {}
