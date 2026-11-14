import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Module 4 — Saisie des notes : individuelle, en masse ou par import Excel.
class NotesSaisiePage extends StatefulWidget {
  const NotesSaisiePage({super.key});

  @override
  State<NotesSaisiePage> createState() => _NotesSaisiePageState();
}

class _NotesSaisiePageState extends State<NotesSaisiePage> {
  int? _semestreId;
  int? _niveauId;
  int? _evaluationId;
  bool _chargement = false;
  bool _chargementGrille = false;
  bool _enregistrement = false;
  bool _importation = false;
  bool _importationEcues = false;
  String? _erreur;
  Map<String, dynamic>? _rapportImportEcues;

  List<Map<String, dynamic>> _evaluations = [];
  Map<String, dynamic>? _evaluation;
  List<Map<String, dynamic>> _lignes = [];

  final Map<int, TextEditingController> _notes = {};
  final Map<int, TextEditingController> _commentaires = {};
  final Map<int, bool> _absents = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _evaluationId = null;
      _chargerEvaluations();
    }
  }

  @override
  void dispose() {
    for (final controleur in _notes.values) {
      controleur.dispose();
    }
    for (final controleur in _commentaires.values) {
      controleur.dispose();
    }
    super.dispose();
  }

  Future<void> _chargerEvaluations() async {
    final app = context.read<AppState>();
    if (_semestreId == null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final evaluations = await app.api.liste('/notes/evaluations', {
        'semestre_id': _semestreId,
      });
      final filtrees = _niveauId == null
          ? evaluations
          : evaluations
                .where(
                  (evaluation) => app
                      .niveauxECUE(evaluation['ecue_id'])
                      .contains(_niveauId),
                )
                .toList();
      if (!mounted) return;
      setState(() {
        _evaluations = filtrees;
        final existe = filtrees.any((e) => e['id'] == _evaluationId);
        if (!existe) {
          _evaluationId = filtrees.isNotEmpty
              ? filtrees.first['id'] as int
              : null;
        }
      });
      await _chargerGrille();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _chargerGrille() async {
    final app = context.read<AppState>();
    if (_evaluationId == null) {
      setState(() {
        _evaluation = null;
        _lignes = [];
      });
      return;
    }
    setState(() {
      _chargementGrille = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/notes/saisie', {
        'evaluation_id': _evaluationId,
      }) as Map<String, dynamic>;
      final lignes = ((donnees['lignes'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final controleur in _notes.values) {
        controleur.dispose();
      }
      for (final controleur in _commentaires.values) {
        controleur.dispose();
      }
      _notes.clear();
      _commentaires.clear();
      _absents.clear();
      for (final ligne in lignes) {
        final id = ligne['inscription_id'] as int;
        final valeur = ligne['valeur'];
        _notes[id] = TextEditingController(
          text: valeur == null ? '' : '$valeur'.replaceAll('.', ','),
        );
        _commentaires[id] = TextEditingController(
          text: '${ligne['commentaire'] ?? ''}',
        );
        _absents[id] = ligne['absent'] == true;
      }
      if (!mounted) return;
      setState(() {
        _evaluation = Map<String, dynamic>.from(donnees['evaluation'] as Map);
        _lignes = lignes;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargementGrille = false);
    }
  }

  Future<void> _enregistrer() async {
    final app = context.read<AppState>();
    if (_evaluationId == null) return;
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final notes = <Map<String, dynamic>>[];
      for (final ligne in _lignes) {
        final id = ligne['inscription_id'] as int;
        final texte = _notes[id]?.text.trim().replaceAll(',', '.') ?? '';
        notes.add({
          'inscription_id': id,
          'valeur': texte.isEmpty ? null : double.tryParse(texte),
          'absent': _absents[id] == true,
          'commentaire': _commentaires[id]?.text.trim() ?? '',
        });
      }
      final resultat = await app.api.post('/notes/saisie', {
        'evaluation_id': _evaluationId,
        'notes': notes,
      });
      if (!mounted) return;
      afficherMessage(context, '${resultat['message']}');
      await _chargerGrille();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _telechargerModele() async {
    if (_evaluationId == null) return;
    final app = context.read<AppState>();
    try {
      final octets = await app.api.octets('/notes/saisie/modele', {
        'evaluation_id': _evaluationId,
      });
      telechargerOctets(
        octets,
        'modele_notes_evaluation_$_evaluationId.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted) afficherMessage(context, 'Modèle Excel téléchargé.');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  Future<void> _telechargerClasseur() async {
    final app = context.read<AppState>();
    if (app.semestreId == null) {
      afficherMessage(
        context,
        'Sélectionnez d’abord un semestre.',
        erreur: true,
      );
      return;
    }
    int? niveauId;
    if (app.estEnseignant) {
      // Le serveur ne renvoie que les ECUE affectées à l'enseignant.
      niveauId = null;
    } else if (_evaluationId != null) {
      final evaluation = _evaluations.firstWhere(
        (e) => e['id'] == _evaluationId,
        orElse: () => const {},
      );
      final ecueId = evaluation['ecue_id'];
      final ecue = app.ecues.firstWhere(
        (e) => e['id'] == ecueId,
        orElse: () => const {},
      );
      final ue = app.ues.firstWhere(
        (u) => u['id'] == ecue['ue_id'],
        orElse: () => const {},
      );
      niveauId = ue['niveau_id'] as int?;
    }
    try {
      final octets = await app.api.octets('/notes/documents/modele-saisie', {
        'semestre_id': app.semestreId,
        'niveau_id': ?niveauId,
      });
      telechargerOctets(
        octets,
        'classeur_saisie_notes.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted) afficherMessage(context, 'Classeur de saisie téléchargé.');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  Future<void> _importer() async {
    if (_evaluationId == null) return;
    final app = context.read<AppState>();
    try {
      final fichier = await FilePicker.pickFile(
        dialogTitle: 'Sélectionner le classeur des notes',
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xlsm'],
      );
      if (fichier == null) return;
      final octets = await fichier.readAsBytes();
      setState(() {
        _importation = true;
        _erreur = null;
      });
      final rapport = await app.api.envoyerFichier(
        '/notes/saisie/importer?evaluation_id=$_evaluationId',
        fichier.name,
        octets,
      );
      if (!mounted) return;
      afficherMessage(context, '${rapport['message']}');
      await _chargerGrille();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _importation = false);
    }
  }

  Future<void> _importerEcues() async {
    final app = context.read<AppState>();
    if (app.semestreId == null) {
      afficherMessage(
        context,
        'Sélectionnez d’abord un semestre.',
        erreur: true,
      );
      return;
    }
    try {
      final fichier = await FilePicker.pickFile(
        dialogTitle: 'Sélectionner le classeur des ECUE',
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xlsm'],
      );
      if (fichier == null) return;
      final octets = await fichier.readAsBytes();
      setState(() {
        _importationEcues = true;
        _erreur = null;
        _rapportImportEcues = null;
      });
      final rapport = await app.api.envoyerFichier(
        '/notes/saisie/importer-ecues?semestre_id=${app.semestreId}&session=1',
        fichier.name,
        octets,
      );
      if (!mounted) return;
      final erreurs = (rapport['erreurs'] as List?) ?? const [];
      setState(() => _rapportImportEcues = rapport);
      afficherMessage(
        context,
        '${rapport['message']}',
        erreur: erreurs.isNotEmpty,
      );
      await _chargerEvaluations();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _importationEcues = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final evaluation = _evaluation;
    final bareme = (evaluation?['note_max'] as num?) ?? 20;
    final remplies = _lignes.where((ligne) {
      final id = ligne['inscription_id'] as int;
      return (_notes[id]?.text.trim().isNotEmpty ?? false) ||
          _absents[id] == true;
    }).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Saisie des notes',
            sousTitre: 'Saisie individuelle, en masse ou import Excel des notes par évaluation.',
            actions: [
              OutlinedButton.icon(
                onPressed: _evaluationId == null ? null : _telechargerModele,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Modèle Excel'),
              ),
              OutlinedButton.icon(
                onPressed: _telechargerClasseur,
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: const Text('Classeur par ECUE'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _importationEcues ||
                        app.semestreId == null ||
                        (!app.peutModifier && !app.estEnseignant)
                    ? null
                    : _importerEcues,
                icon: _importationEcues
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.library_add_outlined, size: 18),
                label: const Text('Importer des ECUE'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _evaluationId == null ||
                        _importation ||
                        (!app.peutModifier && !app.estEnseignant)
                    ? null
                    : _importer,
                icon: _importation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Importer'),
              ),
              ElevatedButton.icon(
                onPressed:
                    _lignes.isEmpty ||
                        _enregistrement ||
                        (!app.peutModifier && !app.estEnseignant)
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
                label: const Text('Enregistrer les notes'),
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
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey<int?>(_niveauId),
                    initialValue: _niveauId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Niveau',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text(
                          'Tous les niveaux',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      for (final niveau in app.niveaux)
                        DropdownMenuItem<int>(
                          value: niveau['id'] as int,
                          child: Text(
                            '${niveau['nom']} · ${niveau['filiere_code']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: _chargement
                        ? null
                        : (valeur) {
                            setState(() {
                              _niveauId = valeur;
                              _evaluationId = null;
                            });
                            _chargerEvaluations();
                          },
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: DropdownButtonFormField<int>(
                    initialValue:
                        _evaluations.any((e) => e['id'] == _evaluationId)
                        ? _evaluationId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Évaluation',
                      isDense: true,
                    ),
                    items: [
                      for (final evaluation in _evaluations)
                        DropdownMenuItem(
                          value: evaluation['id'] as int,
                          child: Text(
                            '${evaluation['ecue_code']} · ${evaluation['nom']} '
                            '(${evaluation['type_evaluation']}, S${evaluation['session']})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: _chargement
                        ? null
                        : (valeur) {
                            setState(() => _evaluationId = valeur);
                            _chargerGrille();
                          },
                  ),
                ),
                if (evaluation != null) ...[
                  Pastille(
                    'ECUE ${evaluation['ecue_code']}',
                    couleur: AppCouleurs.violet,
                  ),
                  Pastille('Barème /${noteTexte(bareme, decimales: 0)}'),
                  Pastille('Coef. ${evaluation['coefficient']}'),
                  Pastille(
                    '$remplies / ${_lignes.length} saisies',
                    couleur: AppCouleurs.teal,
                  ),
                ],
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
          if (_rapportImportEcues != null) ...[
            const SizedBox(height: 14),
            _carteRapportImportEcues(),
          ],
          const SizedBox(height: 16),
          if (_chargement || _chargementGrille)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_evaluations.isEmpty)
            const CarteTableau(
              child: EtatVide(
                message: 'Aucune évaluation pour ce semestre. Créez d’abord une évaluation dans le module Évaluations.',
                icone: Icons.assignment_outlined,
              ),
            )
          else if (_lignes.isEmpty)
            const CarteTableau(
              child: EtatVide(
                message:
                    'Aucun étudiant inscrit au niveau de cette évaluation.',
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
                  columns: [
                    const DataColumn(label: Text('MATRICULE')),
                    const DataColumn(label: Text('ÉTUDIANT')),
                    const DataColumn(label: Text('GROUPE')),
                    DataColumn(
                      label: Text('NOTE /${noteTexte(bareme, decimales: 0)}'),
                    ),
                    const DataColumn(label: Text('ABSENT')),
                    const DataColumn(label: Text('COMMENTAIRE')),
                  ],
                  rows: [
                    for (final ligne in _lignes)
                      _ligne(
                        ligne,
                        (evaluation?['note_max'] as num?)?.toDouble() ?? 20,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Laissez la note vide pour supprimer une saisie. Les notes sont ramenées sur 20 lors du calcul.',
            style: TextStyle(
              fontSize: 11,
              color: AppCouleurs.texteDoux.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteRapportImportEcues() {
    final rapport = _rapportImportEcues!;
    final erreurs = (rapport['erreurs'] as List?) ?? const [];
    final importees = (rapport['importees'] as num?)?.toInt() ?? 0;
    final supprimees = (rapport['supprimees'] as num?)?.toInt() ?? 0;
    final feuilles = (rapport['feuilles'] as num?)?.toInt() ?? 0;

    Widget indicateur(String libelle, int valeur, Color couleur) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: couleur.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$valeur',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: couleur,
              ),
            ),
            Text(
              libelle,
              style: const TextStyle(fontSize: 10.5, color: AppCouleurs.texteDoux),
            ),
          ],
        ),
      );
    }

    return CarteSection(
      titre: 'Rapport d’import des ECUE',
      sousTitre: '${rapport['message']}',
      action: erreurs.isEmpty
          ? const Pastille('Succès', couleur: AppCouleurs.vert)
          : Pastille('${erreurs.length} erreur(s)', couleur: AppCouleurs.rouge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              indicateur('Notes importées', importees, AppCouleurs.vert),
              indicateur('Notes supprimées', supprimees, AppCouleurs.bleu),
              indicateur('Feuilles traitées', feuilles, AppCouleurs.violet),
              indicateur(
                'Erreurs',
                erreurs.length,
                erreurs.isEmpty ? AppCouleurs.texteDoux : AppCouleurs.rouge,
              ),
            ],
          ),
          if (erreurs.isEmpty) ...[
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 17, color: AppCouleurs.vert),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toutes les lignes du classeur ont été importées.',
                    style: TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppCouleurs.ambre.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppCouleurs.ambre.withValues(alpha: 0.2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 17, color: AppCouleurs.ambre),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Les lignes ci-dessous n’ont pas été importées. Les autres lignes ont bien été enregistrées. '
                      'Corrigez le classeur puis relancez l’import : seules les lignes corrigées seront mises à jour.',
                      style: TextStyle(fontSize: 11.5, color: AppCouleurs.texteDoux, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Détail des erreurs',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final erreur in erreurs)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppCouleurs.rouge.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppCouleurs.rouge.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: AppCouleurs.rouge,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${erreur['feuille'] ?? 'Feuille inconnue'} · ligne ${erreur['ligne'] ?? '?'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppCouleurs.rouge,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${erreur['message'] ?? 'Erreur inconnue'}',
                                    style: const TextStyle(fontSize: 11.5, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _rapportImportEcues = null),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Fermer le rapport'),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _ligne(Map<String, dynamic> ligne, double noteMax) {
    final id = ligne['inscription_id'] as int;
    final absent = _absents[id] == true;
    return DataRow(
      cells: [
        DataCell(Text('${ligne['matricule'] ?? '—'}')),
        DataCell(
          SizedBox(
            width: 190,
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
            width: 100,
            child: TextField(
              controller: _notes[id],
              enabled: !absent,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0 – ${noteTexte(noteMax, decimales: 0)}',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        DataCell(
          Checkbox(
            value: absent,
            onChanged: (valeur) =>
                setState(() => _absents[id] = valeur == true),
          ),
        ),
        DataCell(
          SizedBox(
            width: 230,
            child: TextField(
              controller: _commentaires[id],
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Observation…',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
