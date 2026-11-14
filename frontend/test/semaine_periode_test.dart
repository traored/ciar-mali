import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/app_state.dart';

/// Vérifie le calcul des périodes de semaine affichées dans l'application.
void main() {
  AppState preparer() {
    final app = AppState();
    app.semestres = [
      {
        'id': 3,
        'nom': 'Semestre 1',
        'annee': '2026-2027',
        'date_debut': '2026-10-12',
        'date_fin': '2027-02-13',
        'semaines': 16,
        'actif': true,
      },
    ];
    app.semestreId = 3;
    return app;
  }

  test('les périodes suivent les semaines du lundi au samedi', () {
    final app = preparer();
    expect(app.libelleSemaine(1), 'Semaine 1 · du 12 au 17 octobre 2026');
    expect(app.libelleSemaine(2), 'Semaine 2 · du 19 au 24 octobre 2026');
    expect(app.libelleSemaine(3), 'Semaine 3 · du 26 au 31 octobre 2026');
    expect(app.libelleSemaine(4), 'Semaine 4 · du 2 au 7 novembre 2026');
    expect(app.periodeSemaine(1, court: true), '12–17 oct. 2026');
  });

  test('les changements de mois et d’année sont gérés', () {
    final app = preparer();
    expect(app.periodeSemaine(12), 'du 28 décembre 2026 au 2 janvier 2027');
    expect(app.periodeSemaine(12, court: true), '28 déc. 2026 – 2 janv. 2027');
    expect(app.periodeSemaine(16), 'du 25 au 30 janvier 2027');
  });

  test('un autre semestre peut être ciblé explicitement', () {
    final app = preparer();
    app.semestres = [
      ...app.semestres,
      {
        'id': 4,
        'nom': 'Semestre 2',
        'annee': '2026-2027',
        'date_debut': '2027-02-22',
        'date_fin': '2027-06-12',
        'semaines': 14,
        'actif': false,
      },
    ];
    expect(app.nombreSemainesDe(4), 14);
    expect(app.periodeSemaine(1, semestreId: 4), 'du 22 au 27 février 2027');
  });
}
