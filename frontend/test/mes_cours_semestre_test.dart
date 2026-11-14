import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/pages/mes_cours_page.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:provider/provider.dart';

/// « Mes cours » ouvre par défaut sur les semestres de la période courante
/// (impairs ou pairs) de l'année courante. Le mode « Toutes les années »
/// conserve la présélection du semestre courant, même sans affectation.
void main() {
  final maintenant = DateTime.now();
  final debut = maintenant.month >= 9 ? maintenant.year : maintenant.year - 1;
  final annee = '$debut-${debut + 1}';
  final numero = (maintenant.month >= 9 || maintenant.month <= 1) ? 1 : 2;

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
      {'id': 101, 'nom': 'Semestre $numero', 'annee': annee, 'actif': true},
      {'id': 102, 'nom': 'Semestre 3', 'annee': '2020-2021', 'actif': true},
    ];
    // Périmètre restreint vide : aucune affectation pour cet enseignant.
    app.semestres = [];
    app.affectations = [];
    app.semestreId = null;
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
        child: const MaterialApp(home: Scaffold(body: MesCoursPage())),
      ),
    );
    await stabiliser(tester);
  }

  testWidgets('la période courante est sélectionnée par défaut', (
    tester,
  ) async {
    await afficherPage(tester, construireApp());

    final libelle = numero == 1
        ? 'Impairs · 1, 3, 5 · $annee'
        : 'Pairs · 2, 4, 6 · $annee';
    expect(find.text(libelle), findsOneWidget);
    // En mode parité, les cours de plusieurs semestres sont regroupés :
    // le sélecteur d'un semestre unique n'est pas affiché.
    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets('la page attend la fin du chargement des référentiels', (
    tester,
  ) async {
    final app = construireApp();
    // À la connexion, `chargerTout` notifie avec `chargementDonnees = true`
    // avant d'avoir rempli les référentiels : la page ne doit pas se figer.
    app.chargementDonnees = true;
    await afficherPage(tester, app);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Aucun cours'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);

    // Fin du chargement : la page s'initialise et lance ses propres requêtes.
    // Dans l'environnement de test, l'appel réseau échoue et propose de
    // réessayer : c'est la preuve que le chargement a bien démarré.
    app.chargementDonnees = false;
    app.notifyListeners();
    await stabiliser(tester);

    expect(find.textContaining('Aucun cours'), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets(
    'le semestre courant est présélectionné dans « Toutes les années »',
    (tester) async {
      await afficherPage(tester, construireApp());

      await tester.tap(find.byType(DropdownButton<ModePeriode>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Toutes les années').last);
      await stabiliser(tester);

      final liste = tester.widget<DropdownButton<int>>(
        find.byType(DropdownButton<int>),
      );
      expect(liste.value, 101);
      expect(find.text('Semestre $numero · $annee'), findsOneWidget);
    },
  );
}
