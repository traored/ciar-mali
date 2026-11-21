import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../crud/notes_configs.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Module 6 — Délibérations : jury, admission, ajournement et rattrapage.
class NotesDeliberationsPage extends StatefulWidget {
  const NotesDeliberationsPage({super.key});

  @override
  State<NotesDeliberationsPage> createState() => _NotesDeliberationsPageState();
}

class _NotesDeliberationsPageState extends State<NotesDeliberationsPage> {
  int? _semestreId;
  int _session = 1;
  int? _niveauId;
  bool _chargement = false;
  bool _traitement = false;
  String? _erreur;
  List<Map<String, dynamic>> _resultats = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _charger();
    }
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    if (_semestreId == null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final resultats = await app.api.liste('/notes/resultats', {
        'semestre_id': _semestreId,
        'session': _session,
        if (_niveauId != null) 'niveau_id': _niveauId,
      });
      if (mounted) setState(() => _resultats = resultats);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _deliberationAutomatique() async {
    final app = context.read<AppState>();
    if (_semestreId == null) return;
    final ok = await confirmer(
      context,
      titre: 'Délibération automatique',
      message: 'Le jury propose une décision pour chaque résultat non verrouillé : ADMIS, AJOURNE ou RATTRAPAGE. Continuer ?',
      action: 'Délibérer',
      danger: false,
    );
    if (!ok || !mounted) return;
    setState(() {
      _traitement = true;
      _erreur = null;
    });
    try {
      final suffixe = _niveauId != null ? '&niveau_id=$_niveauId' : '';
      final rapport = await app.api.post(
        '/notes/deliberations/automatique?semestre_id=$_semestreId&session=$_session$suffixe',
        {},
      );
      if (!mounted) return;
      afficherMessage(context, '${rapport['message']}');
      await _charger();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  Future<void> _decider(Map<String, dynamic> resultat) async {
    final app = context.read<AppState>();
    final choix = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _DialogueDecision(resultat: resultat),
    );
    if (choix == null) return;
    setState(() => _traitement = true);
    try {
      await app.api.post('/notes/deliberations', {
        'resultat_id': resultat['id'],
        'decision': choix['decision'],
        'commentaire': choix['commentaire'],
        'jury': choix['jury'],
        'points_jury': choix['points_jury'],
      });
      if (!mounted) return;
      afficherMessage(context, 'Décision enregistrée : ${choix['decision']}.');
      await _charger();
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  Future<void> _deverrouiller(Map<String, dynamic> resultat) async {
    final app = context.read<AppState>();
    final ok = await confirmer(
      context,
      titre: 'Déverrouiller le résultat',
      message:
          'La décision de ${resultat['etudiant_nom']} sera effacée et le résultat pourra être recalculé. Continuer ?',
      action: 'Déverrouiller',
      danger: false,
    );
    if (!ok || !mounted) return;
    setState(() => _traitement = true);
    try {
      await app.api.post(
        '/notes/resultats/${resultat['id']}/deverrouiller',
        {},
      );
      if (!mounted) return;
      afficherMessage(context, 'Résultat déverrouillé.');
      await _charger();
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _traitement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final admis = _resultats.where((r) => r['decision'] == 'ADMIS').length;
    final ajournes = _resultats.where((r) => r['decision'] == 'AJOURNE').length;
    final rattrapage = _resultats
        .where((r) => r['decision'] == 'RATTRAPAGE')
        .length;
    final attente = _resultats
        .where((r) => '${r['decision'] ?? ''}'.isEmpty)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Délibérations',
            sousTitre:
                'Jury, admission, ajournement et rattrapage des étudiants.',
            actions: [
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
              ElevatedButton.icon(
                onPressed:
                    _resultats.isEmpty || _traitement || !app.peutModifier
                    ? null
                    : _deliberationAutomatique,
                icon: _traitement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.gavel_outlined, size: 18),
                label: const Text('Délibération automatique'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          CarteSection(
            child: Wrap(
              spacing: 18,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                selecteurSemestre(
                  app,
                  _semestreId,
                  (valeur) => app.selectionnerSemestre(valeur),
                ),
                selecteurSession(_session, (valeur) {
                  setState(() => _session = valeur ?? 1);
                  _charger();
                }),
                selecteurNiveau(app, _niveauId, (valeur) {
                  setState(() => _niveauId = valeur);
                  _charger();
                }),
                Pastille('$admis admis', couleur: AppCouleurs.vert),
                Pastille('$ajournes ajournés', couleur: AppCouleurs.rouge),
                Pastille('$rattrapage rattrapage', couleur: AppCouleurs.ambre),
                Pastille('$attente en attente', couleur: AppCouleurs.texteDoux),
              ],
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 14),
            Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
          ],
          const SizedBox(height: 16),
          CarteTableau(
            child: _chargement
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _resultats.isEmpty
                ? const EtatVide(
                    message: 'Aucun résultat à délibérer pour ces critères.',
                    icone: Icons.gavel_outlined,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      horizontalMargin: 18,
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('MATRICULE')),
                        DataColumn(label: Text('ÉTUDIANT')),
                        DataColumn(label: Text('NIVEAU')),
                        DataColumn(label: Text('MOYENNE')),
                        DataColumn(label: Text('STATUT')),
                        DataColumn(label: Text('DÉCISION')),
                        DataColumn(label: Text('VERROU')),
                        DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: [
                        for (final resultat in _resultats)
                          _ligne(resultat, app.peutModifier),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  DataRow _ligne(Map<String, dynamic> resultat, bool peutModifier) {
    final decision = '${resultat['decision'] ?? ''}';
    final verrouille = resultat['verrouille'] == true;
    return DataRow(
      cells: [
        DataCell(Text('${resultat['matricule'] ?? '—'}')),
        DataCell(
          SizedBox(
            width: 190,
            child: Text(
              '${resultat['etudiant_nom'] ?? '—'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        DataCell(Text('${resultat['niveau_nom'] ?? '—'}')),
        DataCell(Text('/${noteTexte(resultat['moyenne'])}')),
        DataCell(
          Pastille(
            '${resultat['statut'] ?? '—'}',
            couleur: couleurStatut('${resultat['statut'] ?? ''}'),
          ),
        ),
        DataCell(
          Pastille(
            decision.isEmpty ? 'En attente' : decision,
            couleur: decision.isEmpty
                ? AppCouleurs.texteDoux
                : couleurStatut(decision),
          ),
        ),
        DataCell(
          Icon(
            verrouille ? Icons.lock_outline : Icons.lock_open_outlined,
            size: 17,
            color: verrouille ? AppCouleurs.rouge : AppCouleurs.vert,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _traitement || !peutModifier
                    ? null
                    : () => _decider(resultat),
                icon: const Icon(Icons.how_to_vote_outlined, size: 16),
                label: Text(decision.isEmpty ? 'Décider' : 'Réviser'),
              ),
              if (verrouille && peutModifier)
                IconButton(
                  tooltip: 'Déverrouiller',
                  icon: const Icon(Icons.lock_open_outlined, size: 18),
                  color: AppCouleurs.ambre,
                  onPressed: _traitement
                      ? null
                      : () => _deverrouiller(resultat),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialogueDecision extends StatefulWidget {
  final Map<String, dynamic> resultat;

  const _DialogueDecision({required this.resultat});

  @override
  State<_DialogueDecision> createState() => _DialogueDecisionState();
}

class _DialogueDecisionState extends State<_DialogueDecision> {
  late String _decision;
  final _commentaire = TextEditingController();
  final _jury = TextEditingController(text: 'Jury de délibération');
  final _pointsJury = TextEditingController();

  @override
  void initState() {
    super.initState();
    final actuelle = '${widget.resultat['decision'] ?? ''}';
    _decision = decisionsDeliberation.contains(actuelle) ? actuelle : 'ADMIS';
    final points = (widget.resultat['points_jury'] as num?)?.toDouble() ?? 0;
    if (points.abs() >= 0.000001) {
      _pointsJury.text = points.toStringAsFixed(2).replaceAll('.', ',');
    } else {
      final moyenne = (widget.resultat['moyenne'] as num?)?.toDouble();
      if (moyenne != null && moyenne < 10) {
        final deficit = (10 - moyenne).clamp(0.0, 20.0);
        _pointsJury.text = deficit.toStringAsFixed(2).replaceAll('.', ',');
      }
    }
  }

  @override
  void dispose() {
    _commentaire.dispose();
    _jury.dispose();
    _pointsJury.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Décision du jury',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppCouleurs.fond,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppCouleurs.bordure),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.resultat['etudiant_nom'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.resultat['matricule'] ?? ''} · Moyenne /${noteTexte(widget.resultat['moyenne'])} · ${widget.resultat['statut'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppCouleurs.texteDoux,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _decision,
              decoration: const InputDecoration(labelText: 'Décision'),
              items: [
                for (final decision in decisionsDeliberation)
                  DropdownMenuItem(value: decision, child: Text(decision)),
              ],
              onChanged: (valeur) =>
                  setState(() => _decision = valeur ?? 'ADMIS'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _jury,
              decoration: const InputDecoration(labelText: 'Jury'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pointsJury,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Points jury (moyenne finale)',
                helperText: 'Points complémentaires pour valider le semestre (généralement inférieurs à 1).',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _commentaire,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Commentaire (optionnel)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            final texte = _pointsJury.text.trim().replaceAll(',', '.');
            final points = texte.isEmpty ? 0.0 : double.tryParse(texte);
            if (points == null) {
              afficherMessage(
                context,
                'Saisissez un nombre valide pour les points jury.',
                erreur: true,
              );
              return;
            }
            Navigator.pop(context, {
              'decision': _decision,
              'commentaire': _commentaire.text.trim(),
              'jury': _jury.text.trim(),
              'points_jury': points,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
