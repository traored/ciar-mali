import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'pages/login_page.dart';
import 'pages/shell_page.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  final app = AppState();
  // Le démarrage restaure la session enregistrée puis charge les référentiels.
  app.demarrer();
  runApp(
    ChangeNotifierProvider.value(
      value: app,
      child: const CiarMaliApp(),
    ),
  );
}

class CiarMaliApp extends StatelessWidget {
  const CiarMaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIAR-Mali — Gestion des emplois du temps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.clair,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Racine(),
    );
  }
}

class _Racine extends StatelessWidget {
  const _Racine();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.demarrage) {
      return const _EcranChargement();
    }
    if (!app.connecte) {
      return const LoginPage();
    }
    return const ShellPage();
  }
}

class _EcranChargement extends StatelessWidget {
  const _EcranChargement();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppCouleurs.bleuNuit,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF0D9488)],
                ),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 22),
            const Text(
              'CIAR-Mali',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gestion des emplois du temps universitaires',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Color(0xFF5EEAD4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
