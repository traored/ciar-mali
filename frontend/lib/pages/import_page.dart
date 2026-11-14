import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  PlatformFile? _fichier;
  Uint8List? _octets;
  bool _envoi = false;
  bool _telechargement = false;
  Map<String, dynamic>? _rapport;
  String? _erreur;

  Future<void> _telechargerModele() async {
    final app = context.read<AppState>();
    setState(() => _telechargement = true);
    try {
      final contenu = await app.api.octets('/importer/modele');
      telechargerOctets(
        contenu,
        'modele_import_edt.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
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
      if (mounted) afficherMessage(context, 'Sélection annulée ou impossible : $e', erreur: true);
    }
  }

  Future<void> _importer() async {
    final app = context.read<AppState>();
    if (_octets == null || _fichier == null) {
      setState(() => _erreur = 'Sélectionnez d’abord un classeur Excel.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
      _rapport = null;
    });
    try {
      final rapport = await app.api.envoyerFichier(
        '/importer/excel',
        _fichier!.name,
        _octets!,
      );
      await app.rafraichir();
      if (mounted) {
        setState(() => _rapport = rapport);
        afficherMessage(context, '${rapport['message']}');
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Import Excel',
            sousTitre: 'Chargez vos référentiels en masse depuis un classeur normalisé.',
            actions: [
              OutlinedButton.icon(
                onPressed: _telechargement ? null : _telechargerModele,
                icon: _telechargement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text('Télécharger le modèle'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, contraintes) {
              final depot = _carteDepot(app);
              final guide = _guide();
              if (contraintes.maxWidth < 980) {
                return Column(
                  children: [
                    depot,
                    const SizedBox(height: 18),
                    guide,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: depot),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: guide),
                ],
              );
            },
          ),
          if (_rapport != null) ...[
            const SizedBox(height: 18),
            _carteRapport(),
          ],
        ],
      ),
    );
  }

  Widget _carteDepot(AppState app) {
    final fichierPret = _fichier != null && _octets != null;
    return CarteSection(
      titre: 'Fichier à importer',
      sousTitre: 'Formats acceptés : .xlsx et .xlsm — 20 Mo maximum recommandé.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _envoi ? null : _choisirFichier,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: fichierPret ? AppCouleurs.teal : AppCouleurs.bordure,
                  width: fichierPret ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: (fichierPret ? AppCouleurs.teal : AppCouleurs.bleu).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      fichierPret ? Icons.check_circle_outline : Icons.upload_file_outlined,
                      color: fichierPret ? AppCouleurs.teal : AppCouleurs.bleu,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    fichierPret ? _fichier!.name : 'Cliquez pour sélectionner un classeur Excel',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fichierPret
                        ? '${_tailleLisible(_octets!.length)} — prêt à être importé'
                        : 'Les données existantes seront mises à jour, pas dupliquées.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
                  ),
                  if (fichierPret) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _envoi
                          ? null
                          : () => setState(() {
                                _fichier = null;
                                _octets = null;
                                _rapport = null;
                              }),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Retirer le fichier'),
                    ),
                  ],
                ],
              ),
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
                border: Border.all(color: AppCouleurs.rouge.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 18, color: AppCouleurs.rouge),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _erreur!,
                      style: const TextStyle(fontSize: 12, color: AppCouleurs.rouge, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (app.peutModifier)
                ElevatedButton.icon(
                  onPressed: (!fichierPret || _envoi) ? null : _importer,
                  icon: _envoi
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(_envoi ? 'Importation…' : 'Lancer l’importation'),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppCouleurs.ambre.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 15, color: AppCouleurs.ambre),
                      SizedBox(width: 7),
                      Text(
                        'Import réservé aux administrateurs et gestionnaires',
                        style: TextStyle(fontSize: 11.5, color: AppCouleurs.ambre, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              if (fichierPret)
                Text(
                  '${app.groupes.length} groupes · ${app.enseignants.length} enseignants actuellement',
                  style: const TextStyle(fontSize: 11, color: AppCouleurs.texteDoux),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _guide() {
    const etapes = [
      (
        '1',
        'Télécharger le modèle',
        'Le classeur contient une feuille par référentiel avec les en-têtes attendus.',
      ),
      (
        '2',
        'Remplir les feuilles',
        'Respectez les codes : département, filière, UE et ECUE servent de clés de rapprochement.',
      ),
      (
        '3',
        'Importer le fichier',
        'Les enregistrements existants sont mis à jour. Les erreurs sont listées ligne par ligne.',
      ),
      (
        '4',
        'Générer l’emploi du temps',
        'Après import, lancez la génération depuis le tableau de bord pour recalculer les séances.',
      ),
    ];
    return CarteSection(
      titre: 'Mode d’emploi',
      sousTitre: 'Quatre étapes pour intégrer vos données.',
      child: Column(
        children: [
          for (final etape in etapes)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppCouleurs.bleu.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        etape.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppCouleurs.bleu,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          etape.$2,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          etape.$3,
                          style: const TextStyle(fontSize: 11.5, color: AppCouleurs.texteDoux, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 17, color: AppCouleurs.ambre),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Astuce : importez d’abord la structure (départements → filières → niveaux → groupes), '
                    'puis les enseignants et enfin les affectations.',
                    style: TextStyle(fontSize: 11.5, color: AppCouleurs.texteDoux, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteRapport() {
    final rapport = _rapport!;
    final importes = Map<String, dynamic>.from((rapport['importes'] as Map?) ?? {});
    final erreurs = (rapport['erreurs'] as List?) ?? [];
    final total = (rapport['total'] as num?)?.toInt() ?? 0;

    return CarteSection(
      titre: 'Rapport d’importation',
      sousTitre: '${rapport['message']}',
      action: Pastille(
        erreurs.isEmpty ? 'Succès' : '${erreurs.length} erreur(s)',
        couleur: erreurs.isEmpty ? AppCouleurs.vert : AppCouleurs.ambre,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entree in importes.entries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: (entree.value as num) > 0
                        ? AppCouleurs.vert.withValues(alpha: 0.07)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (entree.value as num) > 0
                          ? AppCouleurs.vert.withValues(alpha: 0.25)
                          : AppCouleurs.bordure,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entree.value}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: (entree.value as num) > 0 ? AppCouleurs.vert : AppCouleurs.texteDoux,
                        ),
                      ),
                      Text(
                        entree.key,
                        style: const TextStyle(fontSize: 10.5, color: AppCouleurs.texteDoux),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (erreurs.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Lignes en erreur',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
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
                          border: Border.all(color: AppCouleurs.rouge.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 16, color: AppCouleurs.rouge),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${erreur['feuille']} · ligne ${erreur['ligne']} — ${erreur['message']}',
                                style: const TextStyle(fontSize: 11.5, height: 1.4),
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
          if (total == 0 && erreurs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Aucune ligne exploitable n’a été trouvée dans le classeur.',
                style: TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
              ),
            ),
        ],
      ),
    );
  }

  String _tailleLisible(int octets) {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) return '${(octets / 1024).toStringAsFixed(1)} Ko';
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
