import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/state/app_state.dart';

/// L'emploi du temps d'un étudiant s'ouvre sur le niveau de son inscription :
/// les getters doivent retrouver la bonne inscription selon l'année affichée.
void main() {
  AppState appLecteur() {
    final app = AppState();
    app.utilisateur = Utilisateur(
      id: 155,
      identifiant: 'etudiant',
      nomComplet: 'Étudiant Test',
      role: 'lecteur',
      actif: true,
    );
    app.inscriptionsNotes = [
      {'annee': '2025-2026', 'niveau_id': 8, 'groupe_id': 9},
      {'annee': '2026-2027', 'niveau_id': 18, 'groupe_id': 14},
    ];
    return app;
  }

  test('l’inscription est retrouvée pour une année donnée', () {
    final app = appLecteur();
    expect(app.inscriptionEtudiant('2025-2026')?['niveau_id'], 8);
    expect(app.inscriptionEtudiant('2026-2027')?['niveau_id'], 18);
    expect(app.niveauInscription('2025-2026'), 8);
    expect(app.niveauInscription('2026-2027'), 18);
    expect(app.groupeInscription('2025-2026'), 9);
    expect(app.groupeInscription('2026-2027'), 14);
  });

  test('une année inconnue retombe sur l’inscription la plus récente', () {
    final app = appLecteur();
    expect(app.inscriptionEtudiant('2020-2021')?['annee'], '2026-2027');
    expect(app.niveauInscription('2020-2021'), 18);
    expect(app.niveauInscription(), 18);
    expect(app.groupeInscription(), 14);
  });

  test('un utilisateur non étudiant n’a pas d’inscription', () {
    final app = AppState();
    app.utilisateur = Utilisateur(
      id: 1,
      identifiant: 'admin',
      nomComplet: 'Administrateur',
      role: 'admin',
      actif: true,
    );
    app.inscriptionsNotes = [
      {'annee': '2026-2027', 'niveau_id': 18, 'groupe_id': 14},
    ];
    expect(app.inscriptionEtudiant('2026-2027'), isNull);
    expect(app.niveauInscription('2026-2027'), isNull);
    expect(app.groupeInscription('2026-2027'), isNull);
  });
}
