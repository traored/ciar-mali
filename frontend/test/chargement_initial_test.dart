import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/main.dart';
import 'package:gestion_edt/models/utilisateur.dart';
import 'package:gestion_edt/state/app_state.dart';
import 'package:provider/provider.dart';

/// À la connexion, l'interface attend la fin du premier chargement avant
/// d'afficher la coquille : sans cela, la page « Emploi du temps » se construit
/// avec des référentiels vides et reste vide jusqu'à ce qu'on la recrée.
void main() {
  testWidgets('l’interface attend la fin du premier chargement', (
    tester,
  ) async {
    final app = AppState();
    app.demarrage = false;
    app.utilisateur = Utilisateur(
      id: 155,
      identifiant: 'etudiant',
      nomComplet: 'Étudiant Test',
      role: 'lecteur',
      actif: true,
    );
    app.chargementDonnees = true;
    app.semestreId = null;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const CiarMaliApp(),
      ),
    );
    await tester.pump();

    // Écran de chargement : la coquille n'est pas encore affichée.
    expect(
      find.text('Gestion des emplois du temps universitaires'),
      findsOneWidget,
    );
    expect(find.text('Emploi du temps'), findsNothing);

    // Le premier chargement est terminé : la coquille apparaît.
    app.chargementDonnees = false;
    app.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Emploi du temps'), findsWidgets);
  });
}
