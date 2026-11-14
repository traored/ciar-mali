import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/state/app_state.dart';

/// À la connexion, l'application ouvre le semestre qui contient la date du
/// jour. Un enseignant affecté à l'année courante mais dont les séances ne sont
/// pas encore générées ne doit pas être renvoyé sur une année passée.
void main() {
  final maintenant = DateTime.now();
  final debutCourant = maintenant.subtract(const Duration(days: 30));
  final finCourant = maintenant.add(const Duration(days: 60));
  final debutPasse = DateTime(maintenant.year - 1, 2, 17);
  final finPasse = DateTime(maintenant.year - 1, 6, 28);

  String date(DateTime valeur) =>
      '${valeur.year.toString().padLeft(4, '0')}-'
      '${valeur.month.toString().padLeft(2, '0')}-'
      '${valeur.day.toString().padLeft(2, '0')}';

  AppState construireApp({required Set<int> avecSeances}) {
    final app = AppState();
    app.demarrage = false;
    app.utilisateur = Utilisateur(
      id: 42,
      identifiant: 'enseignant',
      nomComplet: 'Enseignant Test',
      role: 'enseignant',
      actif: true,
      enseignantId: 7,
    );
    app.semestres = [
      {
        'id': 1,
        'nom': 'Semestre 3',
        'annee': '2025-2026',
        'actif': true,
        'date_debut': date(debutPasse),
        'date_fin': date(finPasse),
      },
      {
        'id': 5,
        'nom': 'Semestre 1',
        'annee': '2026-2027',
        'actif': true,
        'date_debut': date(debutCourant),
        'date_fin': date(finCourant),
      },
    ];
    app.semestresAvecSeances = avecSeances;
    return app;
  }

  test('un semestre courant sans séance passe avant une année passée', () {
    final app = construireApp(avecSeances: {1});
    expect(app.semestreCourant(), 5);
  });

  test('un semestre courant avec séances reste prioritaire', () {
    final app = construireApp(avecSeances: {1, 5});
    expect(app.semestreCourant(), 5);
  });

  test('aucun semestre ne contient la date du jour', () {
    final app = construireApp(avecSeances: {1});
    app.semestres = [
      {
        'id': 1,
        'nom': 'Semestre 3',
        'annee': '2025-2026',
        'actif': true,
        'date_debut': date(debutPasse),
        'date_fin': date(finPasse),
      },
    ];
    expect(app.semestreCourant(), isNull);
  });
}
