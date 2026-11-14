import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Module dédié — Passages en classe supérieure.
class NotesPassagesPage extends StatefulWidget {
  const NotesPassagesPage({super.key});

  @override
  State<NotesPassagesPage> createState() => _NotesPassagesPageState();
}

class _NotesPassagesPageState extends State<NotesPassagesPage> {
  final TextEditingController _seuilDettes = TextEditingController(text: '80');
  bool _initialise = false;
  bool _chargement = false;
  bool _afficherTous = false;
  String? _erreur;
  String? _annee;
  int _session = 1;
  int? _niveauId;
  String _mode = '10';
  int _moyennePassage = 10;
  bool _telechargementPdf = false;
  List<String> _annees = [];
  List<Map<String, dynamic>> _resultats = [];
  int _admis = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialise) {
      _initialise = true;
      _initialiser();
    }
  }

  @override
  void dispose() {
    _seuilDettes.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    final app = context.read<AppState>();
    try {
      final donnees =
          await app.api.get('/notes/passages/options') as Map<String, dynamic>;
      _annees = ((donnees['annees'] as List?) ?? [])
          .map((annee) => '$annee')
          .where((annee) => annee.isNotEmpty)
          .toList();
    } catch (_) {
      // Repli sur les années connues de l'application.
    }
    if (_annees.isEmpty) {
      final annees = <String>{
        for (final semestre in app.semestres)
          if ('${semestre['annee'] ?? ''}'.isNotEmpty) '${semestre['annee']}',
        for (final inscription in app.inscriptionsNotes)
          if ('${inscription['annee'] ?? ''}'.isNotEmpty)
            '${inscription['annee']}',
      }.toList()..sort((a, b) => b.compareTo(a));
      _annees = annees;
    }
    // Privilégie l'année la plus récente qui possède réellement des
    // inscriptions, afin de ne pas ouvrir la page sur une année vide.
    if (_annees.isNotEmpty) {
      final anneesInscrites = {
        for (final inscription in app.inscriptionsNotes)
          if ('${inscription['annee'] ?? ''}'.isNotEmpty)
            '${inscription['annee']}',
      };
      _annee = _annees.firstWhere(
        (annee) => anneesInscrites.contains(annee),
        orElse: () => _annees.first,
      );
    } else {
      _annee = null;
    }
    if (mounted) setState(() {});
    await _charger();
  }

  double get _seuil {
    final valeur = double.tryParse(
      _seuilDettes.text.trim().replaceAll(',', '.'),
    );
    return (valeur ?? 80).clamp(0, 100).toDouble();
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    if (_annee == null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/notes/passages', {
        'annee': _annee,
        'session': _session,
        'mode': _mode,
        'seuil_dettes': _seuil,
        'moyenne_passage': _moyennePassage,
        if (_niveauId != null) 'niveau_id': _niveauId,
      }, ApiClient.delaiLong) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _resultats = ((donnees['resultats'] as List?) ?? [])
            .map((element) => Map<String, dynamic>.from(element as Map))
            .toList();
        _admis = (donnees['admis'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _changerMode(String mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _charger();
  }

  void _appliquerSeuil() {
    _seuilDettes.text = _seuil.toStringAsFixed(0);
    _charger();
  }

  Map<String, dynamic> get _parametresPassage => {
    'annee': _annee,
    'session': _session,
    'mode': _mode,
    'seuil_dettes': _seuil,
    'moyenne_passage': _moyennePassage,
    if (_niveauId != null) 'niveau_id': _niveauId,
  };

  Future<void> _telechargerListe() async {
    if (_annee == null) return;
    setState(() => _telechargementPdf = true);
    final app = context.read<AppState>();
    try {
      await telechargerDepuisApi(
        context,
        app,
        '/notes/documents/passages',
        'passages_${_annee}_S$_session.pdf',
        'application/pdf',
        parametres: _parametresPassage,
      );
    } finally {
      if (mounted) setState(() => _telechargementPdf = false);
    }
  }

  void _telechargerReleve(Map<String, dynamic> resultat) {
    final inscriptionId = resultat['inscription_id'];
    if (inscriptionId == null) {
      afficherMessage(context, 'Inscription introuvable pour cet étudiant.', erreur: true);
      return;
    }
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/passage/$inscriptionId',
      'passage_${resultat['matricule'] ?? inscriptionId}.pdf',
      'application/pdf',
      parametres: {
        'session': _session,
        'mode': _mode,
        'seuil_dettes': _seuil,
        'moyenne_passage': _moyennePassage,
      },
    );
  }

  String get _libelleMode {
    switch (_mode) {
      case '12':
        return 'Passage avec 12';
      case 'dettes':
        return 'Passage Dettes';
      default:
        return 'Passage avec 10';
    }
  }

  String get _explicationMode {
    switch (_mode) {
      case '12':
        return 'Admission si les deux semestres de l’année sont validés et si la moyenne annuelle atteint 12.';
      case 'dettes':
        return 'Admission si l’étudiant valide au moins ${_seuil.toStringAsFixed(0)} % des crédits de l’année '
            'et si sa moyenne annuelle atteint au moins $_moyennePassage.';
      default:
        return 'Admission si les deux semestres de l’année sont validés.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final affiches = _afficherTous
        ? _resultats
        : _resultats.where((resultat) => resultat['admis'] == true).toList();
    final taux = _resultats.isEmpty ? 0.0 : _admis / _resultats.length * 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Passages en classe supérieure',
            sousTitre: 'Résultats d’admission calculés sur les deux semestres de l’année universitaire.',
            actions: [
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
              FilledButton.icon(
                onPressed: _annee == null || _telechargementPdf
                    ? null
                    : _telechargerListe,
                icon: _telechargementPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Liste des admis (PDF)'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          CarteSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String?>(_annee),
                        initialValue: _annees.contains(_annee) ? _annee : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Année universitaire',
                          isDense: true,
                        ),
                        items: [
                          for (final annee in _annees)
                            DropdownMenuItem(
                              value: annee,
                              child: Text(
                                annee,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                        onChanged: _annees.isEmpty
                            ? null
                            : (valeur) {
                                if (valeur == null) return;
                                setState(() => _annee = valeur);
                                _charger();
                              },
                      ),
                    ),
                    selecteurSession(_session, (valeur) {
                      setState(() => _session = valeur ?? 1);
                      _charger();
                    }),
                    selecteurNiveau(app, _niveauId, (valeur) {
                      setState(() => _niveauId = valeur);
                      _charger();
                    }),
                    if (_mode == 'dettes') ...[
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _seuilDettes,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,\.]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Crédits à valider (%)',
                            isDense: true,
                            suffixText: '%',
                          ),
                          onSubmitted: (_) => _appliquerSeuil(),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _charger,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Appliquer'),
                      ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<int>(
                          initialValue: _moyennePassage,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Moyenne annuelle minimale',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 10,
                              child: Text('10 (avec 10)'),
                            ),
                            DropdownMenuItem(
                              value: 12,
                              child: Text('12 (avec 12)'),
                            ),
                          ],
                          onChanged: (valeur) {
                            setState(() => _moyennePassage = valeur ?? 10);
                            _charger();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final mode in const ['10', '12', 'dettes'])
                      ChoiceChip(
                        label: Text(switch (mode) {
                          '12' => 'Passage avec 12',
                          'dettes' => 'Passage Dettes',
                          _ => 'Passage avec 10',
                        }),
                        selected: _mode == mode,
                        onSelected: (_) => _changerMode(mode),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _explicationMode,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppCouleurs.texteDoux,
                  ),
                ),
              ],
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 14),
            Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, contraintes) {
              final cartes = [
                CarteIndicateur(
                  libelle: 'Étudiants inscrits',
                  valeur: '${_resultats.length}',
                  icone: Icons.people_outline,
                  couleur: AppCouleurs.bleu,
                  detail: _annee ?? '',
                ),
                CarteIndicateur(
                  libelle: 'Admis',
                  valeur: '$_admis',
                  icone: Icons.workspace_premium_outlined,
                  couleur: AppCouleurs.vert,
                  detail: _libelleMode,
                ),
                CarteIndicateur(
                  libelle: 'Non admis',
                  valeur: '${_resultats.length - _admis}',
                  icone: Icons.block_outlined,
                  couleur: AppCouleurs.rouge,
                  detail: 'Ajournés ou année incomplète',
                ),
                CarteIndicateur(
                  libelle: 'Taux d’admission',
                  valeur: '${noteTexte(taux, decimales: 1)} %',
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _afficherTous
                      ? 'Tous les étudiants de l’année'
                      : 'Étudiants admis en classe supérieure',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppCouleurs.texte,
                  ),
                ),
              ),
              Switch(
                value: _afficherTous,
                onChanged: (valeur) => setState(() => _afficherTous = valeur),
              ),
              const SizedBox(width: 4),
              const Text(
                'Afficher tous les étudiants',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CarteTableau(
            child: _chargement
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : affiches.isEmpty
                ? EtatVide(
                    message: _resultats.isEmpty
                        ? 'Aucune inscription trouvée pour cette année universitaire. '
                              'Vérifiez la session et le niveau sélectionnés.'
                        : 'Aucun étudiant admis avec ce mode de passage. '
                              'Activez « Afficher tous les étudiants » pour consulter tous les résultats.',
                    icone: Icons.school_outlined,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 20,
                      horizontalMargin: 18,
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('MATRICULE')),
                        DataColumn(label: Text('ÉTUDIANT')),
                        DataColumn(label: Text('NIVEAU')),
                        DataColumn(label: Text('SEMESTRES')),
                        DataColumn(label: Text('MOYENNE ANNUELLE')),
                        DataColumn(label: Text('CRÉDITS')),
                        DataColumn(label: Text('% CRÉDITS')),
                        DataColumn(label: Text('DÉCISION')),
                        DataColumn(label: Text('PASSAGE')),
                        DataColumn(label: Text('DOCUMENT')),
                      ],
                      rows: [for (final resultat in affiches) _ligne(resultat)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  DataRow _ligne(Map<String, dynamic> resultat) {
    final decision = '${resultat['decision'] ?? ''}';
    final semestres = (resultat['semestres'] as List?) ?? [];
    final admis = resultat['admis'] == true;
    return DataRow(
      cells: [
        DataCell(Text('${resultat['matricule'] ?? '—'}')),
        DataCell(
          SizedBox(
            width: 180,
            child: Text(
              '${resultat['etudiant'] ?? '—'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        DataCell(
          Text(
            '${resultat['niveau'] ?? '—'}'
            '${'${resultat['filiere'] ?? ''}'.isEmpty ? '' : ' · ${resultat['filiere']}'}',
          ),
        ),
        DataCell(
          SizedBox(
            width: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final semestre in semestres)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      '${semestre['semestre']} : /${noteTexte(semestre['moyenne'])} '
                      '(${semestre['statut'] ?? '—'})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        DataCell(Text('/${noteTexte(resultat['moyenne_annee'])}')),
        DataCell(
          Text(
            '${resultat['credits_obtenus'] ?? 0}/${resultat['credits_total'] ?? 0}',
          ),
        ),
        DataCell(
          Text('${noteTexte(resultat['pourcentage_credits'], decimales: 1)} %'),
        ),
        DataCell(
          Pastille(
            decision.isEmpty ? '—' : decision,
            couleur: _couleurDecision(decision),
          ),
        ),
        DataCell(
          Text(
            admis ? '${resultat['niveau_suivant'] ?? '—'}' : '—',
            style: TextStyle(
              fontWeight: admis ? FontWeight.w700 : FontWeight.w400,
              color: admis ? AppCouleurs.vert : AppCouleurs.texteDoux,
            ),
          ),
        ),
        DataCell(
          IconButton(
            tooltip: 'Relevé récapitulatif de passage',
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            onPressed: () => _telechargerReleve(resultat),
          ),
        ),
      ],
    );
  }

  Color _couleurDecision(String decision) {
    if (decision == 'Admis avec dettes') return AppCouleurs.ambre;
    if (decision.startsWith('Admis')) return AppCouleurs.vert;
    if (decision == 'Année incomplète') return AppCouleurs.texteDoux;
    return AppCouleurs.rouge;
  }
}
