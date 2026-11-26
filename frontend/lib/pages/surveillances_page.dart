import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/surveillances.dart';
import '../widgets/ui.dart';

const _mimeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const _typesEvaluation = [
  'Examen',
  'Devoir',
  'Contrôle continu',
  'TP',
  'Oral',
  'Projet',
  'Rattrapage',
];

/// Espace « Surveillances » : saisie des surveillances d'évaluations,
/// statistiques par surveillant et importation depuis Excel.
class SurveillancesPage extends StatefulWidget {
  const SurveillancesPage({super.key});

  @override
  State<SurveillancesPage> createState() => _SurveillancesPageState();
}

class _SurveillancesPageState extends State<SurveillancesPage> {
  final TextEditingController _recherche = TextEditingController();
  int? _semestreId;
  int? _niveauId;
  int _onglet = 0;
  bool _initialise = false;
  bool _chargement = false;
  bool _telechargement = false;
  String? _erreur;
  List<Map<String, dynamic>> _elements = [];
  List<Map<String, dynamic>> _surveillants = [];
  Map<String, dynamic>? _statistiques;
  final ScrollController _defilementPage = ScrollController();
  final ScrollController _defilementListe = ScrollController();
  final ScrollController _defilementSurveillants = ScrollController();
  final ScrollController _defilementSemestres = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    _initialise = true;
    _semestreId = context.read<AppState>().semestreId;
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    _defilementPage.dispose();
    _defilementListe.dispose();
    _defilementSurveillants.dispose();
    _defilementSemestres.dispose();
    super.dispose();
  }

  Map<String, dynamic> _parametres() => {
    if (_semestreId != null) 'semestre_id': _semestreId,
    if (_niveauId != null) 'niveau_id': _niveauId,
    if (_recherche.text.trim().isNotEmpty) 'q': _recherche.text.trim(),
  };

  Future<void> _charger() async {
    final app = context.read<AppState>();
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final resultats = await Future.wait<dynamic>([
        app.api.liste('/surveillances', _parametres()),
        app.api.get('/surveillances/statistiques', _parametres()),
        app.api.liste('/surveillants'),
      ]);
      if (!mounted) return;
      setState(() {
        _elements = (resultats[0] as List)
            .map((element) => Map<String, dynamic>.from(element as Map))
            .toList();
        _statistiques = resultats[1] is Map
            ? Map<String, dynamic>.from(resultats[1] as Map)
            : null;
        _surveillants = (resultats[2] as List)
            .map((element) => Map<String, dynamic>.from(element as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _telechargerModele() async {
    final app = context.read<AppState>();
    setState(() => _telechargement = true);
    try {
      final contenu = await app.api.octets('/surveillances/modele');
      telechargerOctets(contenu, 'modele_import_surveillances.xlsx', _mimeXlsx);
      if (mounted) afficherMessage(context, 'Modèle Excel téléchargé');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _telechargement = false);
    }
  }

  Future<void> _exporter(String type) async {
    final app = context.read<AppState>();
    final statistiques = type == 'statistiques';
    setState(() => _telechargement = true);
    try {
      final contenu = await app.api.octets(
        statistiques
            ? '/surveillances/statistiques/exporter'
            : '/surveillances/exporter',
        _parametres(),
      );
      telechargerOctets(
        contenu,
        statistiques ? 'statistiques_surveillances.xlsx' : 'surveillances.xlsx',
        _mimeXlsx,
      );
      if (mounted) afficherMessage(context, 'Export Excel téléchargé');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _telechargement = false);
    }
  }

  Future<void> _ouvrirFormulaire([Map<String, dynamic>? element]) async {
    final app = context.read<AppState>();
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogueSurveillance(
        app: app,
        element: element,
        surveillants: _surveillants,
      ),
    );
    if (enregistre == true) _charger();
  }

  Future<void> _ouvrirSurveillants() async {
    final app = context.read<AppState>();
    await showDialog<bool>(
      context: context,
      builder: (_) => _DialogueSurveillants(app: app),
    );
    if (mounted) _charger();
  }

  Future<void> _ouvrirImport() async {
    final app = context.read<AppState>();
    await showDialog<bool>(
      context: context,
      builder: (_) => _DialogueImport(app: app, onImporte: _charger),
    );
  }

  Future<void> _supprimer(Map<String, dynamic> element) async {
    final app = context.read<AppState>();
    final confirme = await confirmer(
      context,
      titre: 'Supprimer la surveillance',
      message:
          'La surveillance de ${element['ecue_code']} du '
          '${formaterDate('${element['date_evaluation']}')} sera supprimée '
          'définitivement, avec ses surveillants.',
    );
    if (!confirme) return;
    try {
      await app.api.delete('/surveillances/${element['id']}');
      if (!mounted) return;
      afficherMessage(context, 'Surveillance supprimée');
      _charger();
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scrollbar(
      controller: _defilementPage,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _defilementPage,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EntetePage(
              titre: 'Surveillances',
              sousTitre:
                  'Planifiez les surveillants des évaluations et suivez la '
                  'charge de chacun.',
              actions: [
                OutlinedButton.icon(
                  onPressed: _ouvrirSurveillants,
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Surveillants'),
                ),
                OutlinedButton.icon(
                  onPressed: _telechargement ? null : _telechargerModele,
                  icon: _telechargement
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Modèle Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _ouvrirImport,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Importer'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Exporter en Excel',
                  enabled: !_telechargement,
                  onSelected: _exporter,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'surveillances',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.table_chart_outlined, size: 18),
                        title: Text(
                          'Surveillances',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'statistiques',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.query_stats_outlined, size: 18),
                        title: Text(
                          'Statistiques',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppCouleurs.bordure),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Exporter', style: TextStyle(fontSize: 13.5)),
                      ],
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _ouvrirFormulaire(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nouvelle surveillance'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _carteFiltres(app),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Surveillances'),
                  icon: Icon(Icons.event_note_outlined, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Statistiques'),
                  icon: Icon(Icons.query_stats_outlined, size: 18),
                ),
              ],
              selected: {_onglet},
              onSelectionChanged: (valeurs) =>
                  setState(() => _onglet = valeurs.first),
            ),
            const SizedBox(height: 16),
            if (_chargement) const LinearProgressIndicator(minHeight: 2),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppCouleurs.rouge.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppCouleurs.rouge.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _erreur!,
                    style: const TextStyle(color: AppCouleurs.rouge),
                  ),
                ),
              ),
            if (_onglet == 0) _vueSurveillances() else _vueStatistiques(),
          ],
        ),
      ),
    );
  }

  Widget _carteFiltres(AppState app) {
    return CarteSection(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<int?>(
              key: ValueKey<String>('filtre-semestre-$_semestreId'),
              initialValue: _semestreId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Semestre',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Tous les semestres'),
                ),
                for (final semestre in app.semestres)
                  DropdownMenuItem<int?>(
                    value: semestre['id'] as int,
                    child: Text(
                      '${semestre['nom']} · ${semestre['annee']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (valeur) {
                setState(() => _semestreId = valeur);
                _charger();
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int?>(
              key: ValueKey<String>('filtre-niveau-$_niveauId'),
              initialValue: _niveauId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Niveau',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Tous les niveaux'),
                ),
                for (final niveau in app.niveaux)
                  DropdownMenuItem<int?>(
                    value: niveau['id'] as int,
                    child: Text(
                      app.libelleNiveau(niveau['id']),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (valeur) {
                setState(() => _niveauId = valeur);
                _charger();
              },
            ),
          ),
          SizedBox(
            width: 300,
            child: TextField(
              controller: _recherche,
              onSubmitted: (_) => _charger(),
              decoration: InputDecoration(
                hintText: 'Rechercher un ECUE ou un surveillant',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _recherche.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Effacer',
                        onPressed: () {
                          _recherche.clear();
                          _charger();
                        },
                      ),
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: _charger,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _vueSurveillances() {
    if (_elements.isEmpty) {
      return CarteSection(
        child: EtatVide(
          message: _chargement
              ? 'Chargement des surveillances…'
              : 'Aucune surveillance pour ces filtres.',
          icone: Icons.event_available_outlined,
          action: FilledButton.icon(
            onPressed: () => _ouvrirFormulaire(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Saisir une surveillance'),
          ),
        ),
      );
    }
    return CarteSection(
      titre: '${_elements.length} surveillance(s)',
      sousTitre: 'Du plus récent au plus ancien',
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: Scrollbar(
        controller: _defilementListe,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _defilementListe,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('ECUE')),
              DataColumn(label: Text('Niveau')),
              DataColumn(label: Text('Semestre')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Durée')),
              DataColumn(label: Text('Surveillants')),
              DataColumn(label: Text('Salle')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final element in _elements)
                DataRow(
                  onSelectChanged: (_) => _ouvrirFormulaire(element),
                  cells: [
                    DataCell(
                      Text(
                        formaterDate('${element['date_evaluation']}'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 210,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${element['ecue_code'] ?? '—'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${element['ecue_nom'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppCouleurs.texteDoux,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text('${element['niveau_nom'] ?? '—'}')),
                    DataCell(
                      Text(
                        '${element['semestre_nom'] ?? '—'}'
                        '${(element['annee'] ?? '') == '' ? '' : ' · ${element['annee']}'}',
                      ),
                    ),
                    DataCell(
                      Pastille(
                        '${element['type_evaluation'] ?? '—'}',
                        couleur: _couleurType('${element['type_evaluation']}'),
                      ),
                    ),
                    DataCell(
                      Text(
                        formaterDuree(
                          (element['duree_minutes'] as num?)?.toInt(),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 230,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final surveillant
                                in (element['surveillants'] as List? ??
                                    const []))
                              _puceNom('${surveillant['nom'] ?? ''}'),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text('${element['salle'] ?? ''}')),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Modifier',
                            onPressed: () => _ouvrirFormulaire(element),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(element),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppCouleurs.rouge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _puceNom(String nom) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppCouleurs.bleu.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        nom,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppCouleurs.bleu,
        ),
      ),
    );
  }

  Color _couleurType(String type) {
    switch (sansAccents(type)) {
      case 'examen':
        return AppCouleurs.bleu;
      case 'devoir':
        return AppCouleurs.teal;
      case 'controle continu':
        return AppCouleurs.violet;
      case 'tp':
        return AppCouleurs.ambre;
      case 'rattrapage':
        return AppCouleurs.rouge;
      default:
        return AppCouleurs.texteDoux;
    }
  }

  Widget _vueStatistiques() {
    final statistiques = _statistiques;
    if (statistiques == null) {
      return CarteSection(
        child: EtatVide(
          message: _chargement
              ? 'Calcul des statistiques…'
              : 'Aucune statistique à afficher.',
          icone: Icons.query_stats_outlined,
        ),
      );
    }
    final resume = Map<String, dynamic>.from(
      statistiques['resume'] as Map? ?? const {},
    );
    final surveillants = (statistiques['par_surveillant'] as List? ?? const [])
        .map((ligne) => Map<String, dynamic>.from(ligne as Map))
        .toList();
    final semestres = (statistiques['par_semestre'] as List? ?? const [])
        .map((ligne) => Map<String, dynamic>.from(ligne as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: 220,
              child: CarteIndicateur(
                libelle: 'Surveillances',
                valeur: '${resume['surveillances'] ?? 0}',
                icone: Icons.event_note_outlined,
                couleur: AppCouleurs.bleu,
              ),
            ),
            SizedBox(
              width: 220,
              child: CarteIndicateur(
                libelle: 'Surveillants',
                valeur: '${resume['surveillants'] ?? 0}',
                icone: Icons.groups_outlined,
                couleur: AppCouleurs.teal,
              ),
            ),
            SizedBox(
              width: 220,
              child: CarteIndicateur(
                libelle: 'Jours de surveillance',
                valeur: '${resume['jours'] ?? 0}',
                detail: 'Dates distinctes',
                icone: Icons.calendar_today_outlined,
                couleur: AppCouleurs.violet,
              ),
            ),
            SizedBox(
              width: 220,
              child: CarteIndicateur(
                libelle: 'Durée totale',
                valeur: formaterDureeTotale(
                  (resume['duree_minutes'] as num?)?.toInt(),
                ),
                icone: Icons.timer_outlined,
                couleur: AppCouleurs.ambre,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        CarteSection(
          titre: 'Par surveillant',
          sousTitre:
              'Les jours correspondent aux dates distinctes de surveillance.',
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          child: surveillants.isEmpty
              ? const EtatVide(
                  message: 'Aucun surveillant sur la période sélectionnée.',
                  icone: Icons.groups_outlined,
                )
              : Scrollbar(
                  controller: _defilementSurveillants,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _defilementSurveillants,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Surveillant')),
                        DataColumn(label: Text('Jours'), numeric: true),
                        DataColumn(label: Text('Surveillances'), numeric: true),
                        DataColumn(label: Text('Durée'), numeric: true),
                        DataColumn(label: Text('Semestres')),
                        DataColumn(label: Text('Dernière date')),
                      ],
                      rows: [
                        for (final ligne in surveillants)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '${ligne['nom'] ?? '—'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${ligne['nombre_jours'] ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppCouleurs.teal,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text('${ligne['nombre_surveillances'] ?? 0}'),
                              ),
                              DataCell(
                                Text(
                                  formaterDureeTotale(
                                    (ligne['duree_minutes'] as num?)?.toInt(),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 260,
                                  child: Text(
                                    _libelleSemestres(ligne['semestres']),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formaterDate(
                                    '${ligne['derniere_date'] ?? ''}',
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 18),
        CarteSection(
          titre: 'Par semestre',
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          child: semestres.isEmpty
              ? const EtatVide(
                  message: 'Aucun semestre sur la période sélectionnée.',
                  icone: Icons.calendar_month_outlined,
                )
              : Scrollbar(
                  controller: _defilementSemestres,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _defilementSemestres,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Semestre')),
                        DataColumn(label: Text('Année')),
                        DataColumn(label: Text('Surveillances'), numeric: true),
                        DataColumn(label: Text('Jours'), numeric: true),
                        DataColumn(label: Text('Surveillants'), numeric: true),
                        DataColumn(label: Text('Durée'), numeric: true),
                      ],
                      rows: [
                        for (final ligne in semestres)
                          DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '${ligne['semestre_nom'] ?? '—'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(Text('${ligne['annee'] ?? ''}')),
                              DataCell(
                                Text('${ligne['nombre_surveillances'] ?? 0}'),
                              ),
                              DataCell(Text('${ligne['nombre_jours'] ?? 0}')),
                              DataCell(
                                Text('${ligne['nombre_surveillants'] ?? 0}'),
                              ),
                              DataCell(
                                Text(
                                  formaterDureeTotale(
                                    (ligne['duree_minutes'] as num?)?.toInt(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  String _libelleSemestres(dynamic semestres) {
    if (semestres is! List || semestres.isEmpty) return '—';
    return semestres
        .map(
          (element) =>
              '${element['nom']} (${element['nombre_surveillances'] ?? 0})',
        )
        .join(' · ');
  }
}

// ------------------------------------------------------------------ Formulaire
class _DialogueSurveillance extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic>? element;
  final List<Map<String, dynamic>> surveillants;

  const _DialogueSurveillance({
    required this.app,
    this.element,
    this.surveillants = const [],
  });

  @override
  State<_DialogueSurveillance> createState() => _DialogueSurveillanceState();
}

class _DialogueSurveillanceState extends State<_DialogueSurveillance> {
  final TextEditingController _duree = TextEditingController(text: '120');
  final TextEditingController _salle = TextEditingController();
  final TextEditingController _observation = TextEditingController();
  final TextEditingController _saisieSurveillant = TextEditingController();
  final List<Map<String, dynamic>> _surveillants = [];

  int? _ecueId;
  int? _niveauId;
  String _type = 'Examen';
  int _session = 1;
  DateTime? _date;
  bool _envoi = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final element = widget.element;
    if (element == null) return;
    _ecueId = element['ecue_id'] as int?;
    _niveauId = element['niveau_id'] as int?;
    _type = '${element['type_evaluation'] ?? 'Examen'}';
    _session = (element['session'] as num?)?.toInt() ?? 1;
    _date = DateTime.tryParse('${element['date_evaluation'] ?? ''}');
    _duree.text = '${(element['duree_minutes'] as num?)?.toInt() ?? 120}';
    _salle.text = '${element['salle'] ?? ''}';
    _observation.text = '${element['observation'] ?? ''}';
    for (final surveillant in (element['surveillants'] as List? ?? const [])) {
      _surveillants.add({
        'nom': '${surveillant['nom'] ?? ''}',
        'enseignant_id': surveillant['enseignant_id'],
        'surveillant_id': surveillant['surveillant_id'],
      });
    }
  }

  @override
  void dispose() {
    _duree.dispose();
    _salle.dispose();
    _observation.dispose();
    _saisieSurveillant.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _ecue {
    if (_ecueId == null) return null;
    for (final ecue in widget.app.ecues) {
      if (ecue['id'] == _ecueId) return ecue;
    }
    return null;
  }

  List<int> get _niveauxEcue => widget.app.niveauxECUE(_ecueId);

  void _ajouterSurveillant([
    String? nom,
    int? enseignantId,
    int? surveillantId,
  ]) {
    final valeur = (nom ?? _saisieSurveillant.text).trim();
    if (valeur.isEmpty) return;
    final cle = cleSurveillant(valeur);
    if (_surveillants.any(
      (surveillant) => cleSurveillant('${surveillant['nom']}') == cle,
    )) {
      _saisieSurveillant.clear();
      setState(() {});
      return;
    }
    var identifiantEnseignant = enseignantId;
    var identifiantSurveillant = surveillantId;
    if (identifiantEnseignant == null && identifiantSurveillant == null) {
      // Le registre des surveillants est prioritaire sur les enseignants.
      for (final surveillant in widget.surveillants) {
        if (surveillant['actif'] == false) continue;
        final noms = {
          cleSurveillant(
            '${surveillant['nom_affichage'] ?? surveillant['nom_complet'] ?? ''}',
          ),
          cleSurveillant('${surveillant['nom_complet'] ?? ''}'),
        };
        if (noms.contains(cle)) {
          identifiantSurveillant = surveillant['id'] as int?;
          break;
        }
      }
      if (identifiantSurveillant == null) {
        for (final enseignant in widget.app.enseignants) {
          final noms = {
            cleSurveillant('${enseignant['nom_affichage'] ?? ''}'),
            cleSurveillant('${enseignant['nom_complet'] ?? ''}'),
          };
          if (noms.contains(cle)) {
            identifiantEnseignant = enseignant['id'] as int?;
            break;
          }
        }
      }
    }
    setState(() {
      _surveillants.add({
        'nom': valeur,
        'enseignant_id': identifiantEnseignant,
        'surveillant_id': identifiantSurveillant,
      });
      _saisieSurveillant.clear();
    });
  }

  Future<void> _choisirDate() async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date de la surveillance',
    );
    if (choisie != null) setState(() => _date = choisie);
  }

  Future<void> _enregistrer() async {
    if (_ecueId == null) {
      setState(() => _erreur = 'Sélectionnez une ECUE.');
      return;
    }
    if (_date == null) {
      setState(() => _erreur = 'Choisissez la date de la surveillance.');
      return;
    }
    if (_surveillants.isEmpty) {
      setState(() => _erreur = 'Ajoutez au moins un surveillant.');
      return;
    }
    final duree = int.tryParse(_duree.text.trim());
    if (duree == null || duree <= 0) {
      setState(() => _erreur = 'Indiquez une durée en minutes (ex. 120).');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final corps = {
      'ecue_id': _ecueId,
      'niveau_id': _niveauId,
      'type_evaluation': _type,
      'duree_minutes': duree,
      'date_evaluation': _date!.toIso8601String().split('T').first,
      'session': _session,
      'salle': _salle.text.trim(),
      'observation': _observation.text.trim(),
      'surveillants': _surveillants,
    };
    try {
      if (widget.element == null) {
        await widget.app.api.post('/surveillances', corps);
      } else {
        await widget.app.api.put(
          '/surveillances/${widget.element!['id']}',
          corps,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.element == null
            ? 'Nouvelle surveillance'
            : 'Modifier la surveillance',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_erreur != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppCouleurs.rouge.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _erreur!,
                    style: const TextStyle(
                      color: AppCouleurs.rouge,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(width: 310, child: _champEcue()),
                  SizedBox(width: 310, child: _champNiveau()),
                  SizedBox(width: 310, child: _champSemestre()),
                  SizedBox(width: 310, child: _champType()),
                  SizedBox(width: 310, child: _champDuree()),
                  SizedBox(width: 310, child: _champSession()),
                  SizedBox(width: 310, child: _champDate()),
                  SizedBox(width: 310, child: _champSalle()),
                ],
              ),
              const SizedBox(height: 14),
              _champObservation(),
              const SizedBox(height: 18),
              _blocSurveillants(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _envoi ? null : _enregistrer,
          icon: _envoi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _champEcue() {
    final ecues = [...widget.app.ecues]
      ..sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
    return DropdownButtonFormField<int>(
      key: ValueKey<String>('ecue-$_ecueId'),
      initialValue: ecues.any((ecue) => ecue['id'] == _ecueId) ? _ecueId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'ECUE', isDense: true),
      items: [
        for (final ecue in ecues)
          DropdownMenuItem<int>(
            value: ecue['id'] as int,
            child: Text(
              '${ecue['code']} — ${ecue['nom']}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: (valeur) {
        setState(() {
          _ecueId = valeur;
          final niveaux = widget.app.niveauxECUE(valeur);
          _niveauId = niveaux.isEmpty ? null : niveaux.first;
        });
      },
    );
  }

  Widget _champNiveau() {
    final ids = _niveauxEcue;
    return DropdownButtonFormField<int>(
      key: ValueKey<String>('niveau-$_ecueId-$_niveauId'),
      initialValue: ids.contains(_niveauId) ? _niveauId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Niveau', isDense: true),
      items: [
        for (final id in ids)
          DropdownMenuItem<int>(
            value: id,
            child: Text(
              widget.app.libelleNiveau(id),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: ids.isEmpty
          ? null
          : (valeur) => setState(() => _niveauId = valeur),
    );
  }

  Widget _champSemestre() {
    final semestreId = _ecue?['semestre_id'];
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Semestre',
        isDense: true,
        helperText: 'Déduit de l’ECUE',
      ),
      child: Text(
        semestreId == null ? '—' : widget.app.libelleSemestre(semestreId),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _champType() {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('type-$_type'),
      initialValue: _typesEvaluation.contains(_type)
          ? _type
          : _typesEvaluation.first,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Type d’évaluation',
        isDense: true,
      ),
      items: [
        for (final type in _typesEvaluation)
          DropdownMenuItem(value: type, child: Text(type)),
      ],
      onChanged: (valeur) => setState(() => _type = valeur ?? 'Examen'),
    );
  }

  Widget _champDuree() {
    return TextField(
      controller: _duree,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Durée',
        suffixText: 'min',
        isDense: true,
      ),
    );
  }

  Widget _champSession() {
    return DropdownButtonFormField<int>(
      key: ValueKey<int>(_session),
      initialValue: _session,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Session', isDense: true),
      items: const [
        DropdownMenuItem(value: 1, child: Text('Session 1 (normale)')),
        DropdownMenuItem(value: 2, child: Text('Session 2 (rattrapage)')),
      ],
      onChanged: (valeur) => setState(() => _session = valeur ?? 1),
    );
  }

  Widget _champDate() {
    return InkWell(
      onTap: _choisirDate,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          isDense: true,
          suffixIcon: Icon(Icons.event_outlined, size: 20),
        ),
        child: Text(
          _date == null
              ? 'Choisir une date'
              : formaterDate(_date!.toIso8601String()),
          style: TextStyle(
            fontSize: 13,
            color: _date == null ? const Color(0xFF94A3B8) : AppCouleurs.texte,
          ),
        ),
      ),
    );
  }

  Widget _champSalle() {
    return TextField(
      controller: _salle,
      decoration: const InputDecoration(
        labelText: 'Salle (facultatif)',
        isDense: true,
      ),
    );
  }

  Widget _champObservation() {
    return TextField(
      controller: _observation,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Observation (facultatif)',
        isDense: true,
      ),
    );
  }

  Widget _blocSurveillants() {
    final texte = cleSurveillant(_saisieSurveillant.text);
    final deja = _surveillants
        .map((surveillant) => cleSurveillant('${surveillant['nom']}'))
        .toSet();
    final propositions = <Map<String, dynamic>>[];
    final vus = <String>{};
    if (texte.isNotEmpty) {
      for (final surveillant in widget.surveillants) {
        if (surveillant['actif'] == false) continue;
        final nom =
            '${surveillant['nom_affichage'] ?? surveillant['nom_complet'] ?? ''}';
        final cle = cleSurveillant(nom);
        if (cle.isEmpty ||
            !cle.contains(texte) ||
            deja.contains(cle) ||
            !vus.add(cle)) {
          continue;
        }
        propositions.add({'nom': nom, 'surveillant_id': surveillant['id']});
      }
      for (final enseignant in widget.app.enseignants) {
        final nom = widget.app.libelleEnseignant(
          Map<String, dynamic>.from(enseignant),
        );
        final cle = cleSurveillant(nom);
        if (cle.isEmpty ||
            !cle.contains(texte) ||
            deja.contains(cle) ||
            !vus.add(cle)) {
          continue;
        }
        propositions.add({'nom': nom, 'enseignant_id': enseignant['id']});
      }
    }
    final suggestions = propositions.take(8).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Surveillants',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ajoutez un ou plusieurs surveillants. Les noms peuvent être '
            'libres, choisis dans le registre des surveillants ou parmi les '
            'enseignants.',
            style: TextStyle(fontSize: 11.5, color: AppCouleurs.texteDoux),
          ),
          const SizedBox(height: 10),
          if (_surveillants.isEmpty)
            const Text(
              'Aucun surveillant ajouté.',
              style: TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var index = 0; index < _surveillants.length; index++)
                  InputChip(
                    avatar: Icon(
                      _surveillants[index]['surveillant_id'] != null
                          ? Icons.badge_outlined
                          : Icons.person_outline,
                      size: 16,
                    ),
                    label: Text('${_surveillants[index]['nom']}'),
                    onDeleted: () =>
                        setState(() => _surveillants.removeAt(index)),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _saisieSurveillant,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _ajouterSurveillant(),
                  decoration: const InputDecoration(
                    hintText: 'Nom du surveillant',
                    isDense: true,
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _ajouterSurveillant,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final proposition in suggestions)
                  ActionChip(
                    avatar: Icon(
                      proposition['surveillant_id'] != null
                          ? Icons.badge_outlined
                          : Icons.school_outlined,
                      size: 15,
                    ),
                    label: Text('${proposition['nom']}'),
                    onPressed: () => _ajouterSurveillant(
                      '${proposition['nom']}',
                      proposition['enseignant_id'] as int?,
                      proposition['surveillant_id'] as int?,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Import Excel
class _DialogueImport extends StatefulWidget {
  final AppState app;
  final VoidCallback? onImporte;

  const _DialogueImport({required this.app, this.onImporte});

  @override
  State<_DialogueImport> createState() => _DialogueImportState();
}

class _DialogueImportState extends State<_DialogueImport> {
  PlatformFile? _fichier;
  Uint8List? _octets;
  bool _envoi = false;
  bool _telechargement = false;
  Map<String, dynamic>? _rapport;
  String? _erreur;

  Future<void> _telechargerModele() async {
    setState(() => _telechargement = true);
    try {
      final contenu = await widget.app.api.octets('/surveillances/modele');
      telechargerOctets(contenu, 'modele_import_surveillances.xlsx', _mimeXlsx);
      if (mounted) afficherMessage(context, 'Modèle Excel téléchargé');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _telechargement = false);
    }
  }

  Future<void> _choisirFichier() async {
    try {
      final fichier = await FilePicker.pickFile(
        dialogTitle: 'Sélectionner un classeur Excel',
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xlsm'],
      );
      if (fichier == null) return;
      final octets = await fichier.readAsBytes();
      if (!mounted) return;
      setState(() {
        _fichier = fichier;
        _octets = octets;
        _rapport = null;
        _erreur = null;
      });
    } catch (e) {
      if (mounted) {
        afficherMessage(
          context,
          'Sélection annulée ou impossible : $e',
          erreur: true,
        );
      }
    }
  }

  Future<void> _importer() async {
    if (_fichier == null || _octets == null) {
      setState(() => _erreur = 'Sélectionnez d’abord un classeur Excel.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
      _rapport = null;
    });
    try {
      final rapport = await widget.app.api.envoyerFichier(
        '/surveillances/importer',
        _fichier!.name,
        _octets!,
      );
      if (!mounted) return;
      setState(() => _rapport = rapport);
      widget.onImporte?.call();
      afficherMessage(context, '${rapport['message']}');
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Importer des surveillances',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choisissez le classeur Excel rempli à partir du modèle. '
                'Une ligne correspond à une surveillance ; plusieurs '
                'surveillants se séparent par « ; », « | » ou « / ».',
                style: TextStyle(fontSize: 12.5, color: AppCouleurs.texteDoux),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _telechargement ? null : _telechargerModele,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Télécharger le modèle'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _envoi ? null : _choisirFichier,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(
                      _fichier == null ? 'Choisir un fichier' : 'Changer',
                    ),
                  ),
                ],
              ),
              if (_fichier != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: AppCouleurs.teal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _fichier!.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${((_octets?.length ?? 0) / 1024).toStringAsFixed(1)} Ko',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ],
                ),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppCouleurs.rouge.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _erreur!,
                    style: const TextStyle(
                      color: AppCouleurs.rouge,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
              if (_rapport != null) ...[
                const SizedBox(height: 14),
                _carteRapport(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.pop(context, true),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          onPressed: _envoi ? null : _importer,
          icon: _envoi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Importer'),
        ),
      ],
    );
  }

  Widget _carteRapport() {
    final rapport = _rapport!;
    final erreurs = (rapport['erreurs'] as List? ?? const [])
        .map((erreur) => Map<String, dynamic>.from(erreur as Map))
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${rapport['message'] ?? 'Import terminé.'}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '${rapport['importes'] ?? 0} importée(s) · '
            '${rapport['crees'] ?? 0} créée(s) · '
            '${rapport['mis_a_jour'] ?? 0} mise(s) à jour',
            style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
          ),
          if (erreurs.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Lignes non importées',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: AppCouleurs.rouge,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final erreur in erreurs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Ligne ${erreur['ligne']} : ${erreur['message']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppCouleurs.texteDoux,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Registre
class _DialogueSurveillants extends StatefulWidget {
  final AppState app;

  const _DialogueSurveillants({required this.app});

  @override
  State<_DialogueSurveillants> createState() => _DialogueSurveillantsState();
}

class _DialogueSurveillantsState extends State<_DialogueSurveillants> {
  final TextEditingController _recherche = TextEditingController();
  final ScrollController _defilement = ScrollController();
  List<Map<String, dynamic>> _elements = [];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final elements = await widget.app.api.liste('/surveillants');
      if (!mounted) return;
      setState(() => _elements = elements);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  List<Map<String, dynamic>> get _filtres {
    final texte = cleSurveillant(_recherche.text);
    if (texte.isEmpty) return _elements;
    return _elements.where((element) {
      final contenu = cleSurveillant(
        [
          element['prenom'],
          element['nom'],
          element['telephone'],
          element['email'],
          element['matricule'],
          element['lieu_naissance'],
          element['fonction'],
        ].where((valeur) => valeur != null).join(' '),
      );
      return contenu.contains(texte);
    }).toList();
  }

  Future<void> _ouvrirFiche([Map<String, dynamic>? element]) async {
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogueFicheSurveillant(
        app: widget.app,
        element: element,
      ),
    );
    if (enregistre == true) _charger();
  }

  Future<void> _supprimer(Map<String, dynamic> element) async {
    final nom = '${element['nom_complet'] ?? element['nom'] ?? ''}'.trim();
    final confirme = await confirmer(
      context,
      titre: 'Supprimer le surveillant',
      message:
          'La fiche de ${nom.isEmpty ? 'ce surveillant' : nom} sera supprimée. '
          'Les surveillances déjà enregistrées conservent son nom.',
    );
    if (!confirme) return;
    try {
      await widget.app.api.delete('/surveillants/${element['id']}');
      if (!mounted) return;
      afficherMessage(context, 'Surveillant supprimé');
      _charger();
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final elements = _filtres;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.badge_outlined, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('Registre des surveillants')),
          Text(
            '${_elements.length} fiche(s)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppCouleurs.texteDoux,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _recherche,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un nom, un téléphone, un email…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _ouvrirFiche(),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Nouveau surveillant'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_erreur != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppCouleurs.rouge.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _erreur!,
                  style: const TextStyle(
                    color: AppCouleurs.rouge,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_chargement) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: elements.isEmpty
                  ? EtatVide(
                      message: _chargement
                          ? 'Chargement du registre…'
                          : 'Aucun surveillant enregistré.',
                      icone: Icons.badge_outlined,
                      action: FilledButton.icon(
                        onPressed: () => _ouvrirFiche(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Ajouter un surveillant'),
                      ),
                    )
                  : Scrollbar(
                      controller: _defilement,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _defilement,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            showCheckboxColumn: false,
                            columns: const [
                              DataColumn(label: Text('Nom complet')),
                              DataColumn(label: Text('Téléphone')),
                              DataColumn(label: Text('Email')),
                              DataColumn(label: Text('Naissance')),
                              DataColumn(label: Text('Lieu de naissance')),
                              DataColumn(label: Text('Fonction')),
                              DataColumn(label: Text('Statut')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: [
                              for (final element in elements)
                                DataRow(
                                  onSelectChanged: (_) => _ouvrirFiche(element),
                                  cells: [
                                    DataCell(
                                      SizedBox(
                                        width: 210,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${element['nom_complet'] ?? '—'}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (element['matricule'] !=
                                                null &&
                                                '${element['matricule']}'
                                                    .isNotEmpty)
                                              Text(
                                                '${element['matricule']}',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color:
                                                      AppCouleurs.texteDoux,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text('${element['telephone'] ?? ''}'),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 210,
                                        child: Text(
                                          '${element['email'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        formaterDate(
                                          '${element['date_naissance'] ?? ''}',
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text('${element['lieu_naissance'] ?? ''}'),
                                    ),
                                    DataCell(
                                      Text('${element['fonction'] ?? ''}'),
                                    ),
                                    DataCell(
                                      element['actif'] == false
                                          ? const Pastille(
                                              'Inactif',
                                              couleur: AppCouleurs.texteDoux,
                                            )
                                          : const Pastille(
                                              'Actif',
                                              couleur: AppCouleurs.vert,
                                            ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Modifier',
                                            onPressed: () =>
                                                _ouvrirFiche(element),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Supprimer',
                                            onPressed: () =>
                                                _supprimer(element),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: AppCouleurs.rouge,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
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
}

class _DialogueFicheSurveillant extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic>? element;

  const _DialogueFicheSurveillant({required this.app, this.element});

  @override
  State<_DialogueFicheSurveillant> createState() =>
      _DialogueFicheSurveillantState();
}

class _DialogueFicheSurveillantState extends State<_DialogueFicheSurveillant> {
  late final TextEditingController _prenom;
  late final TextEditingController _nom;
  late final TextEditingController _lieuNaissance;
  late final TextEditingController _telephone;
  late final TextEditingController _email;
  late final TextEditingController _matricule;
  late final TextEditingController _fonction;
  late final TextEditingController _observation;

  DateTime? _dateNaissance;
  bool _actif = true;
  bool _envoi = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final element = widget.element;
    _prenom = TextEditingController(text: '${element?['prenom'] ?? ''}');
    _nom = TextEditingController(text: '${element?['nom'] ?? ''}');
    _lieuNaissance = TextEditingController(
      text: '${element?['lieu_naissance'] ?? ''}',
    );
    _telephone = TextEditingController(text: '${element?['telephone'] ?? ''}');
    _email = TextEditingController(text: '${element?['email'] ?? ''}');
    _matricule = TextEditingController(text: '${element?['matricule'] ?? ''}');
    _fonction = TextEditingController(text: '${element?['fonction'] ?? ''}');
    _observation = TextEditingController(
      text: '${element?['observation'] ?? ''}',
    );
    _dateNaissance = DateTime.tryParse('${element?['date_naissance'] ?? ''}');
    _actif = element?['actif'] != false;
  }

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    _lieuNaissance.dispose();
    _telephone.dispose();
    _email.dispose();
    _matricule.dispose();
    _fonction.dispose();
    _observation.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: _dateNaissance ?? DateTime(1990),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      helpText: 'Date de naissance',
    );
    if (choisie != null) setState(() => _dateNaissance = choisie);
  }

  Future<void> _enregistrer() async {
    final nom = _nom.text.trim();
    if (nom.isEmpty) {
      setState(() => _erreur = 'Le nom est obligatoire.');
      return;
    }
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        (!email.contains('@') || !email.split('@').last.contains('.'))) {
      setState(() => _erreur = 'Adresse email invalide.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final corps = <String, dynamic>{
      'prenom': _prenom.text.trim(),
      'nom': nom,
      'date_naissance': _dateNaissance?.toIso8601String().split('T').first,
      'lieu_naissance': _lieuNaissance.text.trim(),
      'telephone': _telephone.text.trim(),
      'email': email,
      'matricule': _matricule.text.trim(),
      'fonction': _fonction.text.trim(),
      'observation': _observation.text.trim(),
      'actif': _actif,
    };
    try {
      if (widget.element == null) {
        await widget.app.api.post('/surveillants', corps);
      } else {
        await widget.app.api.put(
          '/surveillants/${widget.element!['id']}',
          corps,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.element == null
            ? 'Nouveau surveillant'
            : 'Modifier le surveillant',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_erreur != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppCouleurs.rouge.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _erreur!,
                    style: const TextStyle(
                      color: AppCouleurs.rouge,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(width: 300, child: _champPrenom()),
                  SizedBox(width: 300, child: _champNom()),
                  SizedBox(width: 300, child: _champDate()),
                  SizedBox(width: 300, child: _champLieu()),
                  SizedBox(width: 300, child: _champTelephone()),
                  SizedBox(width: 300, child: _champEmail()),
                  SizedBox(width: 300, child: _champMatricule()),
                  SizedBox(width: 300, child: _champFonction()),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _observation,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observation (facultatif)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Surveillant actif',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Les fiches inactives restent dans l’historique mais ne sont '
                  'plus proposées.',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: _actif,
                onChanged: (valeur) => setState(() => _actif = valeur),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _envoi ? null : _enregistrer,
          icon: _envoi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _champPrenom() => TextField(
        controller: _prenom,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Prénom',
          isDense: true,
        ),
      );

  Widget _champNom() => TextField(
        controller: _nom,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nom',
          isDense: true,
        ),
      );

  Widget _champLieu() => TextField(
        controller: _lieuNaissance,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Lieu de naissance',
          isDense: true,
        ),
      );

  Widget _champTelephone() => TextField(
        controller: _telephone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Téléphone',
          isDense: true,
        ),
      );

  Widget _champEmail() => TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Email',
          isDense: true,
        ),
      );

  Widget _champMatricule() => TextField(
        controller: _matricule,
        decoration: const InputDecoration(
          labelText: 'Matricule (facultatif)',
          isDense: true,
        ),
      );

  Widget _champFonction() => TextField(
        controller: _fonction,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Fonction (facultatif)',
          hintText: 'Enseignant, vacataire, personnel…',
          isDense: true,
        ),
      );

  Widget _champDate() {
    return InkWell(
      onTap: _choisirDate,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date de naissance',
          isDense: true,
          suffixIcon: _dateNaissance == null
              ? const Icon(Icons.event_outlined, size: 20)
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _dateNaissance = null),
                ),
        ),
        child: Text(
          _dateNaissance == null
              ? 'Choisir une date'
              : formaterDate(_dateNaissance!.toIso8601String()),
          style: TextStyle(
            fontSize: 13,
            color: _dateNaissance == null
                ? const Color(0xFF94A3B8)
                : AppCouleurs.texte,
          ),
        ),
      ),
    );
  }
}
