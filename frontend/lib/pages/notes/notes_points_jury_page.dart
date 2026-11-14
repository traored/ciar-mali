import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Espace « Points jury » : points complémentaires par étudiant, pour une UE
/// ou une ECUE, sans passer par la fiche de l'UE / de l'ECUE.
class NotesPointsJuryPage extends StatefulWidget {
  const NotesPointsJuryPage({super.key});

  @override
  State<NotesPointsJuryPage> createState() => _NotesPointsJuryPageState();
}

class _NotesPointsJuryPageState extends State<NotesPointsJuryPage> {
  int? _semestreId;
  String _mode = 'ue';
  int? _cibleId;
  bool _chargement = false;
  bool _enregistrement = false;
  String? _erreur;

  List<Map<String, dynamic>> _lignes = [];
  Map<String, dynamic>? _cible;
  Map<String, dynamic>? _semestre;

  final Map<int, TextEditingController> _points = {};
  final Map<String, Set<int>> _auto = {};

  String get _cleAuto => '$_mode:$_cibleId';

  void _basculerAuto(
    int inscriptionId,
    Map<String, dynamic> ligne,
    bool actif,
  ) {
    final moyenne = (ligne['moyenne'] as num?)?.toDouble();
    if (actif && moyenne == null) return;
    final ensemble = _auto.putIfAbsent(_cleAuto, () => <int>{});
    setState(() {
      if (!actif) {
        ensemble.remove(inscriptionId);
        return;
      }
      ensemble.add(inscriptionId);
      final points = 10 - moyenne!;
      _points[inscriptionId]?.text = (points < 0 ? 0.0 : points)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _cibleId = null;
      _cible = null;
      _semestre = null;
      _erreur = null;
      _viderLignes();
    }
  }

  @override
  void dispose() {
    _viderLignes();
    super.dispose();
  }

  void _viderLignes() {
    for (final controleur in _points.values) {
      controleur.dispose();
    }
    _points.clear();
    _lignes = [];
  }

  void _changerMode(String mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _cibleId = null;
      _cible = null;
      _semestre = null;
      _erreur = null;
      _viderLignes();
    });
  }

  String get _endpoint =>
      _mode == 'ue' ? '/notes/points-jury/ue' : '/notes/points-jury/ecue';

  String get _cleCible => _mode == 'ue' ? 'ue_id' : 'ecue_id';

  List<Map<String, dynamic>> _options(AppState app) {
    if (_semestreId == null) return [];
    if (_mode == 'ue') {
      final options = app.ues
          .where((ue) => ue['semestre_id'] == _semestreId)
          .toList();
      options.sort(
        (a, b) => '${a['code'] ?? ''}'.compareTo('${b['code'] ?? ''}'),
      );
      return options;
    }
    final options = app.ecues.where((ecue) {
      if (ecue['semestre_id'] != null) {
        return ecue['semestre_id'] == _semestreId;
      }
      final ue = app.ues.firstWhere(
        (element) => element['id'] == ecue['ue_id'],
        orElse: () => const {},
      );
      return ue['semestre_id'] == _semestreId;
    }).toList();
    options.sort(
      (a, b) => '${a['code'] ?? ''}'.compareTo('${b['code'] ?? ''}'),
    );
    return options;
  }

  Future<void> _chargerCible(int? id) async {
    final mode = _mode;
    setState(() {
      _cibleId = id;
      _erreur = null;
      if (id == null) {
        _cible = null;
        _semestre = null;
        _viderLignes();
      }
    });
    if (id == null) return;
    final app = context.read<AppState>();
    setState(() => _chargement = true);
    try {
      final donnees =
          await app.api.get(_endpoint, {_cleCible: id}) as Map<String, dynamic>;
      if (!mounted || _mode != mode || _cibleId != id) return;
      final lignes = ((donnees['lignes'] as List?) ?? [])
          .map((element) => Map<String, dynamic>.from(element as Map))
          .toList();
      _viderLignes();
      for (final ligne in lignes) {
        final inscriptionId = ligne['inscription_id'] as int;
        final points = (ligne['points'] as num?)?.toDouble() ?? 0;
        _points[inscriptionId] = TextEditingController(
          text: points.abs() < 0.000001
              ? ''
              : points.toStringAsFixed(2).replaceAll('.', ','),
        );
      }
      setState(() {
        _lignes = lignes;
        _cible = Map<String, dynamic>.from(
          (donnees[mode] as Map?) ?? (donnees['ue'] as Map?) ?? const {},
        );
        _semestre = donnees['semestre'] == null
            ? null
            : Map<String, dynamic>.from(donnees['semestre'] as Map);
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _enregistrer() async {
    if (_cibleId == null || _lignes.isEmpty) return;
    final app = context.read<AppState>();
    final points = <Map<String, dynamic>>[];
    String? erreur;
    for (final ligne in _lignes) {
      final inscriptionId = ligne['inscription_id'] as int;
      final texte =
          _points[inscriptionId]?.text.trim().replaceAll(',', '.') ?? '';
      double? valeur;
      if (texte.isNotEmpty) {
        valeur = double.tryParse(texte);
        if (valeur == null || valeur < 0) {
          erreur =
              'Valeur invalide pour ${ligne['etudiant_nom'] ?? 'cet étudiant'}. '
              'Entrez un nombre positif.';
          break;
        }
      }
      points.add({'inscription_id': inscriptionId, 'points': valeur});
    }
    if (erreur != null) {
      setState(() => _erreur = erreur);
      return;
    }
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final resultat = await app.api.post(_endpoint, {
        _cleCible: _cibleId,
        'points': points,
      });
      if (!mounted) return;
      afficherMessage(context, '${resultat['message']}');
      await _chargerCible(_cibleId);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final options = _options(app);
    final libelleCible = _mode == 'ue' ? 'UE' : 'ECUE';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Points jury',
            sousTitre:
                'Attribution des points complémentaires par étudiant, au niveau de l’UE ou de l’ECUE. '
                'La note affichée reste la note réelle.',
            actions: [
              ElevatedButton.icon(
                onPressed:
                    _cibleId == null ||
                        _lignes.isEmpty ||
                        _enregistrement ||
                        !app.peutModifier
                    ? null
                    : _enregistrer,
                icon: _enregistrement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Enregistrer les points'),
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
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'ue',
                      label: Text('Points jury UE'),
                      icon: Icon(Icons.layers_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 'ecue',
                      label: Text('Points jury ECUE'),
                      icon: Icon(Icons.view_agenda_outlined, size: 18),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) =>
                      _changerMode(selection.first),
                ),
                selecteurSemestre(
                  app,
                  _semestreId,
                  (valeur) => app.selectionnerSemestre(valeur),
                ),
                SizedBox(
                  width: 380,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey<String>(
                      '${_mode}_${_semestreId}_${_cibleId}_${options.length}',
                    ),
                    initialValue:
                        options.any((element) => element['id'] == _cibleId)
                        ? _cibleId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '$libelleCible (code · nom)',
                      isDense: true,
                    ),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(
                          value: option['id'] as int,
                          child: Text(
                            '${option['code']} · ${option['nom']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: _chargement ? null : _chargerCible,
                  ),
                ),
                if (_semestre != null)
                  Pastille(
                    '${_semestre!['nom']} · ${_semestre!['annee']}',
                    couleur: AppCouleurs.teal,
                  ),
                if (_cible != null)
                  Pastille(
                    '$libelleCible ${_cible!['code']} · ${_cible!['nom']}',
                    couleur: AppCouleurs.violet,
                  ),
                if (_lignes.isNotEmpty)
                  Pastille(
                    '${_lignes.length} étudiant(s)',
                    couleur: AppCouleurs.bleu,
                  ),
              ],
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppCouleurs.rouge.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppCouleurs.rouge.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _erreur!,
                style: const TextStyle(color: AppCouleurs.rouge, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (options.isEmpty)
            CarteTableau(
              child: EtatVide(
                message: _mode == 'ue'
                    ? 'Aucune UE pour ce semestre. Créez d’abord une UE dans le module Formations.'
                    : 'Aucune ECUE pour ce semestre. Créez d’abord une ECUE dans le module Formations.',
                icone: Icons.layers_outlined,
              ),
            )
          else if (_cibleId == null)
            CarteTableau(
              child: EtatVide(
                message:
                    'Sélectionnez d’abord $libelleCible dans le filtre pour afficher les étudiants.',
                icone: Icons.filter_alt_outlined,
              ),
            )
          else if (_lignes.isEmpty)
            const CarteTableau(
              child: EtatVide(
                message: 'Aucun étudiant inscrit à ce niveau pour l’année universitaire du semestre.',
                icone: Icons.people_outline,
              ),
            )
          else
            CarteTableau(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  horizontalMargin: 18,
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('MATRICULE')),
                    DataColumn(label: Text('ÉTUDIANT')),
                    DataColumn(label: Text('GROUPE')),
                    DataColumn(label: Text('POINTS JURY')),
                    DataColumn(label: Text('MOYENNE / 20')),
                    DataColumn(label: Text('AUTO (10 − NOTE)')),
                  ],
                  rows: [for (final ligne in _lignes) _ligne(ligne)],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Les points jury sont des points complémentaires, généralement inférieurs à 1. '
            'Ils ne modifient pas la note affichée de l’UE ou de l’ECUE : ils servent à la '
            'validation et au calcul de la moyenne générale. '
            'Le bouton AUTO calcule automatiquement 10 − note (borné à 0). '
            'Laissez la case vide ou saisissez 0 pour ne rien accorder. '
            'Les résultats non verrouillés sont recalculés automatiquement.',
            style: TextStyle(
              fontSize: 11,
              color: AppCouleurs.texteDoux.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _ligne(Map<String, dynamic> ligne) {
    final inscriptionId = ligne['inscription_id'] as int;
    final moyenne = (ligne['moyenne'] as num?)?.toDouble();
    final auto = _auto[_cleAuto]?.contains(inscriptionId) ?? false;
    return DataRow(
      cells: [
        DataCell(Text('${ligne['matricule'] ?? '—'}')),
        DataCell(
          SizedBox(
            width: 210,
            child: Text(
              '${ligne['etudiant_nom'] ?? '—'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        DataCell(Text('${ligne['groupe_nom'] ?? '—'}')),
        DataCell(
          SizedBox(
            width: 130,
            child: TextField(
              controller: _points[inscriptionId],
              readOnly: auto,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Ex. 0,25',
                filled: auto,
                fillColor: AppCouleurs.teal.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 120,
            child: Text(
              noteTexte(ligne['moyenne']),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppCouleurs.bleu,
              ),
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: auto,
                  onChanged: moyenne == null
                      ? null
                      : (valeur) => _basculerAuto(inscriptionId, ligne, valeur),
                ),
              ),
              Text(
                auto ? 'AUTO' : 'Manuel',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: auto
                      ? AppCouleurs.teal
                      : AppCouleurs.texteDoux.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
