import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/pages/timetable_page.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:provider/provider.dart';

/// L'emploi du temps d'un enseignant regroupe par défaut les semestres de la
/// parité en cours (impairs ou pairs) de l'année universitaire courante.
void main() {
  final maintenant = DateTime.now();
  final debut = maintenant.month >= 9 ? maintenant.year : maintenant.year - 1;
  final annee = '$debut-${debut + 1}';
  final impair = maintenant.month >= 9 || maintenant.month <= 1;

  AppState construireApp() {
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
    app.semestresTous = [
      {
        'id': 101,
        'nom': 'Semestre 1',
        'annee': annee,
        'actif': true,
        'semaines': 12,
      },
      {
        'id': 102,
        'nom': 'Semestre 2',
        'annee': annee,
        'actif': true,
        'semaines': 12,
      },
      {
        'id': 103,
        'nom': 'Semestre 3',
        'annee': annee,
        'actif': true,
        'semaines': 12,
      },
      {
        'id': 104,
        'nom': 'Semestre 1',
        'annee': '2020-2021',
        'actif': true,
        'semaines': 12,
      },
    ];
    app.semestres = [app.semestresTous[impair ? 0 : 1]];
    app.semestreId = impair ? 101 : 102;
    app.semaine = 1;
    app.affectations = [];
    app.creneaux = [];
    return app;
  }

  Future<void> stabiliser(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> afficherPage(WidgetTester tester, AppState app) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: Scaffold(body: TimetablePage())),
      ),
    );
    await stabiliser(tester);
  }

  testWidgets('la parité en cours est sélectionnée par défaut', (tester) async {
    await afficherPage(tester, construireApp());

    final parite = impair ? 'Semestres impairs' : 'Semestres pairs';
    expect(find.text('Période'), findsOneWidget);
    // Le sélecteur porte l'année universitaire courante.
    expect(find.text('$parite $annee'), findsOneWidget);
    expect(find.textContaining('$parite · $annee'), findsOneWidget);
  });

  testWidgets('le sélecteur permet de basculer vers l’autre parité', (
    tester,
  ) async {
    await afficherPage(tester, construireApp());

    final actuel = impair ? 'Semestres impairs' : 'Semestres pairs';
    final autre = impair ? 'Semestres pairs' : 'Semestres impairs';
    await tester.tap(find.text('$actuel $annee'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('$autre $annee').last);
    await stabiliser(tester);

    expect(find.textContaining('$autre · $annee'), findsOneWidget);
  });
}
