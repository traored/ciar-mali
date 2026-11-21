import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les filtres année/période de l'en-tête et de la page « Heures » sont
/// partagés : un numéro sélectionne un semestre concret, une parité conserve
/// le dernier semestre précis, et un changement d'année suit le même numéro.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Map<String, dynamic> semestre(
    int id,
    String nom,
    String annee, {
    bool actif = true,
  }) {
    return {
      'id': id,
      'nom': nom,
      'annee': annee,
      'actif': actif,
      'semaines': 12,
    };
  }

  AppState construire() {
    final app = AppState();
    app.demarrage = false;
    app.semestres = [
      semestre(10, 'Semestre 5', '2026-2027'),
      semestre(11, 'Semestre 6', '2026-2027'),
      semestre(12, 'Semestre 7', '2026-2027', actif: false),
      semestre(20, 'Semestre 5', '2025-2026'),
      semestre(21, 'Semestre 6', '2025-2026'),
      semestre(30, 'Master 1 - Semestre 5', '2026-2027', actif: false),
    ];
    app.semestresTous = List.of(app.semestres);
    app.semestreId = 10;
    return app;
  }

  test('les filtres suivent par défaut le semestre sélectionné', () {
    final app = construire();
    expect(app.anneeFiltre, '2026-2027');
    expect(app.periodeFiltre, 'impairs');
    app.semestreId = 11;
    expect(app.periodeFiltre, 'pairs');
  });

  test('les années proposées sont triées et contiennent le filtre', () {
    final app = construire();
    expect(app.anneesFiltre, ['2026-2027', '2025-2026']);
  });

  test(
    'un numéro retrouve le semestre de l’année, en préférant le courant',
    () {
      final app = construire();
      expect(app.semestreIdParNumero(5, annee: '2026-2027'), 10);
      app.semestreId = 30;
      expect(app.semestreIdParNumero(5, annee: '2026-2027'), 30);
      // Sans semestre courant, le premier semestre actif, sinon le premier.
      app.semestreId = 11;
      app.semestres = app.semestres
          .map((s) => {...s, 'actif': s['id'] == 30})
          .toList();
      expect(app.semestreIdParNumero(5, annee: '2026-2027'), 30);
      app.semestres = app.semestres.map((s) => {...s, 'actif': false}).toList();
      expect(app.semestreIdParNumero(5, annee: '2026-2027'), 10);
    },
  );

  test('un numéro absent de l’année ne retourne rien', () {
    final app = construire();
    expect(app.semestreIdParNumero(9, annee: '2026-2027'), isNull);
    expect(app.semestreIdParPeriode('pairs', annee: '2030-2031'), isNull);
  });

  test('choisir un numéro sélectionne le semestre concret', () async {
    final app = construire();
    await app.definirFiltres(periode: '7');
    expect(app.periodeFiltre, '7');
    expect(app.semestreId, 12);
    expect(app.anneeFiltre, '2026-2027');
  });

  test('choisir une parité conserve le dernier semestre précis', () async {
    final app = construire();
    app.semestreId = 11;
    await app.definirFiltres(periode: 'impairs');
    expect(app.periodeFiltre, 'impairs');
    expect(app.semestreId, 11);
  });

  test('changer d’année suit le même numéro de semestre', () async {
    final app = construire();
    await app.definirFiltres(annee: '2025-2026');
    expect(app.anneeFiltre, '2025-2026');
    expect(app.semestreId, 20);
  });

  test('changer d’année sans le même numéro retombe sur la parité', () async {
    final app = construire();
    app.semestres = [
      semestre(12, 'Semestre 7', '2026-2027'),
      semestre(23, 'Semestre 3', '2025-2026'),
      semestre(24, 'Semestre 4', '2025-2026'),
    ];
    app.semestresTous = List.of(app.semestres);
    app.semestreId = 12;
    await app.definirFiltres(annee: '2025-2026');
    expect(app.anneeFiltre, '2025-2026');
    expect(app.semestreId, 23);
  });

  test('sélectionner un semestre aligne les filtres sur son année', () async {
    final app = construire();
    await app.selectionnerSemestre(21);
    expect(app.anneeFiltre, '2025-2026');
    expect(app.periodeFiltre, 'pairs');
  });
}
