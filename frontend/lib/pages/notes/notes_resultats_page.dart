import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Module 5 — Calcul des résultats : moyennes, crédits, compensations.
class NotesResultatsPage extends StatefulWidget {
  const NotesResultatsPage({super.key});

  @override
  State<NotesResultatsPage> createState() => _NotesResultatsPageState();
}

class _NotesResultatsPageState extends State<NotesResultatsPage> {
  int? _semestreId;
  int _session = 1;
  int? _niveauId;
  bool _chargement = false;
  String? _erreur;
  bool _compensation = true;
  bool _compensationInterUe = true;
  bool _ponderation = false;
  double _coefficientDevoir = 1;
  double _coefficientExamen = 2;
  String _session2Mode = 'meilleure_moyenne';
  bool _parametresCharges = false;
  List<Map<String, dynamic>> _resultats = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!_parametresCharges) {
      _parametresCharges = true;
      _chargerParametres();
    }
    if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _charger();
    }
  }

  Future<void> _chargerParametres() async {
    final app = context.read<AppState>();
    try {
      final donnees =
          await app.api.get('/notes/parametres') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _compensation = donnees['compensation_ecue'] as bool? ?? true;
          _compensationInterUe =
              donnees['compensation_inter_ue'] as bool? ?? true;
          _ponderation = donnees['ponderation_ecue'] as bool? ?? false;
          _coefficientDevoir =
              (donnees['coefficient_devoir'] as num?)?.toDouble() ?? 1;
          _coefficientExamen =
              (donnees['coefficient_examen'] as num?)?.toDouble() ?? 2;
          _session2Mode =
              donnees['session2_mode'] as String? ?? 'meilleure_moyenne';
        });
      }
    } catch (_) {
      // Le réglage par défaut reste la compensation activée.
    }
  }

  Future<void> _basculerCompensation(bool valeur) async {
    final app = context.read<AppState>();
    setState(() => _compensation = valeur);
    try {
      await app.api.put('/notes/parametres', {'compensation_ecue': valeur});
      if (!mounted) return;
      afficherMessage(
        context,
        valeur
            ? 'Compensation entre ECUE activée : seules les UE sont validées.'
            : 'Compensation désactivée : UE et ECUE sont validés séparément.',
      );
      await _charger();
    } catch (e) {
      if (mounted) {
        setState(() => _compensation = !valeur);
        afficherMessage(context, e.toString(), erreur: true);
      }
    }
  }

  Future<void> _basculerCompensationInterUe(bool valeur) async {
    final app = context.read<AppState>();
    setState(() => _compensationInterUe = valeur);
    try {
      await app.api.put('/notes/parametres', {'compensation_inter_ue': valeur});
      if (!mounted) return;
      afficherMessage(
        context,
        valeur
            ? 'Compensation inter UE activée : le semestre est validé dès que la moyenne pondérée des UE atteint 10.'
            : 'Compensation inter UE désactivée : toutes les UE doivent être validées pour valider le semestre.',
      );
      await _charger();
    } catch (e) {
      if (mounted) {
        setState(() => _compensationInterUe = !valeur);
        afficherMessage(context, e.toString(), erreur: true);
      }
    }
  }

  Future<void> _basculerPonderation(bool valeur) async {
    final app = context.read<AppState>();
    setState(() => _ponderation = valeur);
    try {
      await app.api.put('/notes/parametres', {'ponderation_ecue': valeur});
      if (!mounted) return;
      afficherMessage(
        context,
        valeur
            ? 'Moyenne des UE pondérée par les coefficients des ECUE.'
            : 'Moyenne des UE calculée sans coefficient des ECUE.',
      );
      await _charger();
    } catch (e) {
      if (mounted) {
        setState(() => _ponderation = !valeur);
        afficherMessage(context, e.toString(), erreur: true);
      }
    }
  }

  Future<void> _ouvrirCoefficients() async {
    final app = context.read<AppState>();
    final devoir = TextEditingController(text: noteTexte(_coefficientDevoir));
    final examen = TextEditingController(text: noteTexte(_coefficientExamen));
    final enregistrer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coefficients d’évaluation'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ces coefficients s’appliquent aux devoirs / contrôles continus '
                'et aux examens dans le calcul des moyennes.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: devoir,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Coefficient devoir / CC',
                  hintText: '1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: examen,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Coefficient examen',
                  hintText: '2',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (enregistrer != true) return;
    final valeurDevoir = double.tryParse(devoir.text.replaceAll(',', '.'));
    final valeurExamen = double.tryParse(examen.text.replaceAll(',', '.'));
    if (valeurDevoir == null ||
        valeurExamen == null ||
        valeurDevoir < 0 ||
        valeurExamen < 0 ||
        (valeurDevoir + valeurExamen) <= 0) {
      if (mounted) {
        afficherMessage(
          context,
          'Saisissez des coefficients valides (au moins un coefficient positif).',
          erreur: true,
        );
      }
      return;
    }
    try {
      await app.api.put('/notes/parametres', {
        'coefficient_devoir': valeurDevoir,
        'coefficient_examen': valeurExamen,
      });
      setState(() {
        _coefficientDevoir = valeurDevoir;
        _coefficientExamen = valeurExamen;
      });
      if (!mounted) return;
      afficherMessage(context, 'Coefficients d’évaluation enregistrés.');
      await _charger();
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  Future<void> _ouvrirParametrageSession2() async {
    final app = context.read<AppState>();
    var mode = _session2Mode;
    const descriptions = {
      'examen_remplace':
          'La note de rattrapage remplace la note d’examen initiale. '
          'La note de contrôle continu est conservée.',
      'meilleure_note':
          'La meilleure note entre l’examen initial et le rattrapage est '
          'retenue. La note de contrôle continu est conservée.',
      'meilleure_moyenne':
          'La meilleure moyenne générale entre la session 1 et le rattrapage '
          'est retenue. La note de contrôle continu est conservée.',
    };
    final enregistrer = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Paramétrage session 2'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mode de calcul de la note finale d’un ECUE en session de '
                  'rattrapage :',
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: mode,
                  onChanged: (valeur) {
                    if (valeur != null) {
                      setDialogState(() => mode = valeur);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entrue in descriptions.entries)
                        RadioListTile<String>(
                          value: entrue.key,
                          title: Text(switch (entrue.key) {
                            'examen_remplace' =>
                              'Remplacer uniquement la note d’examen initiale',
                            'meilleure_note' => 'Conserver la meilleure note',
                            _ => 'Conserver la meilleure moyenne entre les sessions',
                          }),
                          subtitle: Text(entrue.value),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (enregistrer != true) return;
    try {
      await app.api.put('/notes/parametres', {'session2_mode': mode});
      setState(() => _session2Mode = mode);
      if (!mounted) return;
      afficherMessage(context, 'Paramétrage de la session 2 enregistré.');
      await _charger();
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
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

  Future<void> _detail(Map<String, dynamic> resultat) async {
    final app = context.read<AppState>();
    try {
      final donnees = await app.api.get(
        '/notes/resultats/${resultat['inscription_id']}',
        {'semestre_id': _semestreId, 'session': _session},
      ) as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _DialogueDetailResultat(
          donnees: donnees,
          compensation: _compensation,
          compensationInterUe: _compensationInterUe,
          ponderation: _ponderation,
        ),
      );
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  void _telechargerReleve(Map<String, dynamic> resultat) {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/releve/${resultat['inscription_id']}',
      'releve_${resultat['matricule']}_S$_session.pdf',
      'application/pdf',
      parametres: {'semestre_id': _semestreId, 'session': _session},
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final notes = _resultats
        .map((r) => (r['moyenne'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final moyenne = notes.isEmpty
        ? 0.0
        : notes.reduce((a, b) => a + b) / notes.length;
    final valides = _resultats
        .where((r) => '${r['statut']}' == 'Validé')
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Calcul des résultats',
            sousTitre:
                'Moyennes, crédits, compensations et mentions par semestre.',
            actions: [
              OutlinedButton.icon(
                onPressed: _ouvrirCoefficients,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Coefficients d’évaluation'),
              ),
              OutlinedButton.icon(
                onPressed: _ouvrirParametrageSession2,
                icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                label: const Text('Paramétrage session 2'),
              ),
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Recalculer et actualiser'),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _compensation,
                      onChanged: _basculerCompensation,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Compensation entre ECUE',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _compensationInterUe,
                      onChanged: _basculerCompensationInterUe,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Compensation inter UE',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _ponderation,
                      onChanged: _basculerPonderation,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Moyenne pondérée des ECUE',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Pastille(
                  '${_resultats.length} étudiant(s)',
                  couleur: AppCouleurs.teal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, contraintes) {
              final cartes = [
                CarteIndicateur(
                  libelle: 'Étudiants évalués',
                  valeur: '${_resultats.length}',
                  icone: Icons.people_outline,
                  couleur: AppCouleurs.bleu,
                ),
                CarteIndicateur(
                  libelle: 'Moyenne générale',
                  valeur: '/${noteTexte(moyenne)}',
                  icone: Icons.analytics_outlined,
                  couleur: AppCouleurs.violet,
                  detail: 'sur 20',
                ),
                CarteIndicateur(
                  libelle: 'Validés',
                  valeur: '$valides',
                  icone: Icons.verified_outlined,
                  couleur: AppCouleurs.vert,
                  detail: _resultats.isEmpty
                      ? null
                      : '${(valides / _resultats.length * 100).toStringAsFixed(1)} %',
                ),
                CarteIndicateur(
                  libelle: 'Taux de réussite',
                  valeur: _resultats.isEmpty
                      ? '0 %'
                      : '${(valides / _resultats.length * 100).toStringAsFixed(1)} %',
                  icone: Icons.trending_up_outlined,
                  couleur: AppCouleurs.ambre,
                ),
              ];
              if (contraintes.maxWidth < 900) {
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final carte in cartes)
                      SizedBox(
                        width: (contraintes.maxWidth - 14) / 2,
                        child: carte,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < cartes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: cartes[i]),
                  ],
                ],
              );
            },
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
                    message: 'Aucun résultat calculable. Vérifiez les notes saisies et les UE du semestre.',
                    icone: Icons.calculate_outlined,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      horizontalMargin: 18,
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('RANG'), numeric: true),
                        DataColumn(label: Text('MATRICULE')),
                        DataColumn(label: Text('ÉTUDIANT')),
                        DataColumn(label: Text('NIVEAU')),
                        DataColumn(label: Text('MOYENNE')),
                        DataColumn(label: Text('CRÉDITS')),
                        DataColumn(label: Text('STATUT')),
                        DataColumn(label: Text('MENTION')),
                        DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: [
                        for (var i = 0; i < _resultats.length; i++)
                          _ligne(_resultats[i], i + 1),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  DataRow _ligne(Map<String, dynamic> resultat, int rang) {
    final statut = '${resultat['statut'] ?? ''}';
    return DataRow(
      cells: [
        DataCell(Text('$rang')),
        DataCell(Text('${resultat['matricule'] ?? '—'}')),
        DataCell(
          SizedBox(
            width: 180,
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
          Text(
            '${resultat['credits_obtenus'] ?? 0}/${resultat['credits_total'] ?? 0}',
          ),
        ),
        DataCell(
          Pastille(
            statut.isEmpty ? '—' : statut,
            couleur: couleurStatut(statut),
          ),
        ),
        DataCell(Text('${resultat['mention'] ?? '—'}')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Détail par UE',
                icon: const Icon(Icons.visibility_outlined, size: 18),
                color: AppCouleurs.bleu,
                onPressed: () => _detail(resultat),
              ),
              IconButton(
                tooltip: 'Relevé de notes PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                color: AppCouleurs.rouge,
                onPressed: () => _telechargerReleve(resultat),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialogueDetailResultat extends StatelessWidget {
  final Map<String, dynamic> donnees;
  final bool compensation;
  final bool compensationInterUe;
  final bool ponderation;

  const _DialogueDetailResultat({
    required this.donnees,
    required this.compensation,
    required this.compensationInterUe,
    required this.ponderation,
  });

  @override
  Widget build(BuildContext context) {
    final resultat = donnees['resultat'] as Map<String, dynamic>? ?? {};
    final ues = (resultat['ues'] as List?) ?? [];
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${donnees['etudiant'] ?? 'Étudiant'}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${donnees['matricule'] ?? ''} · ${donnees['niveau'] ?? ''} · Session ${resultat['session'] ?? 1}',
            style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Pastille(
                      'Moyenne /${noteTexte(resultat['moyenne'])}',
                      couleur: AppCouleurs.bleu,
                    ),
                    Pastille(
                      'Crédits ${resultat['credits_obtenus'] ?? 0}/${resultat['credits_total'] ?? 0}',
                      couleur: AppCouleurs.teal,
                    ),
                    Pastille(
                      '${resultat['mention'] ?? '—'}',
                      couleur: AppCouleurs.violet,
                    ),
                    Pastille(
                      '${resultat['decision'] ?? resultat['statut'] ?? '—'}',
                      couleur: couleurStatut(
                        '${resultat['decision'] ?? resultat['statut'] ?? ''}',
                      ),
                    ),
                    if (compensation)
                      const Pastille(
                        'Compensation ECUE activée',
                        couleur: AppCouleurs.teal,
                      ),
                    Pastille(
                      compensationInterUe
                          ? 'Compensation inter UE activée'
                          : 'Compensation inter UE désactivée',
                      couleur: compensationInterUe
                          ? AppCouleurs.vert
                          : AppCouleurs.ambre,
                    ),
                    Pastille(
                      ponderation
                          ? 'Moyenne UE pondérée par les ECUE'
                          : 'Moyenne UE sans coefficient ECUE',
                      couleur: AppCouleurs.violet,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final ue in ues) _blocUE(ue as Map<String, dynamic>),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _blocUE(Map<String, dynamic> ue) {
    final ecues = (ue['ecues'] as List?) ?? [];
    final statut = '${ue['statut'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.fond,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ue['code']} — ${ue['nom']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Pastille('${ue['credits']} crédits'),
              const SizedBox(width: 6),
              Pastille(
                'Moy. ${noteTexte(ue['moyenne'])}',
                couleur: AppCouleurs.bleu,
              ),
              const SizedBox(width: 6),
              Pastille(
                statut.isEmpty ? '—' : statut,
                couleur: couleurStatut(statut),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: {
              0: const FlexColumnWidth(1.0),
              1: const FlexColumnWidth(3.0),
              2: const FlexColumnWidth(0.8),
              3: const FlexColumnWidth(0.8),
              4: const FlexColumnWidth(0.8),
              5: const FlexColumnWidth(0.9),
              if (!compensation) 6: const FlexColumnWidth(1.0),
            },
            children: [
              TableRow(
                children: [
                  const _EnteteCellule('ECUE'),
                  const _EnteteCellule('Intitulé'),
                  const _EnteteCellule('Crédits'),
                  const _EnteteCellule('CC'),
                  const _EnteteCellule('Examen'),
                  const _EnteteCellule('Moyenne'),
                  if (!compensation) const _EnteteCellule('Statut'),
                ],
              ),
              for (final ecue in ecues)
                TableRow(
                  children: [
                    _Cellule('${ecue['code'] ?? ''}'),
                    _Cellule('${ecue['nom'] ?? ''}'),
                    _Cellule('${ecue['credits'] ?? '—'}'),
                    _Cellule(noteTexte(ecue['cc'])),
                    _Cellule(noteTexte(ecue['examen'])),
                    _Cellule(noteTexte(ecue['moyenne'])),
                    if (!compensation)
                      _Cellule(
                        (ecue['moyenne_jury'] ?? ecue['moyenne']) == null
                            ? '—'
                            : (((ecue['moyenne_jury'] ?? ecue['moyenne'])
                                          as num) >=
                                      10
                                  ? 'Validé'
                                  : 'Non validé'),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnteteCellule extends StatelessWidget {
  final String texte;

  const _EnteteCellule(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        texte,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppCouleurs.texteDoux,
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  final String texte;

  const _Cellule(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(texte, style: const TextStyle(fontSize: 12)),
    );
  }
}
