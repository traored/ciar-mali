import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/app_state.dart';

/// Vérifie le filtrage des enseignants et des groupes proposés lors de la
/// création d'une séance, à partir des affectations du module Programme.
void main() {
  AppState preparer() {
    final app = AppState();
    app.enseignants = [
      {'id': 1, 'nom_complet': 'Alice Martin'},
      {'id': 2, 'nom_complet': 'Benoît Durand'},
      {'id': 3, 'nom_complet': 'Chloé Petit'},
    ];
    app.groupes = [
      {'id': 10, 'nom': 'G1', 'niveau_id': 1},
      {'id': 11, 'nom': 'G2', 'niveau_id': 1},
      {'id': 12, 'nom': 'G3', 'niveau_id': 2},
    ];
    app.affectations = [
      {'id': 1, 'enseignant_id': 1, 'ecue_id': 5, 'groupe_id': 10},
      {'id': 2, 'enseignant_id': 1, 'ecue_id': 5, 'groupe_id': 11},
      {'id': 3, 'enseignant_id': 2, 'ecue_id': 6, 'groupe_id': 12},
    ];
    return app;
  }

  test('les enseignants proposés sont ceux affectés à l’ECUE', () {
    final app = preparer();
    expect(app.enseignantsDeECUE(5).map((e) => e['id']), [1]);
    expect(app.enseignantsDeECUE(6).map((e) => e['id']), [2]);
    expect(app.enseignantsDeECUE(99), isEmpty);
  });

  test('les groupes proposés dépendent de l’ECUE et de l’enseignant', () {
    final app = preparer();
    expect(app.groupesDeECUEEnseignant(5, 1).map((g) => g['id']), [10, 11]);
    expect(app.groupesDeECUEEnseignant(6, 2).map((g) => g['id']), [12]);
    expect(app.groupesDeECUEEnseignant(5, 2), isEmpty);
    expect(app.groupesDeECUEEnseignant(null, 1), isEmpty);
  });
}
