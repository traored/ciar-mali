import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Feuille de présence d'une séance : liste des étudiants du groupe avec
/// une case « présent » et un commentaire facultatif.
class PresencesDialog extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic> seance;

  const PresencesDialog({super.key, required this.app, required this.seance});

  @override
  State<PresencesDialog> createState() => _PresencesDialogState();
}

class _PresencesDialogState extends State<PresencesDialog> {
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;
  List<Map<String, dynamic>> _lignes = [];
  final Map<int, bool> _presents = {};
  final Map<int, TextEditingController> _commentaires = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final controleur in _commentaires.values) {
      controleur.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final donnees = await widget.app.api.get('/notes/presences', {
        'seance_id': widget.seance['id'],
      }) as Map<String, dynamic>;
      final lignes = ((donnees['lignes'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      for (final ligne in lignes) {
        final inscriptionId = ligne['inscription_id'] as int;
        _presents[inscriptionId] = ligne['present'] as bool? ?? true;
        _commentaires[inscriptionId] = TextEditingController(
          text: '${ligne['commentaire'] ?? ''}',
        );
      }
      if (mounted) setState(() => _lignes = lignes);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final resultat = await widget.app.api.post('/notes/presences', {
        'seance_id': widget.seance['id'],
        'presences': [
          for (final ligne in _lignes)
            {
              'inscription_id': ligne['inscription_id'],
              'present': _presents[ligne['inscription_id']] ?? true,
              'commentaire':
                  _commentaires[ligne['inscription_id']]?.text.trim() ?? '',
            },
        ],
      });
      if (!mounted) return;
      Navigator.pop(context);
      afficherMessage(
        context,
        '${resultat['message'] ?? 'Présences enregistrées'}',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.toString();
          _enregistrement = false;
        });
      }
    }
  }

  void _toutPresent(bool present) {
    setState(() {
      for (final ligne in _lignes) {
        _presents[ligne['inscription_id'] as int] = present;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final seance = widget.seance;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Feuille de présence',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
        width: 620,
        child: _chargement
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _toutPresent(true),
                        icon: const Icon(Icons.done_all, size: 17),
                        label: const Text('Tous présents'),
                      ),
                      TextButton.icon(
                        onPressed: () => _toutPresent(false),
                        icon: const Icon(Icons.remove_done, size: 17),
                        label: const Text('Tous absents'),
                      ),
                      const Spacer(),
                      Pastille(
                        '${_lignes.where((l) => _presents[l['inscription_id']] == true).length} / ${_lignes.length} présent(s)',
                        couleur: AppCouleurs.teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_lignes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          'Aucun étudiant inscrit pour cette séance.',
                          style: TextStyle(color: AppCouleurs.texteDoux),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final ligne in _lignes)
                              _ligneEtudiant(ligne),
                          ],
                        ),
                      ),
                    ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _erreur!,
                      style: const TextStyle(color: AppCouleurs.rouge),
                    ),
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
          onPressed: _chargement || _enregistrement || _lignes.isEmpty
              ? null
              : _enregistrer,
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

  Widget _ligneEtudiant(Map<String, dynamic> ligne) {
    final inscriptionId = ligne['inscription_id'] as int;
    final present = _presents[inscriptionId] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: present,
            onChanged: (valeur) =>
                setState(() => _presents[inscriptionId] = valeur ?? false),
          ),
          SizedBox(
            width: 90,
            child: Text(
              '${ligne['matricule'] ?? '—'}',
              style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
            ),
          ),
          SizedBox(
            width: 200,
            child: Text(
              '${ligne['etudiant_nom'] ?? '—'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _commentaires[inscriptionId],
              decoration: const InputDecoration(
                hintText: 'Commentaire (facultatif)',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
