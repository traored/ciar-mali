import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Suivi du contenu enseigné lors d'une séance : intitulé du chapitre et
/// grandes lignes du cours.
class SuiviCoursDialog extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic> seance;

  const SuiviCoursDialog({super.key, required this.app, required this.seance});

  @override
  State<SuiviCoursDialog> createState() => _SuiviCoursDialogState();
}

class _SuiviCoursDialogState extends State<SuiviCoursDialog> {
  late final TextEditingController _chapitre;
  late final TextEditingController _contenus;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _chapitre = TextEditingController(text: '${widget.seance['chapitre'] ?? ''}');
    _contenus = TextEditingController(text: '${widget.seance['contenus'] ?? ''}');
  }

  @override
  void dispose() {
    _chapitre.dispose();
    _contenus.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final resultat = await widget.app.api.post(
        '/seances/${widget.seance['id']}/suivi-cours',
        {
          'chapitre': _chapitre.text.trim(),
          'contenus': _contenus.text.trim(),
        },
      );
      if (!mounted) return;
      afficherMessage(context, 'Suivi du cours enregistré.');
      Navigator.pop(context, Map<String, dynamic>.from(resultat as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.toString();
        _enregistrement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seance = widget.seance;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Suivi cours',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${seance['ecue_code'] ?? ''} — ${seance['ecue_nom'] ?? ''}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppCouleurs.texteDoux,
            ),
          ),
          Text(
            '${seance['groupes_noms'] ?? ''} · semaine ${seance['semaine'] ?? ''}',
            style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _chapitre,
              decoration: const InputDecoration(
                labelText: 'Intitulé chapitre',
                hintText: 'Ex. Chapitre 3 : structures de données',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contenus,
              decoration: const InputDecoration(
                labelText: 'Contenus',
                hintText: 'Grandes lignes du cours enseigné',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 8,
              minLines: 5,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 10),
              Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enregistrement ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        ElevatedButton.icon(
          onPressed: _enregistrement ? null : _enregistrer,
          icon: _enregistrement
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
