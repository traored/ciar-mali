import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';

/// Page publique ouverte par le QR code d'un relevé : aucune session requise.
class VerificationPage extends StatefulWidget {
  final String code;
  final VoidCallback onOuvrirApplication;

  const VerificationPage({
    super.key,
    required this.code,
    required this.onOuvrirApplication,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

enum _Etat { chargement, authentique, invalide, indisponible }

class _VerificationPageState extends State<VerificationPage> {
  _Etat _etat = _Etat.chargement;
  Map<String, dynamic> _releve = const {};
  String _message = '';

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  Future<void> _verifier() async {
    setState(() {
      _etat = _Etat.chargement;
      _message = '';
    });
    try {
      // L'endpoint répond toujours HTTP 200, même pour un code invalide :
      // une ApiException signifie donc que le serveur est injoignable.
      final resultat = await ApiClient().get('/notes/verification', {
        'code': widget.code,
      });
      if (!mounted) return;
      final valide = resultat is Map && resultat['valide'] == true;
      setState(() {
        if (valide) {
          _etat = _Etat.authentique;
          _releve = Map<String, dynamic>.from(resultat['releve'] as Map? ?? const {});
        } else {
          _etat = _Etat.invalide;
          _message = resultat is Map
              ? '${resultat['message'] ?? ''}'
              : 'Code de vérification invalide.';
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _etat = _Etat.indisponible;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _etat = _Etat.indisponible;
        _message = 'Serveur CIAR-Mali injoignable.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFF), Color(0xFFE8EEF9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _enTete(),
                    const SizedBox(height: 22),
                    _carte(),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: widget.onOuvrirApplication,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Ouvrir l’application'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppCouleurs.bleu,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _enTete() {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF0D9488)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 14),
        const Text(
          'CIAR-Mali',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppCouleurs.bleuNuit,
          ),
        ),
        const Text(
          'Vérification d’un relevé de notes',
          style: TextStyle(fontSize: 13, color: AppCouleurs.texteDoux),
        ),
      ],
    );
  }

  Widget _carte() {
    return Card(
      elevation: 0,
      color: AppCouleurs.carte,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppCouleurs.bordure),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (_etat) {
          _Etat.chargement => _contenuChargement(),
          _Etat.authentique => _contenuAuthentique(),
          _Etat.indisponible => _contenuIndisponible(),
          _Etat.invalide => _contenuInvalide(),
        },
      ),
    );
  }

  Widget _contenuChargement() {
    return const Column(
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(strokeWidth: 3, color: AppCouleurs.bleu),
        ),
        SizedBox(height: 18),
        Text(
          'Vérification du relevé en cours…',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _contenuAuthentique() {
    final lignes = [
      ('Étudiant', '${_releve['etudiant'] ?? '—'}'),
      ('Matricule', '${_releve['matricule'] ?? '—'}'),
      ('Semestre', '${_releve['semestre'] ?? '—'}'),
      ('Session', '${_releve['session'] ?? '—'}'),
      ('Moyenne', '${_releve['moyenne'] ?? '—'} / 20'),
      ('Crédits', '${_releve['credits'] ?? '—'}'),
      ('Décision', '${_releve['decision'] ?? '—'}'),
      ('Émis le', '${_releve['emise_le'] ?? '—'}'),
    ];
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: AppCouleurs.vert, size: 36),
        ),
        const SizedBox(height: 14),
        const Text(
          'Relevé authentique',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: AppCouleurs.vert,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          'Ce relevé a bien été émis par CIAR-Mali. Sa signature numérique est valide.',
          style: TextStyle(fontSize: 13, color: AppCouleurs.texteDoux),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ...lignes.map(
          (ligne) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    ligne.$1,
                    style: const TextStyle(fontSize: 12.5, color: AppCouleurs.texteDoux),
                  ),
                ),
                Expanded(
                  child: Text(
                    ligne.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppCouleurs.texte,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _contenuInvalide() {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF4D6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.warning_amber_rounded, color: AppCouleurs.ambre, size: 34),
        ),
        const SizedBox(height: 14),
        const Text(
          'Relevé non vérifié',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: AppCouleurs.ambre,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _message.isEmpty ? 'Code de vérification invalide.' : _message,
          style: const TextStyle(fontSize: 13.5, color: AppCouleurs.texte),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Le code scanné n’a pas été reconnu comme un relevé émis par CIAR-Mali.',
          style: TextStyle(fontSize: 12.5, color: AppCouleurs.texteDoux),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _contenuIndisponible() {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: Color(0xFFFEE2E2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.cloud_off_rounded, color: AppCouleurs.rouge, size: 34),
        ),
        const SizedBox(height: 14),
        const Text(
          'Application indisponible',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: AppCouleurs.rouge,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Impossible de joindre le serveur CIAR-Mali. Vérifiez votre connexion '
          'et réessayez dans quelques instants.',
          style: TextStyle(fontSize: 13.5, color: AppCouleurs.texteDoux),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _verifier,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Réessayer'),
        ),
      ],
    );
  }
}
