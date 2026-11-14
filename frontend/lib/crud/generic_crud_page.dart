import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'crud_config.dart';

class GenericCrudPage extends StatefulWidget {
  final ConfigCrud Function(AppState) config;
  final String? description;

  const GenericCrudPage({super.key, required this.config, this.description});

  @override
  State<GenericCrudPage> createState() => _GenericCrudPageState();
}

class _GenericCrudPageState extends State<GenericCrudPage> {
  final _recherche = TextEditingController();
  final _defilementTableau = ScrollController();
  String _filtre = '';
  final Map<String, dynamic> _filtres = {};
  bool _telechargementModele = false;
  bool _importation = false;

  /// Valeur réellement appliquée pour [filtre] : `null` si « Tous » ou si la
  /// valeur mémorisée n'existe plus dans les options courantes.
  dynamic _choixFiltre(FiltreCrud filtre, AppState app) {
    final choix = _filtres[filtre.libelle];
    if (choix == null) return null;
    final options = filtre.options(app);
    return options.any((option) => option.valeur == choix) ? choix : null;
  }

  bool _filtresActifs(ConfigCrud config, AppState app) =>
      config.filtres.any((filtre) => _choixFiltre(filtre, app) != null);

  @override
  void dispose() {
    _recherche.dispose();
    _defilementTableau.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final config = widget.config(app);
    final toutes = config.source(app);
    final filtresActifs = _filtresActifs(config, app);
    final donnees = toutes.where((element) {
      for (final filtre in config.filtres) {
        final choix = _choixFiltre(filtre, app);
        if (choix == null) continue;
        if (!filtre.correspond(element, app, choix)) return false;
      }
      if (_filtre.trim().isEmpty) return true;
      final cible = _filtre.toLowerCase();
      if (element.values.join(' ').toLowerCase().contains(cible)) return true;
      return config.colonnes.any(
        (colonne) => colonne.valeur(element, app).toLowerCase().contains(cible),
      );
    }).toList();

    if (config.triCle != null) {
      donnees.sort((a, b) {
        final va = a[config.triCle]?.toString() ?? '';
        final vb = b[config.triCle]?.toString() ?? '';
        return va.compareTo(vb);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: config.titre,
            sousTitre: widget.description ?? config.sousTitre,
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await app.rafraichir();
                    if (context.mounted)
                      afficherMessage(context, 'Données actualisées');
                  } catch (e) {
                    if (context.mounted)
                      afficherMessage(context, e.toString(), erreur: true);
                  }
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
              if (app.peutModifier && config.importation != null) ...[
                OutlinedButton.icon(
                  onPressed: _telechargementModele
                      ? null
                      : () => _telechargerModele(context, app, config.importation!),
                  icon: _telechargementModele
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Modèle Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _importation
                      ? null
                      : () => _importerFichier(context, app, config),
                  icon: _importation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(config.importation!.libelleImport),
                ),
              ],
              if (app.peutModifier && config.action != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await config.action!(context, app);
                    } catch (e) {
                      if (context.mounted) {
                        afficherMessage(context, e.toString(), erreur: true);
                      }
                    }
                  },
                  icon: Icon(config.iconeAction ?? Icons.settings_outlined, size: 18),
                  label: Text(config.libelleAction ?? 'Action'),
                ),
              if (app.peutModifier)
                ElevatedButton.icon(
                  onPressed: () => _ouvrirFormulaire(context, app, config),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(config.libelleAjout),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppCouleurs.bordure),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, contraintes) {
                          final champ = ChampRecherche(
                            controleur: _recherche,
                            hint:
                                'Rechercher ${config.articleIndefini} ${config.nomSingulier}…',
                            onChanged: (v) => setState(() => _filtre = v),
                          );
                          final compteur = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Pastille(
                                '${donnees.length} élément${donnees.length > 1 ? 's' : ''}',
                              ),
                              if (_filtre.isNotEmpty || filtresActifs) ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    _recherche.clear();
                                    setState(() {
                                      _filtre = '';
                                      _filtres.clear();
                                    });
                                  },
                                  child: const Text('Effacer les filtres'),
                                ),
                              ],
                            ],
                          );
                          if (contraintes.maxWidth < 620) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                champ,
                                const SizedBox(height: 10),
                                compteur,
                              ],
                            );
                          }
                          return Row(children: [champ, const Spacer(), compteur]);
                        },
                      ),
                      if (config.filtres.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            for (final filtre in config.filtres)
                              _menuFiltre(app, filtre),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (donnees.isEmpty)
                  EtatVide(
                    message: (_filtre.isEmpty && !filtresActifs)
                        ? '${config.feminin ? 'Aucune' : 'Aucun'} ${config.nomSingulier} enregistré${config.accord} pour le moment.'
                        : _filtre.isEmpty
                        ? 'Aucun résultat pour les filtres sélectionnés.'
                        : 'Aucun résultat pour « $_filtre ».',
                    icone: Icons.folder_open_outlined,
                    action: app.peutModifier && _filtre.isEmpty && !filtresActifs
                        ? TextButton.icon(
                            onPressed: () =>
                                _ouvrirFormulaire(context, app, config),
                            icon: const Icon(Icons.add),
                            label: Text(
                              'Ajouter ${config.articleIndefini} ${config.nomSingulier}',
                            ),
                          )
                        : null,
                  )
                else
                  Scrollbar(
                    controller: _defilementTableau,
                    thumbVisibility: true,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _defilementTableau,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 24,
                        horizontalMargin: 18,
                        showCheckboxColumn: false,
                        columns: [
                          if (app.peutModifier && config.actionsEnPremier)
                            const DataColumn(label: Text('ACTIONS')),
                          for (final colonne in config.colonnes)
                            DataColumn(
                              label: Text(colonne.libelle),
                              numeric: colonne.numerique,
                            ),
                          if (app.peutModifier && !config.actionsEnPremier)
                            const DataColumn(label: Text('ACTIONS')),
                        ],
                        rows: [
                          for (final ligne in donnees)
                            DataRow(
                              cells: [
                                if (app.peutModifier && config.actionsEnPremier)
                                  _celluleActions(context, app, config, ligne),
                                for (final colonne in config.colonnes)
                                  DataCell(_cellule(colonne, ligne, app)),
                                if (app.peutModifier && !config.actionsEnPremier)
                                  _celluleActions(context, app, config, ligne),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Les modifications sont enregistrées sur le serveur et visibles par tous les utilisateurs.',
            style: TextStyle(
              fontSize: 11,
              color: AppCouleurs.texteDoux.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuFiltre(AppState app, FiltreCrud filtre) {
    final choix = _choixFiltre(filtre, app);
    final options = filtre.options(app);
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<dynamic>(
        key: ValueKey<String>('filtre-${filtre.libelle}-$choix'),
        initialValue: choix,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: filtre.libelle,
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<dynamic>(
            value: null,
            child: Text('Tous', style: TextStyle(fontSize: 13)),
          ),
          for (final option in options)
            DropdownMenuItem<dynamic>(
              value: option.valeur,
              child: Text(
                option.libelle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        onChanged: (valeur) =>
            setState(() => _filtres[filtre.libelle] = valeur),
      ),
    );
  }

  Widget _cellule(
    ColonneTableau colonne,
    Map<String, dynamic> ligne,
    AppState app,
  ) {
    final valeur = colonne.valeur(ligne, app);
    final contenu = colonne.badge
        ? Pastille(valeur, couleur: _couleurBadge(valeur))
        : Text(valeur);
    if (colonne.largeur == null) return contenu;
    return SizedBox(
      width: colonne.largeur,
      child: DefaultTextStyle.merge(
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        child: contenu,
      ),
    );
  }

  DataCell _celluleActions(
    BuildContext context,
    AppState app,
    ConfigCrud config,
    Map<String, dynamic> ligne,
  ) {
    return DataCell(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppCouleurs.bleu,
            onPressed: () =>
                _ouvrirFormulaire(context, app, config, element: ligne),
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppCouleurs.rouge,
            onPressed: () => _supprimer(context, app, config, ligne),
          ),
        ],
      ),
    );
  }

  Color _couleurBadge(String valeur) {
    switch (valeur.toLowerCase()) {
      case 'actif':
      case 'oui':
      case 'effectuée':
      case 'amphi':
        return AppCouleurs.vert;
      case 'inactif':
      case 'non':
      case 'annulée':
      case 'labo':
        return AppCouleurs.rouge;
      case 'planifiée':
      case 'salle td':
        return AppCouleurs.bleu;
      case 'admin':
        return AppCouleurs.violet;
      case 'gestionnaire':
        return AppCouleurs.ambre;
      case 'enseignant':
        return AppCouleurs.teal;
      default:
        return AppCouleurs.texteDoux;
    }
  }

  Future<void> _telechargerModele(
    BuildContext context,
    AppState app,
    ImportationCrud importation,
  ) async {
    setState(() => _telechargementModele = true);
    try {
      final octets = await app.api.octets(importation.modeleEndpoint);
      telechargerOctets(
        octets,
        importation.nomModele,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (context.mounted) {
        afficherMessage(context, 'Modèle Excel téléchargé.');
      }
    } catch (e) {
      if (context.mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _telechargementModele = false);
    }
  }

  Future<void> _importerFichier(
    BuildContext context,
    AppState app,
    ConfigCrud config,
  ) async {
    final importation = config.importation;
    if (importation == null) return;
    try {
      final fichier = await FilePicker.pickFile(
        dialogTitle: importation.libelleImport,
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xlsm'],
      );
      if (fichier == null) return;
      final octets = await fichier.readAsBytes();
      setState(() => _importation = true);
      final rapport = await app.api.envoyerFichier(
        importation.importEndpoint,
        fichier.name,
        octets,
      );
      await app.rafraichir();
      if (!mounted) return;
      final erreurs = (rapport['erreurs'] as List?) ?? const [];
      afficherMessage(
        context,
        '${rapport['message'] ?? 'Import terminé.'}',
        erreur: erreurs.isNotEmpty,
      );
      if (erreurs.isNotEmpty) {
        await _afficherErreursImport(context, erreurs);
      }
    } catch (e) {
      if (context.mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _importation = false);
    }
  }

  Future<void> _afficherErreursImport(
    BuildContext context,
    List erreurs,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lignes non importées'),
        content: SizedBox(
          width: 640,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final erreur in erreurs.take(50))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        'Ligne ${erreur['ligne'] ?? '?'}'
                        '${erreur['feuille'] != null ? ' · ${erreur['feuille']}' : ''}'
                        ' : ${erreur['message'] ?? erreur}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  if (erreurs.length > 50)
                    Text('… et ${erreurs.length - 50} autre(s).'),
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
      ),
    );
  }

  Future<void> _supprimer(
    BuildContext context,
    AppState app,
    ConfigCrud config,
    Map<String, dynamic> ligne,
  ) async {
    final nom = config.colonnes.isNotEmpty
        ? config.colonnes.first.valeur(ligne, app)
        : '';
    final ok = await confirmer(
      context,
      titre:
          'Supprimer ${config.feminin ? 'cette' : 'ce'} ${config.nomSingulier} ?',
      message:
          '« $nom » sera supprimé${config.accord}. Les données liées (affectations, séances) peuvent également être supprimées.',
    );
    if (!ok || !context.mounted) return;
    try {
      await app.api.delete('${config.endpoint}/${ligne['id']}');
      await app.rafraichir();
      if (context.mounted) {
        afficherMessage(
          context,
          '${config.nomSingulier.capitalize()} supprimé${config.accord}',
        );
      }
    } catch (e) {
      if (context.mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  Future<void> _ouvrirFormulaire(
    BuildContext context,
    AppState app,
    ConfigCrud config, {
    Map<String, dynamic>? element,
  }) async {
    final resultat = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          FormulaireEntite(config: config, app: app, element: element),
    );
    if (resultat == true && context.mounted) {
      afficherMessage(
        context,
        element == null
            ? '${config.nomSingulier.capitalize()} créé${config.accord} avec succès'
            : '${config.nomSingulier.capitalize()} modifié${config.accord} avec succès',
      );
    }
  }
}

extension _Capitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

class FormulaireEntite extends StatefulWidget {
  final ConfigCrud config;
  final AppState app;
  final Map<String, dynamic>? element;

  const FormulaireEntite({
    super.key,
    required this.config,
    required this.app,
    this.element,
  });

  @override
  State<FormulaireEntite> createState() => _FormulaireEntiteState();
}

class _FormulaireEntiteState extends State<FormulaireEntite> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controleurs = {};
  final Map<String, dynamic> _valeurs = {};
  final _defilementChamps = ScrollController();
  bool _enregistrement = false;
  String? _erreur;

  bool get _edition => widget.element != null;

  @override
  void initState() {
    super.initState();
    for (final champ in widget.config.champs) {
      final brut = widget.element?[champ.cle];
      if (champ.type == TypeChamp.texte ||
          champ.type == TypeChamp.motDePasse ||
          champ.type == TypeChamp.nombre ||
          champ.type == TypeChamp.decimal) {
        _controleurs[champ.cle] = TextEditingController(
          text: champ.type == TypeChamp.motDePasse
              ? ''
              : brut == null
              ? '${champ.valeurInitiale ?? _valeurParDefaut(champ)}'
              : champ.type == TypeChamp.decimal
              ? '$brut'.replaceAll('.', ',')
              : '$brut',
        );
      } else if (champ.type == TypeChamp.date) {
        _controleurs[champ.cle] = TextEditingController(
          text: brut == null ? '' : _formatDateApi('$brut'),
        );
        if (brut != null) _valeurs[champ.cle] = '$brut'.substring(0, 10);
      } else if (champ.type == TypeChamp.booleen) {
        _valeurs[champ.cle] = brut is bool ? brut : (champ.cle == 'actif');
      } else if (champ.type == TypeChamp.liste) {
        _valeurs[champ.cle] = _edition
            ? brut
            : (champ.valeurInitiale ?? _premiereOption(champ));
      } else if (champ.type == TypeChamp.listeMultiple) {
        if (brut is List) {
          _valeurs[champ.cle] = List<dynamic>.from(brut);
        } else if (champ.valeurInitiale is List) {
          _valeurs[champ.cle] = List<dynamic>.from(champ.valeurInitiale as List);
        } else {
          _valeurs[champ.cle] = <dynamic>[];
        }
      }
    }
  }

  String _valeurParDefaut(ChampFormulaire champ) {
    switch (champ.cle) {
      case 'heures_max':
        return '192';
      case 'capacite':
        return '40';
      case 'effectif':
        return '30';
      case 'credits':
        return '6';
      case 'semaines':
        return '12';
      case 'ordre':
        return '1';
      case 'annee':
        return '2025-2026';
      case 'coefficient':
        return _valeurs['type_evaluation'] == 'Examen' ? '2' : '1';
      case 'note_max':
        return '20';
      case 'session':
        return '1';
      case 'heures_cm':
      case 'heures_td':
      case 'heures_tp':
        return '0';
      default:
        return '';
    }
  }

  dynamic _premiereOption(ChampFormulaire champ) {
    if (champ.options == null) return null;
    final options = champ.options!(widget.app);
    if (options.isEmpty) return null;
    if (champ.autoriserVide && options.first.valeur == null) return null;
    return options.first.valeur;
  }

  String _formatDateApi(String iso) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  void dispose() {
    for (final controleur in _controleurs.values) {
      controleur.dispose();
    }
    _defilementChamps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _edition
                ? 'Modifier ${widget.config.nomSingulier}'
                : widget.config.libelleAjout,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _edition
                ? 'Mettez à jour les informations ci-dessous.'
                : 'Renseignez les informations ci-dessous.',
            style: const TextStyle(
              fontSize: 12,
              color: AppCouleurs.texteDoux,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: taille.height * 0.65),
          child: Form(
            key: _formKey,
            child: Scrollbar(
              controller: _defilementChamps,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _defilementChamps,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final champ in widget.config.champs) ...[
                      _construireChamp(champ),
                      const SizedBox(height: 14),
                    ],
                    if (_erreur != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppCouleurs.rouge.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppCouleurs.rouge.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          _erreur!,
                          style: const TextStyle(
                            color: AppCouleurs.rouge,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enregistrement
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _enregistrement ? null : _enregistrer,
          child: _enregistrement
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_edition ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }

  Widget _construireChamp(ChampFormulaire champ) {
    switch (champ.type) {
      case TypeChamp.booleen:
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppCouleurs.bordure),
          ),
          child: SwitchListTile(
            title: Text(
              champ.libelle,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: champ.aide == null
                ? null
                : Text(champ.aide!, style: const TextStyle(fontSize: 11)),
            value: _valeurs[champ.cle] == true,
            onChanged: (v) => setState(() => _valeurs[champ.cle] = v),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            dense: true,
          ),
        );
      case TypeChamp.liste:
        final options = champ.options?.call(widget.app) ?? [];
        var valeur = _valeurs[champ.cle];
        if (!options.any((o) => o.valeur == valeur)) {
          valeur = options.isEmpty ? null : options.first.valeur;
        }
        return DropdownButtonFormField<dynamic>(
          initialValue: valeur,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
          ),
          items: [
            for (final option in options)
              DropdownMenuItem<dynamic>(
                value: option.valeur,
                child: Text(
                  option.libelle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
          ],
          validator: champ.obligatoire && !champ.autoriserVide
              ? (v) => v == null ? 'Champ obligatoire' : null
              : null,
          onChanged: (v) {
            setState(() {
              _valeurs[champ.cle] = v;
              // Le coefficient suit le type d'évaluation : 1 (devoir/CC/TP), 2 (examen).
              if (champ.cle == 'type_evaluation' &&
                  _controleurs.containsKey('coefficient')) {
                _controleurs['coefficient']!.text = v == 'Examen' ? '2' : '1';
              }
            });
          },
        );
      case TypeChamp.listeMultiple:
        final optionsMulti = champ.options?.call(widget.app) ?? [];
        final selection = (_valeurs[champ.cle] as List<dynamic>?) ?? <dynamic>[];
        return InputDecorator(
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in optionsMulti)
                FilterChip(
                  label: Text(
                    option.libelle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: selection.contains(option.valeur),
                  onSelected: (actif) {
                    setState(() {
                      final valeurs = List<dynamic>.from(selection);
                      if (actif) {
                        if (!valeurs.contains(option.valeur)) {
                          valeurs.add(option.valeur);
                        }
                      } else {
                        valeurs.remove(option.valeur);
                      }
                      _valeurs[champ.cle] = valeurs;
                    });
                  },
                ),
            ],
          ),
        );
      case TypeChamp.date:
        return TextFormField(
          controller: _controleurs[champ.cle],
          readOnly: true,
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          validator: (v) => champ.obligatoire && (v == null || v.isEmpty)
              ? 'Champ obligatoire'
              : null,
          onTap: () async {
            final actuel = _valeurs[champ.cle] == null
                ? DateTime.now()
                : DateTime.tryParse('${_valeurs[champ.cle]}') ?? DateTime.now();
            final choix = await showDatePicker(
              context: context,
              initialDate: actuel,
              firstDate: champ.dateMin ?? DateTime(2020),
              lastDate: champ.dateMax ?? DateTime(2035),
              locale: const Locale('fr', 'FR'),
            );
            if (choix != null) {
              final iso = DateFormat('yyyy-MM-dd').format(choix);
              setState(() {
                _valeurs[champ.cle] = iso;
                _controleurs[champ.cle]!.text = DateFormat('dd/MM/yyyy')
                    .format(choix);
              });
            }
          },
        );
      case TypeChamp.nombre:
        return TextFormField(
          controller: _controleurs[champ.cle],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
          ),
          validator: (v) {
            if (!champ.obligatoire && (v == null || v.trim().isEmpty))
              return null;
            if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
            if (int.tryParse(v.trim()) == null) return 'Nombre entier attendu';
            return null;
          },
        );
      case TypeChamp.decimal:
        return TextFormField(
          controller: _controleurs[champ.cle],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
          ),
          validator: (v) {
            if (!champ.obligatoire && (v == null || v.trim().isEmpty))
              return null;
            if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
            if (double.tryParse(v.trim().replaceAll(',', '.')) == null) {
              return 'Nombre décimal attendu';
            }
            return null;
          },
        );
      case TypeChamp.motDePasse:
        return TextFormField(
          controller: _controleurs[champ.cle],
          obscureText: true,
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
          ),
          validator: (v) {
            if (_edition) return null;
            if (v == null || v.isEmpty) return 'Champ obligatoire';
            if (v.length < 4) return '4 caractères minimum';
            return null;
          },
        );
      case TypeChamp.texte:
        return TextFormField(
          controller: _controleurs[champ.cle],
          decoration: InputDecoration(
            labelText: champ.libelle,
            helperText: champ.aide,
          ),
          validator: (v) => champ.obligatoire && (v == null || v.trim().isEmpty)
              ? 'Champ obligatoire'
              : null,
        );
    }
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final payload = <String, dynamic>{};
      for (final champ in widget.config.champs) {
        switch (champ.type) {
          case TypeChamp.texte:
            payload[champ.cle] = _controleurs[champ.cle]!.text.trim();
            break;
          case TypeChamp.nombre:
            final texte = _controleurs[champ.cle]!.text.trim();
            payload[champ.cle] = texte.isEmpty ? 0 : int.parse(texte);
            break;
          case TypeChamp.decimal:
            final texte = _controleurs[champ.cle]!.text.trim().replaceAll(
              ',',
              '.',
            );
            payload[champ.cle] = texte.isEmpty ? 0.0 : double.parse(texte);
            break;
          case TypeChamp.motDePasse:
            final texte = _controleurs[champ.cle]!.text;
            if (!(_edition && texte.isEmpty)) payload[champ.cle] = texte;
            break;
          case TypeChamp.booleen:
            payload[champ.cle] = _valeurs[champ.cle] == true;
            break;
          case TypeChamp.liste:
            payload[champ.cle] = _valeurs[champ.cle];
            break;
          case TypeChamp.listeMultiple:
            payload[champ.cle] = List<dynamic>.from(
              (_valeurs[champ.cle] as List<dynamic>?) ?? const [],
            );
            break;
          case TypeChamp.date:
            payload[champ.cle] = _valeurs[champ.cle];
            break;
        }
      }

      if (widget.config.utilisateurs &&
          !_edition &&
          (payload['mot_de_passe'] as String? ?? '').isEmpty) {
        throw ApiException(
          'Le mot de passe est obligatoire pour un nouvel utilisateur.',
        );
      }

      if (_edition) {
        await widget.app.api.put(
          '${widget.config.endpoint}/${widget.element!['id']}',
          payload,
        );
      } else {
        await widget.app.api.post(widget.config.endpoint, payload);
      }
      await widget.app.rafraichir();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.toString();
          _enregistrement = false;
        });
      }
    }
  }
}
