import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/crud/configs.dart';
import 'package:gestion_edt/crud/generic_crud_page.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:provider/provider.dart';

/// Vérifie que la ressource Enseignant reste modifiable : la colonne d'actions
/// est visible en tête de tableau et le crayon ouvre un formulaire pré-rempli.
void main() {
  AppState preparerApplication() {
    final app = AppState();
    app.demarrage = false;
    app.utilisateur = Utilisateur(
      id: 1,
      identifiant: 'admin',
      nomComplet: 'Admin Test',
      role: 'admin',
      actif: true,
    );
    app.departements = [
      {'id': 4, 'code': 'LANG', 'nom': 'Langues et Communication'},
    ];
    app.enseignants = [
      {
        'id': 4,
        'prenom': 'Mireille',
        'nom': 'Abena',
        'email': 'mireille.abena@univ.cm',
        'telephone': '+237 6 90 00 00 00',
        'date_naissance': '1986-06-15',
        'lieu_naissance': 'Ebolowa',
        'statut': 'Permanent',
        'matricule': 'ENS-004',
        'grade': 'Maître de Conférences',
        'departement_id': 4,
        'heures_max': 160,
        'actif': true,
        'nom_complet': 'Mireille Abena',
        'nom_affichage': 'Dr Mireille Abena',
        'titre': 'Dr',
        'departement_nom': 'Langues et Communication',
      },
    ];
    return app;
  }

  Future<void> afficherPage(WidgetTester tester, AppState app) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          home: Scaffold(
            body: GenericCrudPage(config: configEnseignants),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la colonne Actions est placée en tête du tableau', (tester) async {
    final app = preparerApplication();
    await afficherPage(tester, app);

    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.columns.first.label, isA<Text>());
    expect((table.columns.first.label as Text).data, 'ACTIONS');
    expect(find.byTooltip('Modifier'), findsOneWidget);
    expect(find.byTooltip('Supprimer'), findsOneWidget);
  });

  testWidgets('le crayon ouvre le formulaire de modification pré-rempli',
      (tester) async {
    final app = preparerApplication();
    await afficherPage(tester, app);

    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier enseignant'), findsOneWidget);
    final dialogue = find.byType(AlertDialog);
    Finder dansLeDialogue(String texte) =>
        find.descendant(of: dialogue, matching: find.text(texte));
    expect(dansLeDialogue('Mireille'), findsOneWidget);
    expect(dansLeDialogue('Abena'), findsOneWidget);
    expect(dansLeDialogue('ENS-004'), findsOneWidget);
    expect(dansLeDialogue('Ebolowa'), findsOneWidget);
    expect(dansLeDialogue('15/06/1986'), findsOneWidget);
    expect(dansLeDialogue('Maître de Conférences (Dr)'), findsOneWidget);
  });
}
