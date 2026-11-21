import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/pages/timetable_page.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:provider/provider.dart';

/// Un étudiant ouvre l'emploi du temps de sa classe : le filtre « Niveau »
/// est présélectionné sur le niveau de son inscription pour l'année du
/// semestre affiché, sans devoir le choisir lui-même.
void main() {
  AppState construireApp() {
    final app = AppState();
    app.demarrage = false;
    app.utilisateur = Utilisateur(
      id: 155,
      identifiant: 'etudiant',
      nomComplet: 'Étudiant Test',
      role: 'lecteur',
      actif: true,
    );
    app.niveaux = [
      {'id': 8, 'nom': 'MPSI 1', 'filiere_code': 'MPSI', 'filiere_id': 7},
      {'id': 18, 'nom': 'MPSI 2', 'filiere_code': 'MPSI', 'filiere_id': 7},
    ];
    app.groupes = [
      {'id': 9, 'nom': 'MPSI-1-G1', 'niveau_id': 8, 'filiere_code': 'MPSI'},
      {'id': 14, 'nom': 'G1', 'niveau_id': 18, 'filiere_code': 'MPSI'},
    ];
    app.inscriptionsNotes = [
      {
        'id': 203,
        'etudiant_id': 113,
        'annee': '2025-2026',
        'niveau_id': 8,
        'groupe_id': 9,
      },
      {
        'id': 163,
        'etudiant_id': 113,
        'annee': '2026-2027',
        'niveau_id': 18,
        'groupe_id': 14,
      },
    ];
    app.semestres = [
      {
        'id': 3,
        'nom': 'Semestre 1',
        'annee': '2025-2026',
        'actif': false,
        'semaines': 16,
        'date_debut': '2025-10-13',
      },
      {
        'id': 26,
        'nom': 'Semestre 3',
        'annee': '2026-2027',
        'actif': true,
        'semaines': 16,
        'date_debut': '2026-10-12',
      },
    ];
    app.semestresTous = List.of(app.semestres);
    app.semestreId = 26;
    app.semaine = 5;
    app.semestresAvecSeances = {26};
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

  testWidgets('le niveau de l’inscription est présélectionné', (tester) async {
    await afficherPage(tester, construireApp());

    expect(find.text('Niveau'), findsOneWidget);
    // Le sélecteur affiche le niveau de l'inscription 2026-2027.
    expect(find.text('MPSI 2 · MPSI'), findsOneWidget);
    expect(find.text('MPSI 1 · MPSI'), findsNothing);
  });

  testWidgets('le niveau suit l’année du semestre affiché', (tester) async {
    final app = construireApp();
    await afficherPage(tester, app);
    expect(find.text('MPSI 2 · MPSI'), findsOneWidget);

    // L'étudiant bascule sur un semestre de l'année précédente : le niveau
    // par défaut devient celui de l'inscription 2025-2026.
    app.semestreId = 3;
    app.notifyListeners();
    await stabiliser(tester);

    expect(find.text('MPSI 1 · MPSI'), findsOneWidget);
    expect(find.text('MPSI 2 · MPSI'), findsNothing);
  });

  testWidgets('la grille se charge quand les données arrivent après coup', (
    tester,
  ) async {
    final complet = construireApp();
    final app = AppState();
    app.demarrage = false;
    app.utilisateur = complet.utilisateur;
    // La page est construite avant la fin du chargement : aucun référentiel.
    app.semestreId = null;
    app.semaine = 1;
    app.affectations = [];
    app.creneaux = [];

    await afficherPage(tester, app);
    expect(find.text('MPSI 2 · MPSI'), findsNothing);

    // Fin du chargement : les référentiels et le semestre courant arrivent.
    app.niveaux = complet.niveaux;
    app.groupes = complet.groupes;
    app.inscriptionsNotes = complet.inscriptionsNotes;
    app.semestres = complet.semestres;
    app.semestresTous = complet.semestresTous;
    app.semestreId = 26;
    app.semaine = 5;
    app.notifyListeners();
    await stabiliser(tester);

    expect(find.text('MPSI 2 · MPSI'), findsOneWidget);
  });
}
