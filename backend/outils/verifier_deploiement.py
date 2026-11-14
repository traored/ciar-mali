"""Vérifie une instance déployée de l'application.

    python -m outils.verifier_deploiement --url https://ciar-mali.onrender.com

Contrôle la santé de l'API, la connexion, la liste des diplômés et la
génération d'un PDF. Le premier appel peut prendre une minute si le service
gratuit est en veille.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request


def appel(base: str, chemin: str, methode: str = "GET", corps=None, jeton=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    requete = urllib.request.Request(base.rstrip("/") + chemin, data=donnees, method=methode)
    if corps is not None:
        requete.add_header("Content-Type", "application/json")
    if jeton:
        requete.add_header("Authorization", f"Bearer {jeton}")
    with urllib.request.urlopen(requete, timeout=180) as reponse:
        contenu = reponse.read()
        try:
            return reponse.status, json.loads(contenu.decode("utf-8"))
        except ValueError:
            return reponse.status, contenu


def main() -> int:
    analyseur = argparse.ArgumentParser(description=__doc__)
    analyseur.add_argument("--url", required=True, help="URL publique du service")
    analyseur.add_argument("--identifiant", default="admin")
    analyseur.add_argument("--mot-de-passe", default="admin123")
    analyseur.add_argument("--annee", default="2026-2027")
    options = analyseur.parse_args()

    base = options.url.rstrip("/")
    echecs = 0

    def verifier(nom: str, condition: bool, detail: str = "") -> None:
        nonlocal echecs
        if condition:
            print(f"  ok  {nom}")
        else:
            echecs += 1
            print(f"  KO  {nom} {detail}")

    print(f"Vérification de {base}")

    try:
        statut, corps = appel(base, "/api/sante")
        verifier("/api/sante", statut == 200 and corps.get("statut") == "ok", str(corps)[:120])
    except urllib.error.URLError as erreur:
        print(f"  KO  service injoignable : {erreur}")
        return 1

    try:
        statut, corps = appel(
            base,
            "/api/auth/connexion",
            "POST",
            {"identifiant": options.identifiant, "mot_de_passe": options.mot_de_passe},
        )
    except urllib.error.HTTPError as erreur:
        print(f"  KO  connexion refusée ({erreur.code}) : identifiants incorrects ?")
        return 1

    jeton = corps.get("access_token")
    verifier(
        "connexion",
        statut == 200 and bool(jeton),
        f"rôle={corps.get('utilisateur', {}).get('role')}",
    )
    if not jeton:
        return 1

    try:
        statut, diplomes = appel(base, f"/api/notes/documents/diplomes?annee={options.annee}", jeton=jeton)
        verifier(
            "diplômés éligibles",
            statut == 200 and isinstance(diplomes, list),
            f"{len(diplomes) if isinstance(diplomes, list) else '?'} étudiant(s)",
        )
        if isinstance(diplomes, list) and diplomes:
            identifiant = diplomes[0]["etudiant_id"]
            cycle = diplomes[0]["cycle"]
            statut, pdf = appel(
                base,
                f"/api/notes/documents/diplome/{identifiant}?cycle={cycle}",
                jeton=jeton,
            )
            verifier("PDF d'attestation", statut == 200 and pdf[:5] == b"%PDF-", f"{len(pdf)} octets")
    except urllib.error.HTTPError as erreur:
        verifier("documents", False, f"HTTP {erreur.code}")

    try:
        statut, _ = appel(base, "/app/")
        verifier("interface /app/", statut == 200)
    except urllib.error.HTTPError as erreur:
        verifier("interface /app/", False, f"HTTP {erreur.code}")

    print("\nDéploiement conforme." if echecs == 0 else f"\n{echecs} contrôle(s) en échec.")
    return 0 if echecs == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
