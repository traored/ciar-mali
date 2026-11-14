import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/pages/shell_page.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:provider/provider.dart';

/// Vérifie la navigation mobile : le menu latéral doit s'ouvrir et se fermer
/// sans dépendre du `Scaffold.of(context)` (source d'erreur en production).
void main() {
  Future<AppState> preparerApplication(
    WidgetTester tester, {
    Size taille = const Size(900, 700),
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = AppState();
    app.demarrage = false;
    app.utilisateur = Utilisateur(
      id: 1,
      identifiant: 'admin',
      nomComplet: 'Admin Test',
      role: 'admin',
      actif: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: ShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return app;
  }

  testWidgets('le menu mobile s’ouvre, navigue et se ferme', (tester) async {
    await preparerApplication(tester);

    expect(find.text('Emploi du temps'), findsNothing);
    expect(find.byTooltip('Menu'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Emploi du temps'), findsOneWidget);
    expect(find.text('Séances'), findsOneWidget);
    expect(find.text('Heures enseignants'), findsOneWidget);
    expect(find.text('Structure'), findsOneWidget);
    expect(find.text('Programme'), findsOneWidget);
    expect(find.text('Ressources'), findsOneWidget);
    expect(find.text('Utilisateurs & rôles'), findsOneWidget);

    await tester.tap(find.text('Emploi du temps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Le panneau se referme après la navigation.
    expect(find.text('Utilisateurs & rôles'), findsNothing);
  });

  testWidgets('le sous-menu Gestion des notes se déplie et se replie', (tester) async {
    await preparerApplication(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // La section des notes est en bas du menu : on la fait défiler jusqu'à l'écran.
    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Gestion des notes'), findsOneWidget);
    expect(find.text('Étudiants'), findsNothing);

    await tester.tap(find.text('Gestion des notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Étudiants'), findsOneWidget);

    await tester.tap(find.text('Gestion des notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Étudiants'), findsNothing);
  });

  testWidgets('le bouton de fermeture masque le menu', (tester) async {
    await preparerApplication(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Fermer le menu'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer le menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Emploi du temps'), findsNothing);
  });

  testWidgets('un clic sur le voile ferme le menu', (tester) async {
    await preparerApplication(tester);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Emploi du temps'), findsOneWidget);

    // Le voile couvre la partie droite de l'écran, à côté du panneau.
    await tester.tapAt(const Offset(700, 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Emploi du temps'), findsNothing);
  });

  testWidgets('la déconnexion reste accessible sur un téléphone', (tester) async {
    await preparerApplication(tester, taille: const Size(360, 640));

    // La barre supérieure ne déborde pas et propose directement la déconnexion.
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Se déconnecter'), findsOneWidget);

    // Le menu latéral expose lui aussi la déconnexion.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Se déconnecter'), findsNWidgets(2));
  });
}
