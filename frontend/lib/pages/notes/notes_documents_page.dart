import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Module 7 — Documents : relevés, PV de délibération et attestations.
class NotesDocumentsPage extends StatefulWidget {
  const NotesDocumentsPage({super.key});

  @override
  State<NotesDocumentsPage> createState() => _NotesDocumentsPageState();
}

class _NotesDocumentsPageState extends State<NotesDocumentsPage> {
  int? _semestreId;
  int _session = 1;
  int? _niveauId;
  bool _chargement = false;
  bool _initialise = false;
  String? _erreur;
  String _filtre = '';
  List<Map<String, dynamic>> _inscriptions = [];
  List<Map<String, dynamic>> _mesReleves = [];
  List<Map<String, dynamic>> _diplomes = [];
  bool _chargementDiplomes = false;
  final _recherche = TextEditingController();
  final _scrollVertical = ScrollController();
  final _scrollHorizontal = ScrollController();

  static const _grades = [
    'Professeur',
    'Maître de Conférences',
    'Maître Assistant',
    'Assistant',
  ];
  static const _fonctions = [
    'Le Chef du Département de la formation',
    'La Directrice Générale',
    'Le Directeur Général',
    'Le Directeur Général Adjoint',
    'Le Président du jury',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!_initialise) {
      _initialise = true;
      _semestreId = app.semestreId;
      _charger();
    } else if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _charger();
    }
  }

  @override
  void dispose() {
    _recherche.dispose();
    _scrollVertical.dispose();
    _scrollHorizontal.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      if (app.estLecteur) {
        final releves = await app.api.liste('/notes/mes-releves', {
          'session': _session,
        });
        if (mounted) {
          setState(() {
            _mesReleves = releves;
            _filtre = '';
            _recherche.clear();
          });
        }
        return;
      }
      final inscriptions = await app.api.liste('/notes/inscriptions', {
        if (!app.estLecteur && _niveauId != null) 'niveau_id': _niveauId,
      });
      if (mounted) {
        setState(() {
          _inscriptions = inscriptions;
          _filtre = '';
          _recherche.clear();
        });
      }
      if (!app.estLecteur) await _chargerDiplomes();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _chargerDiplomes() async {
    final app = context.read<AppState>();
    setState(() => _chargementDiplomes = true);
    try {
      final diplomes = await app.api.liste('/notes/documents/diplomes', {
        if (_anneeSemestre.isNotEmpty) 'annee': _anneeSemestre,
        if (_niveauId != null) 'niveau_id': _niveauId,
      });
      if (mounted) setState(() => _diplomes = diplomes);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargementDiplomes = false);
    }
  }

  String get _anneeSemestre {
    final app = context.read<AppState>();
    final semestre = app.semestres.firstWhere(
      (s) => s['id'] == _semestreId,
      orElse: () => app.semestres.isEmpty ? <String, dynamic>{} : app.semestres.first,
    );
    return '${semestre['annee'] ?? ''}';
  }

  List<Map<String, dynamic>> get _affichees {
    // L'étudiant voit toutes ses inscriptions (et donc tous ses relevés)
    // sur une seule page, sans filtre par année.
    if (context.read<AppState>().estLecteur) return _mesReleves;
    final annee = _anneeSemestre;
    final cible = _filtre.trim().toLowerCase();
    return _inscriptions.where((inscription) {
      if (annee.isNotEmpty && '${inscription['annee'] ?? ''}' != annee) return false;
      if (cible.isEmpty) return true;
      return '${inscription['matricule']} ${inscription['etudiant_nom']} ${inscription['niveau_nom']}'
          .toLowerCase()
          .contains(cible);
    }).toList();
  }

  /// Semestres du parcours d'une année (pour proposer un relevé par semestre
  /// à l'étudiant), d'après `/notes/mes-releves`.
  List<Map<String, dynamic>> _semestresInscription(
    AppState app,
    Map<String, dynamic> inscription,
  ) {
    final semestres = inscription['semestres'];
    if (semestres is List) {
      return semestres.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  /// Formate une moyenne (ou « — » lorsque non calculable).
  String _valeurMoyenne(dynamic valeur) {
    if (valeur == null) return '—';
    final nombre = valeur is num ? valeur : num.tryParse('$valeur');
    if (nombre == null) return '$valeur';
    return nombre.toStringAsFixed(2);
  }

  /// Suffixe d'une année universitaire : « 2025-2026 » → « 25-26 ».
  String _suffixeAnnee(dynamic annee) {
    final morceaux = '${annee ?? ''}'.split('-');
    if (morceaux.length >= 2 &&
        morceaux[0].length >= 4 &&
        morceaux[1].length >= 2) {
      return '${morceaux[0].substring(2)}-${morceaux[1].substring(2)}';
    }
    return '${annee ?? ''}';
  }

  void _telechargerReleve(
    Map<String, dynamic> inscription, {
    int? semestreId,
  }) {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/releve/${inscription['inscription_id'] ?? inscription['id']}',
      'releve_${inscription['matricule']}_S$_session.pdf',
      'application/pdf',
      parametres: {'semestre_id': semestreId ?? _semestreId, 'session': _session},
    );
  }

  void _telechargerRelevePassage(Map<String, dynamic> inscription) {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/passage/${inscription['inscription_id'] ?? inscription['id']}',
      'releve_passage_${inscription['matricule']}_${inscription['annee']}.pdf',
      'application/pdf',
      parametres: {'session': _session},
    );
  }

  void _telechargerAttestation(Map<String, dynamic> inscription) {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/attestation/${inscription['id']}',
      'attestation_${inscription['matricule']}_S$_session.pdf',
      'application/pdf',
      parametres: {'semestre_id': _semestreId, 'session': _session},
    );
  }

  void _telechargerPv() {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/pv',
      'pv_deliberation_S$_session.pdf',
      'application/pdf',
      parametres: {
        'semestre_id': _semestreId,
        'session': _session,
        if (_niveauId != null) 'niveau_id': _niveauId,
      },
    );
  }

  void _telechargerLot() {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/releves',
      'releves_S$_session.zip',
      'application/zip',
      parametres: {
        'semestre_id': _semestreId,
        'session': _session,
        if (_niveauId != null) 'niveau_id': _niveauId,
      },
    );
  }

  void _telechargerDiplome(Map<String, dynamic> diplome) {
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/diplome/${diplome['etudiant_id']}',
      'attestation_diplome_${diplome['matricule']}_${diplome['cycle']}.pdf',
      'application/pdf',
      parametres: {'cycle': diplome['cycle']},
    );
  }

  void _telechargerModele() {
    if (_niveauId == null) {
      afficherMessage(
        context,
        'Choisissez d’abord un niveau pour le modèle de saisie.',
        erreur: true,
      );
      return;
    }
    final app = context.read<AppState>();
    telechargerDepuisApi(
      context,
      app,
      '/notes/documents/modele-saisie',
      'modele_saisie_S$_session.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      parametres: {
        'semestre_id': _semestreId,
        'niveau_id': _niveauId,
        'session': _session,
      },
    );
  }

  Future<void> _ouvrirSignataires() async {
    final app = context.read<AppState>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DialogueSignataires(
        app: app,
        grades: _grades,
        fonctions: _fonctions,
      ),
    );
    if (mounted) _charger();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final inscriptions = _affichees;
    final etudiant = app.estLecteur;

    return Scrollbar(
      controller: _scrollVertical,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollVertical,
        padding: const EdgeInsets.all(24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: etudiant ? 'Mes relevés de notes' : 'Documents',
            sousTitre: etudiant
                ? 'Tous vos relevés de notes officiels, par année et par semestre.'
                : 'Relevés de notes, procès-verbaux de délibération et attestations.',
            actions: etudiant
                ? const []
                : [
                    OutlinedButton.icon(
                      onPressed: _ouvrirSignataires,
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: const Text('Signataires'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _semestreId == null ? null : _telechargerPv,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('PV de délibération'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _semestreId == null ? null : _telechargerLot,
                      icon: const Icon(Icons.folder_zip_outlined, size: 18),
                      label: const Text('Tous les relevés (ZIP)'),
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
                if (!etudiant)
                  selecteurSemestre(
                    app,
                    _semestreId,
                    (valeur) => app.selectionnerSemestre(valeur),
                  ),
                selecteurSession(_session, (valeur) {
                  setState(() => _session = valeur ?? 1);
                  if (etudiant) _charger();
                }),
                if (!etudiant)
                  selecteurNiveau(app, _niveauId, (valeur) {
                    setState(() => _niveauId = valeur);
                    _charger();
                  }),
                if (!etudiant)
                  FilledButton.icon(
                    onPressed: _telechargerModele,
                    icon: const Icon(Icons.table_view_outlined, size: 18),
                    label: const Text('Modèle de saisie'),
                  ),
                Pastille(
                  _chargement
                      ? 'Chargement…'
                      : etudiant
                          ? '${inscriptions.length} année(s)'
                          : '${inscriptions.length} étudiant(s)',
                  couleur: AppCouleurs.teal,
                ),
                Pastille('Session $_session'),
              ],
            ),
          ),
          if (!etudiant) ...[
            const SizedBox(height: 14),
            Text(
              'Le modèle de saisie contient une feuille par ECUE du niveau sélectionné. '
              'Une cellule vide signifie qu’aucune évaluation de ce type n’existe.',
              style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
            ),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 14),
            Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
          ],
          const SizedBox(height: 16),
          CarteTableau(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      if (!etudiant)
                        ChampRecherche(
                          controleur: _recherche,
                          hint: 'Rechercher un étudiant…',
                          onChanged: (v) => setState(() => _filtre = v),
                        )
                      else
                        Text(
                          app.utilisateur?.nomComplet ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        etudiant
                            ? 'Toutes les années'
                            : 'Année ${_anneeSemestre.isEmpty ? '—' : _anneeSemestre}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppCouleurs.texteDoux,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_chargement)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (inscriptions.isEmpty)
                  EtatVide(
                    message: etudiant
                        ? 'Aucune inscription à votre nom pour le moment.'
                        : 'Aucun étudiant inscrit pour ces critères.',
                    icone: Icons.people_outline,
                  )
                else
                  Scrollbar(
                    controller: _scrollHorizontal,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollHorizontal,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 18,
                        horizontalMargin: 18,
                        showCheckboxColumn: false,
                        columns: [
                          if (!etudiant) const DataColumn(label: Text('MATRICULE')),
                          if (!etudiant) const DataColumn(label: Text('ÉTUDIANT')),
                          if (etudiant) const DataColumn(label: Text('ANNÉE')),
                          const DataColumn(label: Text('NIVEAU')),
                          if (etudiant) const DataColumn(label: Text('FILIÈRE')),
                          const DataColumn(label: Text('GROUPE')),
                          if (etudiant) const DataColumn(label: Text('MOYENNE')),
                          if (etudiant) const DataColumn(label: Text('DÉCISION')),
                          if (!etudiant) const DataColumn(label: Text('STATUT')),
                          if (etudiant) const DataColumn(label: Text('RELEVÉS')),
                          if (etudiant) const DataColumn(label: Text('RELEVÉ ANNUEL')),
                          if (!etudiant) const DataColumn(label: Text('DOCUMENTS')),
                        ],
                        rows: [
                          for (final inscription in inscriptions)
                            DataRow(
                              cells: [
                                if (!etudiant)
                                  DataCell(Text('${inscription['matricule'] ?? '—'}')),
                                if (!etudiant)
                                  DataCell(
                                    SizedBox(
                                      width: 190,
                                      child: Text(
                                        '${inscription['etudiant_nom'] ?? '—'}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                if (etudiant)
                                  DataCell(Text('${inscription['annee'] ?? '—'}')),
                                DataCell(Text('${inscription['niveau_nom'] ?? '—'}')),
                                if (etudiant)
                                  DataCell(Text('${inscription['filiere_nom'] ?? '—'}')),
                                DataCell(Text('${inscription['groupe_nom'] ?? '—'}')),
                                if (etudiant)
                                  DataCell(
                                    Text(
                                      _valeurMoyenne(inscription['moyenne_annee']),
                                    ),
                                  ),
                                if (etudiant)
                                  DataCell(
                                    Pastille(
                                      '${inscription['decision'] ?? '—'}',
                                      couleur: couleurStatut(
                                        '${inscription['decision'] ?? ''}',
                                      ),
                                    ),
                                  ),
                                if (!etudiant)
                                  DataCell(
                                    Pastille(
                                      '${inscription['statut'] ?? '—'}',
                                      couleur: couleurStatut('${inscription['statut'] ?? ''}'),
                                    ),
                                  ),
                                if (etudiant)
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      spacing: 4,
                                      children: [
                                        for (final semestre
                                            in _semestresInscription(app, inscription))
                                          TextButton.icon(
                                            onPressed: semestre['id'] is int
                                                ? () => _telechargerReleve(
                                                      inscription,
                                                      semestreId: semestre['id'] as int,
                                                    )
                                                : null,
                                            icon: const Icon(
                                              Icons.picture_as_pdf_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              '${semestre['nom'] ?? 'Relevé'}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (etudiant)
                                  DataCell(
                                    TextButton.icon(
                                      onPressed: () =>
                                          _telechargerRelevePassage(inscription),
                                      icon: const Icon(
                                        Icons.summarize_outlined,
                                        size: 16,
                                      ),
                                      label: Text(
                                        'Relevé passage-'
                                        '${_suffixeAnnee(inscription['annee'])}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                if (!etudiant)
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () => _telechargerReleve(inscription),
                                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                          label: const Text('Relevé'),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => _telechargerAttestation(inscription),
                                          icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                                          label: const Text('Attestation'),
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
              ],
            ),
          ),
          if (!etudiant) ...[
            const SizedBox(height: 24),
            CarteSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attestations de réussite de diplôme',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppCouleurs.texte,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Étudiants ayant validé les conditions d’un diplôme '
                              '(Licence, Master ou Grade d’ingénieur).',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppCouleurs.texteDoux,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _chargementDiplomes ? null : _chargerDiplomes,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Actualiser'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_chargementDiplomes)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_diplomes.isEmpty)
                    const EtatVide(
                      message: 'Aucun étudiant éligible à une attestation de diplôme '
                          'pour ces critères.',
                      icone: Icons.workspace_premium_outlined,
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 18,
                        horizontalMargin: 8,
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('MATRICULE')),
                          DataColumn(label: Text('ÉTUDIANT')),
                          DataColumn(label: Text('DIPLÔME')),
                          DataColumn(label: Text('SEMESTRES VALIDÉS')),
                          DataColumn(label: Text('ANNÉE')),
                          DataColumn(label: Text('DOCUMENT')),
                        ],
                        rows: [
                          for (final diplome in _diplomes)
                            DataRow(
                              cells: [
                                DataCell(Text('${diplome['matricule'] ?? '—'}')),
                                DataCell(
                                  SizedBox(
                                    width: 190,
                                    child: Text(
                                      '${diplome['etudiant'] ?? '—'}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Pastille(
                                    '${diplome['diplome'] ?? '—'}',
                                    couleur: AppCouleurs.violet,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${diplome['semestres_valides'] ?? 0} / '
                                    '${diplome['semestres_requis'] ?? 0}',
                                  ),
                                ),
                                DataCell(Text('${diplome['annee_validation'] ?? '—'}')),
                                DataCell(
                                  TextButton.icon(
                                    onPressed: () => _telechargerDiplome(diplome),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Attestation'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          ],
        ),
      ),
    );
  }
}

/// Boîte de dialogue de paramétrage des signataires (relevé, PV, attestation).
class _DialogueSignataires extends StatefulWidget {
  final AppState app;
  final List<String> grades;
  final List<String> fonctions;

  const _DialogueSignataires({
    required this.app,
    required this.grades,
    required this.fonctions,
  });

  @override
  State<_DialogueSignataires> createState() => _DialogueSignatairesState();
}

class _DialogueSignatairesState extends State<_DialogueSignataires> {
  static const _types = [
    ('releve', 'Relevé de notes'),
    ('pv', 'PV de délibération'),
    ('attestation', 'Attestation'),
  ];

  final Map<String, TextEditingController> _noms = {
    'releve': TextEditingController(),
    'pv': TextEditingController(),
    'attestation': TextEditingController(),
  };
  final Map<String, String?> _grades = {'releve': null, 'pv': null, 'attestation': null};
  final Map<String, String?> _fonctions = {
    'releve': null,
    'pv': null,
    'attestation': null,
  };
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final controleur in _noms.values) {
      controleur.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final donnees = await widget.app.api.get('/notes/signataires') as Map<String, dynamic>;
      for (final (type, _) in _types) {
        final bloc = (donnees[type] as Map<String, dynamic>?) ?? const {};
        _noms[type]!.text = '${bloc['prenom_nom'] ?? ''}';
        final grade = '${bloc['grade'] ?? ''}';
        final fonction = '${bloc['fonction'] ?? ''}';
        _grades[type] = widget.grades.contains(grade) ? grade : null;
        _fonctions[type] = widget.fonctions.contains(fonction) ? fonction : null;
      }
    } catch (e) {
      _erreur = e.toString();
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
      await widget.app.api.put('/notes/signataires', {
        for (final (type, _) in _types)
          type: {
            'prenom_nom': _noms[type]!.text.trim(),
            'grade': _grades[type] ?? '',
            'fonction': _fonctions[type] ?? '',
          },
      });
      if (mounted) {
        Navigator.pop(context);
        afficherMessage(context, 'Signataires enregistrés');
      }
    } catch (e) {
      setState(() {
        _erreur = e.toString();
        _enregistrement = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Signataires des documents',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 560,
        child: _chargement
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (type, libelle) in _types) ...[
                      Text(
                        libelle,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noms[type],
                        decoration: const InputDecoration(
                          labelText: 'Prénom et nom',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _grades[type],
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Grade',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('— Aucun —'),
                                ),
                                for (final grade in widget.grades)
                                  DropdownMenuItem<String>(
                                    value: grade,
                                    child: Text(grade),
                                  ),
                              ],
                              onChanged: (valeur) => setState(() => _grades[type] = valeur),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _fonctions[type],
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Fonction',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text('— Aucune —'),
                                ),
                                for (final fonction in widget.fonctions)
                                  DropdownMenuItem<String>(
                                    value: fonction,
                                    child: Text(
                                      fonction,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                              ],
                              onChanged: (valeur) => setState(() => _fonctions[type] = valeur),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_erreur != null)
                      Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _enregistrement ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _chargement || _enregistrement ? null : _enregistrer,
          child: _enregistrement
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
