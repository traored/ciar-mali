import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/app_state.dart';

/// Choix du semestre d'un niveau : chaque niveau a son propre semestre
/// (Licence 3 → Semestre 5, Master 1 → « Master 1 - Semestre 1 », …). Le
/// semestre de l'année universitaire courante est privilégié, puis celui qui
/// contient la date du jour.
void main() {
  final maintenant = DateTime.now();

  String date(DateTime valeur) =>
      '${valeur.year.toString().padLeft(4, '0')}-'
      '${valeur.month.toString().padLeft(2, '0')}-'
      '${valeur.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> semestre({
    required int id,
    required String nom,
    required String annee,
    DateTime? debut,
    DateTime? fin,
  }) {
    final anneeDebut = int.parse(annee.split('-').first);
    return {
      'id': id,
      'nom': nom,
      'annee': annee,
      'actif': true,
      'date_debut': date(debut ?? DateTime(anneeDebut, 10, 12)),
      'date_fin': date(fin ?? DateTime(anneeDebut + 1, 2, 13)),
    };
  }

  AppState appVide() {
    final app = AppState();
    app.demarrage = false;
    return app;
  }

  String anneePrecedente(String annee) {
    final debut = int.parse(annee.split('-').first) - 1;
    return '$debut-${debut + 1}';
  }

  test('un niveau avec UE ouvre le semestre de l’année courante', () {
    final app = appVide();
    final courante = app.anneeCourante;
    final passee = anneePrecedente(courante);
    app.niveaux = [
      {'id': 3, 'nom': 'Licence 3'},
    ];
    app.semestresTous = [
      // Ce semestre de l'année passée contient encore la date du jour : il ne
      // doit pas primer sur l'année courante.
      semestre(
        id: 20,
        nom: 'Semestre 5',
        annee: passee,
        debut: maintenant.subtract(const Duration(days: 20)),
        fin: maintenant.add(const Duration(days: 40)),
      ),
      // Les deux semestres de l'année courante sont à venir.
      semestre(
        id: 10,
        nom: 'Semestre 5',
        annee: courante,
        debut: maintenant.add(const Duration(days: 150)),
        fin: maintenant.add(const Duration(days: 300)),
      ),
      semestre(
        id: 11,
        nom: 'Semestre 6',
        annee: courante,
        debut: maintenant.add(const Duration(days: 330)),
        fin: maintenant.add(const Duration(days: 480)),
      ),
    ];
    app.ues = [
      {'id': 1, 'niveau_id': 3, 'semestre_id': 20},
      {'id': 2, 'niveau_ids': [3], 'semestre_id': 10},
    ];
    expect(app.semestreCourantNiveau(3), 10);
  });

  test('un semestre de l’année courante qui contient la date du jour gagne', () {
    final app = appVide();
    final courante = app.anneeCourante;
    app.niveaux = [
      {'id': 1, 'nom': 'Licence 1'},
    ];
    app.semestresTous = [
      semestre(
        id: 1,
        nom: 'Semestre 1',
        annee: courante,
        debut: maintenant.subtract(const Duration(days: 30)),
        fin: maintenant.add(const Duration(days: 60)),
      ),
      semestre(
        id: 2,
        nom: 'Semestre 2',
        annee: courante,
        debut: maintenant.add(const Duration(days: 90)),
        fin: maintenant.add(const Duration(days: 240)),
      ),
    ];
    app.ues = [
      {'id': 1, 'niveau_id': 1, 'semestre_id': 1},
      {'id': 2, 'niveau_id': 1, 'semestre_id': 2},
    ];
    expect(app.semestreCourantNiveau(1), 1);
  });

  test('un niveau sans UE est reconnu par le nom de son semestre', () {
    final app = appVide();
    final courante = app.anneeCourante;
    app.niveaux = [
      {'id': 12, 'nom': 'Master 1'},
    ];
    app.semestresTous = [
      semestre(
        id: 30,
        nom: 'Master 1 - Semestre 1',
        annee: courante,
        debut: maintenant.subtract(const Duration(days: 30)),
        fin: maintenant.add(const Duration(days: 60)),
      ),
      semestre(
        id: 31,
        nom: 'Master 1 - Semestre 2',
        annee: courante,
        debut: maintenant.add(const Duration(days: 90)),
        fin: maintenant.add(const Duration(days: 240)),
      ),
      // Même période, mais autre niveau : ne doit jamais être retenu.
      semestre(
        id: 32,
        nom: 'Master 2 - Semestre 1',
        annee: courante,
        debut: maintenant.subtract(const Duration(days: 30)),
        fin: maintenant.add(const Duration(days: 60)),
      ),
    ];
    expect(app.semestreCourantNiveau(12), 30);
  });

  test('un niveau non reconnu retombe sur l’année courante', () {
    final app = appVide();
    final courante = app.anneeCourante;
    final passee = anneePrecedente(courante);
    app.niveaux = [
      {'id': 14, 'nom': "2e année cycle d'ingénieur"},
    ];
    app.semestresTous = [
      semestre(
        id: 50,
        nom: 'Semestre 1',
        annee: passee,
        debut: maintenant.subtract(const Duration(days: 400)),
        fin: maintenant.subtract(const Duration(days: 200)),
      ),
      semestre(
        id: 40,
        nom: 'Semestre 1',
        annee: courante,
        debut: maintenant.subtract(const Duration(days: 30)),
        fin: maintenant.add(const Duration(days: 60)),
      ),
      semestre(
        id: 41,
        nom: 'Semestre 2',
        annee: courante,
        debut: maintenant.add(const Duration(days: 90)),
        fin: maintenant.add(const Duration(days: 240)),
      ),
    ];
    expect(app.semestreCourantNiveau(14), 40);
  });

  test('sans aucun semestre, aucun semestre courant n’est proposé', () {
    final app = appVide();
    app.niveaux = [
      {'id': 3, 'nom': 'Licence 3'},
    ];
    expect(app.semestreCourantNiveau(3), isNull);
  });
}
