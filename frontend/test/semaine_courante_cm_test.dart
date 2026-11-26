import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/app_state.dart';

/// Vérifie la semaine sélectionnée à l'ouverture de l'application et la
/// prise en compte des CM mutualisés lors de la création d'une séance.
void main() {
  /// Semestre dont la semaine 5 contient la date du jour.
  AppState preparer() {
    final aujourdhui = DateTime.now();
    final debut = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day)
        .subtract(const Duration(days: 28));
    final app = AppState();
    app.semestres = [
      {
        'id': 3,
        'nom': 'Semestre 1',
        'annee': '2026-2027',
        'date_debut':
            '${debut.year.toString().padLeft(4, '0')}-${debut.month.toString().padLeft(2, '0')}-${debut.day.toString().padLeft(2, '0')}',
        'date_fin': '2027-02-13',
        'semaines': 16,
        'actif': true,
      },
    ];
    app.semestreId = 3;
    return app;
  }

  test('la semaine courante est retenue lorsqu’elle contient des séances', () {
    final app = preparer();
    app.semainesAvecSeances = {4, 5, 6};
    expect(app.semainePourDate(DateTime.now()), 5);
    expect(app.semaineParDefaut(), 5);
  });

  test('sinon la semaine la plus proche disposant de séances est choisie', () {
    final app = preparer();
    app.semainesAvecSeances = {2, 7};
    expect(app.semaineParDefaut(), 7);
    app.semainesAvecSeances = {1, 2, 3};
    expect(app.semaineParDefaut(), 3);
  });

  test('sans séance connue, la semaine de la date du jour est conservée', () {
    final app = preparer();
    expect(app.semaineParDefaut(), 5);
  });

  test('le semestre contenant la date du jour est privilégié', () {
    final aujourdhui = DateTime.now();
    String iso(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final app = AppState();
    app.semestres = [
      {
        'id': 1,
        'nom': 'Semestre 3',
        'annee': '2025-2026',
        'date_debut': iso(aujourdhui.subtract(const Duration(days: 400))),
        'date_fin': iso(aujourdhui.subtract(const Duration(days: 200))),
        'semaines': 16,
        'actif': true,
      },
      {
        'id': 2,
        'nom': 'Semestre 1',
        'annee': '2026-2027',
        'date_debut': iso(aujourdhui.subtract(const Duration(days: 20))),
        'date_fin': iso(aujourdhui.add(const Duration(days: 90))),
        'semaines': 16,
        'actif': true,
      },
    ];
    expect(app.semestreCourant(), 2);
    expect(app.semestreCourant(), isNot(1));
  });

  test('un CM mutualisé concerne tous les groupes du niveau', () {
    final app = AppState();
    app.groupes = [
      {'id': 9, 'nom': 'MPSI-1-G1', 'niveau_id': 8},
      {'id': 10, 'nom': 'MPSI-1-G2', 'niveau_id': 8},
      {'id': 12, 'nom': 'G3', 'niveau_id': 9},
    ];
    app.affectations = [
      {
        'id': 1,
        'enseignant_id': 29,
        'ecue_id': 22,
        'groupe_id': 9,
        'cm_commun': true,
      },
      {
        'id': 2,
        'enseignant_id': 30,
        'ecue_id': 22,
        'groupe_id': 9,
        'cm_commun': false,
      },
    ];
    expect(app.cmMutualise(22, 29), isTrue);
    expect(app.cmMutualise(22, 30), isFalse);
    expect(app.groupesMutualises(22, 29).map((g) => g['id']), [9, 10]);
    // Sans enseignant précisé, l'affectation mutualisée de l'ECUE suffit.
    expect(app.cmMutualise(22), isTrue);
    expect(app.groupesMutualises(22).map((g) => g['id']), [9, 10]);
  });

  test('un CM mutualisé sans groupe affecté couvre les niveaux de l’UE', () {
    final app = AppState();
    app.groupes = [
      {'id': 10, 'nom': 'G1', 'niveau_id': 1},
      {'id': 11, 'nom': 'G2', 'niveau_id': 1},
      {'id': 12, 'nom': 'G3', 'niveau_id': 2},
    ];
    app.ecues = [
      {'id': 5, 'ue_id': 2, 'code': 'INF101', 'nom': 'Algorithmique'},
    ];
    app.ues = [
      {'id': 2, 'niveau_id': 1, 'niveau_ids': [1]},
    ];
    app.affectations = [
      {
        'id': 3,
        'enseignant_id': 7,
        'ecue_id': 5,
        'groupe_id': null,
        'cm_commun': true,
      },
    ];
    expect(app.cmMutualise(5, 7), isTrue);
    expect(app.groupesMutualises(5, 7).map((g) => g['id']), [10, 11]);
  });

  test('le premier niveau ayant des séances est retenu', () {
    final app = AppState();
    app.niveaux = [
      {'id': 1, 'nom': 'Licence 1'},
      {'id': 2, 'nom': 'Licence 2'},
    ];
    app.groupes = [
      {'id': 10, 'niveau_id': 1},
      {'id': 11, 'niveau_id': 2},
    ];
    // Seul le groupe du niveau 2 a une séance.
    expect(
      app.niveauAvecSeances([
        {'groupe_ids': [11]},
      ]),
      2,
    );
    // Les deux niveaux en ont : l'ordre des filtres tranche.
    expect(
      app.niveauAvecSeances([
        {'groupe_ids': [10]},
        {'groupe_ids': [11]},
      ]),
      1,
    );
    // Aucune séance : aucun niveau imposé.
    expect(app.niveauAvecSeances([]), isNull);
  });
}
