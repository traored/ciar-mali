import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/semestres_parite.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'notes/presences_dialog.dart';
import 'sessions_page.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  String _mode = 'niveau';
  int? _cibleId;
  List<Map<String, dynamic>> _seances = [];
  bool _chargement = true;
  String? _erreur;
  bool _initialise = false;
  int? _semaineChargee;
  int? _semestreCharge;

  /// L'utilisateur a choisi lui-même la cible : on ne la remplace plus par
  /// le niveau ou le groupe par défaut de l'étudiant.
  bool _cibleManuelle = false;

  /// Parité des semestres affichés pour un enseignant : `impairs`, `pairs`
  /// ou `tous` (le semestre sélectionné dans l'en-tête uniquement).
  String _parite = 'impairs';

  /// Une vérification ou une réparation des conflits est en cours.
  bool _conflitsEnCours = false;

  /// Défilement vertical de la page et horizontal de la grille : les deux
  /// barres restent visibles pour les utilisateurs web.
  final ScrollController _defilementPage = ScrollController();
  final ScrollController _defilementGrille = ScrollController();
  final ScrollController _defilementGlobalV = ScrollController();
  final ScrollController _defilementGlobalHTete = ScrollController();
  final ScrollController _defilementGlobalHCorps = ScrollController();
  bool _syncH = false;

  static const _jours = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
  ];
  static const _libellesModes = {
    'global': 'Général (tous)',
    'groupe': 'Par groupe',
    'enseignant': 'Par enseignant',
    'salle': 'Par salle',
    'niveau': 'Par niveau',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialise) {
      _initialise = true;
      _defilementGlobalHTete.addListener(
        () => _synchroniserHorizontal(_defilementGlobalHTete, _defilementGlobalHCorps),
      );
      _defilementGlobalHCorps.addListener(
        () => _synchroniserHorizontal(_defilementGlobalHCorps, _defilementGlobalHTete),
      );
      final app = context.read<AppState>();
      _mode = app.estEnseignant ? 'enseignant' : 'niveau';
      _parite = _pariteCourante();
      _cibleId = _premiereCible(app);
      _charger(autoNiveau: !app.estEnseignant && !app.estLecteur);
    }
  }

  void _synchroniserHorizontal(ScrollController source, ScrollController cible) {
    if (_syncH || !source.hasClients || !cible.hasClients) return;
    final offset = source.offset.clamp(
      0.0,
      cible.position.maxScrollExtent,
    );
    if ((cible.offset - offset).abs() < 0.5) return;
    _syncH = true;
    cible.jumpTo(offset);
    _syncH = false;
  }

  @override
  void dispose() {
    _defilementPage.dispose();
    _defilementGrille.dispose();
    _defilementGlobalV.dispose();
    _defilementGlobalHTete.dispose();
    _defilementGlobalHCorps.dispose();
    super.dispose();
  }

  /// Année universitaire courante (ex. « 2025-2026 »).
  String get _anneeCourante {
    final maintenant = DateTime.now();
    final debut = maintenant.month >= 9 ? maintenant.year : maintenant.year - 1;
    return '$debut-${debut + 1}';
  }

  /// Parité en cours : impairs de septembre à janvier, pairs ensuite.
  String _pariteCourante() {
    final mois = DateTime.now().month;
    return (mois >= 9 || mois <= 1) ? 'impairs' : 'pairs';
  }

  /// Affiche-t-on plusieurs semestres de même parité (impairs/pairs) ?
  ///
  /// - Enseignant : sur son emploi du temps (mode « enseignant »).
  /// - Administrateur/gestionnaire : sur la vue globale (tous les niveaux).
  bool _groupeParParite(AppState app) =>
      _parite != 'tous' &&
      ((app.estEnseignant && _mode == 'enseignant') ||
          (!app.estEnseignant && _mode == 'global'));

  String get _libelleParite =>
      _parite == 'pairs' ? 'Semestres pairs' : 'Semestres impairs';

  /// Semestres impairs ou pairs de l'année universitaire courante.
  ///
  /// Pour un enseignant, seuls les semestres où il intervient sont retenus.
  /// Pour la vue globale (administration/gestion), tous les semestres de la
  /// parité sont retenus afin de planifier l'ensemble des niveaux.
  List<Map<String, dynamic>> _semestresParite(AppState app) {
    final complets = app.semestresTous.isNotEmpty
        ? app.semestresTous
        : app.semestres;
    final periode = _parite == 'pairs' ? 2 : 1;
    if (!app.estEnseignant && _mode == 'global') {
      final liste = <Map<String, dynamic>>[];
      for (final semestre in complets) {
        if ('${semestre['annee'] ?? ''}' != _anneeCourante) continue;
        final numero = numeroSemestre('${semestre['nom'] ?? ''}');
        if (numero == null || (numero.isOdd ? 1 : 2) != periode) continue;
        liste.add({...semestre, '_numero': numero});
      }
      liste.sort(
        (a, b) => (a['_numero'] as int).compareTo(b['_numero'] as int),
      );
      return liste;
    }
    return semestresDeParite(
      complets,
      periode: periode,
      annee: _anneeCourante,
      affectations: app.affectations,
      avecSeances: app.semestresAvecSeances,
    );
  }

  /// Année du semestre affiché : c'est celle de l'inscription de l'étudiant.
  String _anneeSemestre(AppState app) =>
      '${app.semestreSelectionne?['annee'] ?? app.anneeCourante}';

  int? _premiereCible(AppState app) {
    switch (_mode) {
      case 'global':
        return null;
      case 'enseignant':
        return app.estEnseignant
            ? app.utilisateur?.enseignantId
            : (app.enseignants.isEmpty
                  ? null
                  : app.enseignants.first['id'] as int);
      case 'salle':
        return app.salles.isEmpty ? null : app.salles.first['id'] as int;
      case 'niveau':
        // Un étudiant ouvre l'emploi du temps de sa classe : le niveau de son
        // inscription pour l'année du semestre affiché.
        return app.niveauInscription(_anneeSemestre(app)) ??
            (app.niveaux.isEmpty ? null : app.niveaux.first['id'] as int);
      default:
        return app.groupeInscription(_anneeSemestre(app)) ??
            (app.groupes.isEmpty ? null : app.groupes.first['id'] as int);
    }
  }

  List<Map<String, dynamic>> _optionsCibles(AppState app) {
    switch (_mode) {
      case 'global':
        return const [];
      case 'enseignant':
        return app.enseignants;
      case 'salle':
        return app.salles;
      case 'niveau':
        return app.niveaux;
      default:
        return app.groupes;
    }
  }

  String _libelleCible(AppState app, Map<String, dynamic> element) {
    switch (_mode) {
      case 'enseignant':
        return app.libelleEnseignant(element);
      case 'salle':
        return '${element['nom']}';
      case 'niveau':
        return app.libelleNiveau(element['id']);
      default:
        return app.libelleGroupe(element['id']);
    }
  }

  Future<void> _charger({bool autoNiveau = false}) async {
    final app = context.read<AppState>();
    if (_groupeParParite(app)) {
      await _chargerParite(app);
      return;
    }
    if (app.semestreId == null) return;
    _semaineChargee = app.semaine;
    _semestreCharge = app.semestreId;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final parametres = <String, dynamic>{
        'semestre_id': app.semestreId,
        'semaine': app.semaine,
      };
      if (_mode == 'groupe') parametres['groupe_id'] = _cibleId;
      if (_mode == 'enseignant') parametres['enseignant_id'] = _cibleId;
      if (_mode == 'salle') parametres['salle_id'] = _cibleId;
      var donnees = await app.api.liste('/seances', parametres);
      int? cible = _cibleId;
      if (_mode == 'niveau') {
        if (autoNiveau) {
          // À l'ouverture du tableau de bord, on affiche directement un
          // niveau qui a des séances plutôt qu'un niveau vide.
          cible = app.niveauAvecSeances(donnees) ?? cible;
        }
        final ids = app.groupes
            .where((g) => g['niveau_id'] == cible)
            .map((g) => g['id'])
            .toSet();
        donnees = donnees.where((s) {
          final groupes = (s['groupe_ids'] as List?) ?? [];
          return groupes.any((id) => ids.contains(id));
        }).toList();
      }
      if (mounted) {
        setState(() {
          _cibleId = cible;
          _seances = donnees;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  /// Charge en une seule grille les séances de tous les semestres de la
  /// parité choisie pour l'année universitaire courante (par exemple 1, 3 et
  /// 5). Chaque séance conserve le semestre dont elle provient.
  Future<void> _chargerParite(AppState app) async {
    final semestres = _semestresParite(app);
    final enseignantId = app.utilisateur?.enseignantId;
    // Semaine civile affichée, définie par le semestre de référence : chaque
    // semestre de la parité est interrogé sur la semaine qui la recouvre, car
    // ils ne démarrent pas tous le même jour (le semestre 7 commence par
    // exemple cinq semaines après le semestre 1).
    final reference = _semestreReference(app);
    final lundi = reference == null
        ? null
        : lundiDeSemaine(reference, app.semaine);
    _semaineChargee = app.semaine;
    _semestreCharge = app.semestreId;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final resultats = await Future.wait([
        for (final semestre in semestres)
          app.api.liste('/seances', {
            'semestre_id': semestre['id'],
            'semaine': lundi == null
                ? app.semaine
                : semaineDansSemestre(semestre, lundi, defaut: app.semaine),
            if (enseignantId != null) 'enseignant_id': enseignantId,
          }),
      ]);
      final seances = <Map<String, dynamic>>[];
      for (var i = 0; i < resultats.length; i++) {
        final semestre = semestres[i];
        for (final seance in resultats[i]) {
          seances.add({
            ...seance,
            '_semestre_id': semestre['id'],
            '_semestre_nom': semestre['nom'],
            '_semestre_annee': semestre['annee'],
          });
        }
      }
      seances.sort((a, b) {
        final semaine = (a['semaine'] as int? ?? 0).compareTo(
          b['semaine'] as int? ?? 0,
        );
        if (semaine != 0) return semaine;
        final creneau = (a['creneau_id'] as int? ?? 0).compareTo(
          b['creneau_id'] as int? ?? 0,
        );
        if (creneau != 0) return creneau;
        return '${a['ecue_code']}'.compareTo('${b['ecue_code']}');
      });
      if (mounted) setState(() => _seances = seances);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  /// Semestre de référence de la grille groupée : celui de l'année courante
  /// qui contient la date du jour, à défaut le premier de la parité.
  Map<String, dynamic>? _semestreReference(AppState app) {
    final semestres = _semestresParite(app);
    if (semestres.isEmpty) return null;
    final maintenant = DateTime.now();
    for (final semestre in semestres) {
      final debut = DateTime.tryParse('${semestre["date_debut"] ?? ""}');
      final fin = DateTime.tryParse('${semestre["date_fin"] ?? ""}');
      if (debut != null &&
          fin != null &&
          !maintenant.isBefore(debut) &&
          !maintenant.isAfter(fin)) {
        return semestre;
      }
    }
    return semestres.first;
  }

  void _changerParite(String? parite) {
    if (parite == null) return;
    setState(() => _parite = parite);
    _charger();
  }

  void _changerMode(String? mode) {
    if (mode == null) return;
    final app = context.read<AppState>();
    setState(() {
      _mode = mode;
      // Nouveau mode : on repart de la cible par défaut de l'utilisateur
      // (pour un étudiant, le niveau ou le groupe de son inscription).
      _cibleManuelle = false;
      _cibleId = _premiereCible(app);
    });
    _charger(autoNiveau: mode == 'niveau' && !app.estLecteur);
  }

  Future<void> _exporter() async {
    final app = context.read<AppState>();
    if (_groupeParParite(app)) return;
    if (app.semestreId == null) return;
    if (_mode != 'global' && _cibleId == null) return;
    try {
      final octets = await app.api.octets('/export/emploi-du-temps', {
        'type': _mode,
        if (_mode != 'global') 'cible_id': _cibleId,
        'semestre_id': app.semestreId,
        'semaine': app.semaine,
      });
      final suffixe = _mode == 'global' ? 'global' : '${_mode}_$_cibleId';
      telechargerOctets(
        octets,
        'emploi_du_temps_${suffixe}_semaine_${app.semaine}.pdf',
        'application/pdf',
      );
      if (mounted) afficherMessage(context, 'Export PDF téléchargé');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  /// Ouvre le rapport des conflits (salle, enseignant, groupe) et propose de
  /// réparer automatiquement les séances planifiées concernées.
  Future<void> _ouvrirConflits(AppState app) async {
    setState(() => _conflitsEnCours = true);
    try {
      final donnees = await app.api.get('/seances/conflits');
      final conflits = ((donnees['conflits'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      final reparer = await showDialog<bool>(
        context: context,
        builder: (context) => _DialogConflits(conflits: conflits),
      );
      if (reparer == true) {
        await _reparerConflits(app);
      }
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _conflitsEnCours = false);
    }
  }

  Future<void> _reparerConflits(AppState app) async {
    setState(() => _conflitsEnCours = true);
    try {
      final resultat = await app.api.post('/seances/conflits/reparer', {});
      await _charger();
      if (!mounted) return;
      final deplacees = resultat['deplacees'] ?? 0;
      final restants = resultat['restants'] ?? 0;
      afficherMessage(
        context,
        restants == 0
            ? '$deplacees séance(s) déplacée(s). Plus aucun conflit.'
            : '$deplacees séance(s) déplacée(s). $restants conflit(s) '
                  'restant(s), limités aux séances effectuées ou verrouillées.',
      );
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _conflitsEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final options = _optionsCibles(app);
    final semestre = app.semestreSelectionne;
    final groupeParParite = _groupeParParite(app);
    // En mode groupé, les dates de semaine viennent d'un semestre de l'année
    // affichée, même si l'en-tête pointe encore sur une autre année.
    final reference = groupeParParite ? _semestreReference(app) : null;
    final semestreIdReference = reference?['id'];
    // La grille groupée couvre plusieurs semestres : on propose le plus grand
    // nombre de semaines de la parité, pour ne pas masquer des séances.
    final nombreSemaines = groupeParParite
        ? _semestresParite(app)
              .map((s) => (s['semaines'] as int?) ?? 0)
              .fold<int>(app.nombreSemaines, (max, v) => v > max ? v : max)
        : app.nombreSemaines;
    // Un étudiant ne consulte que son groupe ou son niveau. Le superviseur
    // consulte toutes les classes, en lecture seule.
    final modes = app.estLecteur || app.estSuperviseur
        ? {
            for (final cle in const ['groupe', 'niveau'])
              cle: _libellesModes[cle]!,
          }
        : _libellesModes;

    if (_cibleId == null && options.isNotEmpty) {
      // Cible par défaut de l'utilisateur (niveau d'inscription pour un
      // étudiant), sans écraser un choix explicite.
      _cibleId = _premiereCible(app) ?? options.first['id'] as int;
      if (_semestreCharge != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _charger();
        });
      }
    }

    // Le semestre ou la semaine par défaut change (sélection dans l'en-tête) :
    // la grille doit suivre la nouvelle semaine. Un changement de semestre
    // relance aussi la recherche d'un niveau pourvu de séances.
    // `premierChargement` couvre le cas où la page aurait été construite avant
    // la fin du chargement des référentiels (aucun semestre connu) : elle se
    // recharge dès que le semestre courant est disponible.
    final premierChargement = _semestreCharge == null && app.semestreId != null;
    final changementSemestre =
        _semestreCharge != null && _semestreCharge != app.semestreId;
    final changementSemaine =
        _semaineChargee != null && _semaineChargee != app.semaine;
    if (premierChargement || changementSemestre || changementSemaine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_semestreCharge == null || _semestreCharge != app.semestreId) {
          // Un étudiant suit son inscription : le niveau (ou le groupe) par
          // défaut dépend de l'année du semestre affiché. On le recalcule
          // sauf s'il a choisi lui-même la cible.
          if (app.estLecteur && !_cibleManuelle) {
            setState(() => _cibleId = _premiereCible(app));
          }
          _charger(
            autoNiveau: _mode == 'niveau' && !app.estLecteur && !_cibleManuelle,
          );
        } else if (_semaineChargee != app.semaine) {
          _charger();
        }
      });
    }

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
              titre: app.estEnseignant
                  ? 'Mon emploi du temps'
                  : 'Emploi du temps',
              sousTitre: groupeParParite
                  ? '$_libelleParite · $_anneeCourante — ${app.libelleSemaine(app.semaine, semestreId: semestreIdReference)}'
                  : semestre == null
                  ? 'Semaine de cours'
                  : '${semestre['nom']} · ${semestre['annee']} — ${app.libelleSemaine(app.semaine)} '
                        '(sur ${app.nombreSemaines} semaines)',
              actions: [
                OutlinedButton.icon(
                  onPressed: _charger,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualiser'),
                ),
                if (app.peutModifier)
                  OutlinedButton.icon(
                    onPressed: _conflitsEnCours
                        ? null
                        : () => _ouvrirConflits(app),
                    icon: _conflitsEnCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Conflits'),
                  ),
                ElevatedButton.icon(
                  onPressed:
                      !_groupeParParite(app) &&
                          (_mode == 'global' || _cibleId != null)
                      ? _exporter
                      : null,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Exporter en PDF'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppCouleurs.bordure),
              ),
              child: LayoutBuilder(
                builder: (context, contraintes) {
                  final champs = <Widget>[
                    if (!app.estEnseignant)
                      _filtre(
                        label: 'Affichage',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('mode-$_mode'),
                          initialValue: _mode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            for (final entree in modes.entries)
                              DropdownMenuItem(
                                value: entree.key,
                                child: Text(
                                  entree.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: _changerMode,
                        ),
                      ),
                    if (app.estEnseignant || (!app.estEnseignant && _mode == 'global'))
                      _filtre(
                        label: 'Période',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('parite-$_mode-$_parite'),
                          initialValue: _parite,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'impairs',
                              child: Text(
                                'Semestres impairs $_anneeCourante',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'pairs',
                              child: Text(
                                'Semestres pairs $_anneeCourante',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const DropdownMenuItem(
                              value: 'tous',
                              child: Text(
                                'Semestre sélectionné',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: _changerParite,
                        ),
                      ),
                    if (_mode != 'global' && !_groupeParParite(app))
                      _filtre(
                        label: _mode == 'groupe'
                            ? 'Groupe'
                            : _mode == 'enseignant'
                            ? 'Enseignant'
                            : _mode == 'salle'
                            ? 'Salle'
                            : 'Niveau',
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('cible-$_mode-$_cibleId'),
                          initialValue: options.any((e) => e['id'] == _cibleId)
                              ? _cibleId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: [
                            for (final element in options)
                              DropdownMenuItem(
                                value: element['id'] as int,
                                child: Text(
                                  _libelleCible(app, element),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                          onChanged: app.estEnseignant
                              ? null
                              : (v) async {
                                  setState(() {
                                    _cibleId = v;
                                    // Choix explicite : il prime sur le niveau
                                    // d'inscription lors des changements.
                                    _cibleManuelle = true;
                                  });
                                  if (_mode == 'niveau' && v != null) {
                                    // Chaque niveau a son propre semestre en
                                    // cours : Licence 1 → semestre 1, Licence 3
                                    // → semestre 5, etc. Le filtre semestre de
                                    // l'en-tête suit automatiquement.
                                    final semestre = app.semestreCourantNiveau(
                                      v,
                                    );
                                    if (semestre != null &&
                                        semestre != app.semestreId &&
                                        app.semestres.any(
                                          (s) => s['id'] == semestre,
                                        )) {
                                      await app.selectionnerSemestre(semestre);
                                    }
                                  }
                                  _charger();
                                },
                        ),
                      ),
                    _filtre(
                      label: 'Semaine',
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('semaine-${app.semaine}'),
                        initialValue: app.semaine,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: [
                          for (var i = 1; i <= nombreSemaines; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                app.libelleSemaine(
                                  i,
                                  court: true,
                                  semestreId: semestreIdReference,
                                ),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          app.selectionnerSemaine(v);
                          _charger();
                        },
                      ),
                    ),
                  ];
                  if (contraintes.maxWidth < 700) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < champs.length; i++) ...[
                          SizedBox(width: double.infinity, child: champs[i]),
                          if (i < champs.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < champs.length; i++) ...[
                        Expanded(child: champs[i]),
                        if (i < champs.length - 1) const SizedBox(width: 14),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_erreur != null)
              CarteSection(
                child: EtatVide(
                  message: _erreur!,
                  icone: Icons.cloud_off_outlined,
                  action: ElevatedButton(
                    onPressed: _charger,
                    child: const Text('Réessayer'),
                  ),
                ),
              )
            else
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
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_view_week_outlined,
                            size: 18,
                            color: AppCouleurs.bleu,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              groupeParParite
                                  ? '$_libelleParite · ${app.libelleSemaine(app.semaine, semestreId: semestreIdReference)}'
                                  : app.libelleSemaine(app.semaine),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_chargement)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          const Spacer(),
                          Wrap(
                            spacing: 14,
                            children: const [
                              _Legende('CM', AppCouleurs.bleu),
                              _Legende('TD', AppCouleurs.vert),
                              _Legende('TP', AppCouleurs.ambre),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (_chargement && _seances.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 70),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      (_mode == 'global' ? _grilleGlobale(app) : _grille(app)),
                    if (!_chargement && _seances.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 18,
                                color: AppCouleurs.texteDoux,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _groupeParParite(app)
                                      ? 'Aucune séance pour cette semaine dans les ${_parite == 'pairs' ? 'semestres pairs' : 'semestres impairs'} de $_anneeCourante.'
                                      : app.peutModifier
                                      ? 'Aucune séance pour cette semaine. Utilisez « Générer l’emploi du temps » depuis le tableau de bord ou créez une séance manuellement.'
                                      : 'Aucune séance programmée pour cette semaine.',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppCouleurs.texteDoux,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filtre({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppCouleurs.texteDoux,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _grille(AppState app) {
    final horaires = <String>[];
    for (final creneau in app.creneaux) {
      final horaire = '${creneau['debut']}|${creneau['fin']}';
      if (!horaires.contains(horaire)) horaires.add(horaire);
    }
    if (horaires.isEmpty) {
      return const EtatVide(
        message:
            'Aucun créneau défini. Ajoutez des créneaux dans les paramètres.',
      );
    }

    return Scrollbar(
      controller: _defilementGrille,
      thumbVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      child: SingleChildScrollView(
        controller: _defilementGrille,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 74),
                  for (final jour in _jours)
                    Container(
                      width: 182,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        jour,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppCouleurs.texteDoux,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final horaire in horaires) _ligneHoraire(app, horaire),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ligneHoraire(AppState app, String horaire) {
    final morceaux = horaire.split('|');
    final debut = morceaux.first;
    final fin = morceaux.last;
    final parJour = <int, List<Map<String, dynamic>>>{};
    for (var jour = 0; jour < 6; jour++) {
      parJour[jour] = _seances.where((s) {
        return s['creneau_debut'] == debut &&
            s['creneau_fin'] == fin &&
            s['creneau_jour'] == jour;
      }).toList();
    }
    final maxSeances = parJour.values.fold<int>(
      1,
      (max, liste) => liste.length > max ? liste.length : max,
    );
    // En mode groupé, la carte affiche en plus le niveau et le semestre.
    final hauteur = maxSeances * (_groupeParParite(app) ? 100 : 78) + 16;

    return SizedBox(
      height: hauteur.toDouble(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 74,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  debut,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  fin,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppCouleurs.texteDoux,
                  ),
                ),
              ],
            ),
          ),
          for (var jour = 0; jour < 6; jour++)
            _celluleJour(app, jour, debut, fin, parJour[jour]!),
        ],
      ),
    );
  }

  Widget _celluleJour(
    AppState app,
    int jour,
    String debut,
    String fin,
    List<Map<String, dynamic>> seances,
  ) {
    final creneau = _creneauPour(app, jour, debut, fin);
    return Container(
      width: 182,
      margin: const EdgeInsets.only(right: 4, bottom: 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEDF2F7)),
      ),
      child: seances.isEmpty && creneau != null && app.peutModifier
          ? _invitationCreation(app, creneau)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final seance in seances)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: _carteSeance(app, seance),
                    ),
                  ),
              ],
            ),
    );
  }

  Map<String, dynamic>? _creneauPour(
    AppState app,
    int jour,
    String debut,
    String fin,
  ) {
    for (final creneau in app.creneaux) {
      if (creneau['jour'] == jour &&
          creneau['debut'] == debut &&
          creneau['fin'] == fin) {
        return creneau;
      }
    }
    return null;
  }

  Widget _invitationCreation(AppState app, Map<String, dynamic> creneau) {
    return InkWell(
      onTap: () => _creerDepuisCreneau(app, creneau),
      borderRadius: BorderRadius.circular(6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 20,
              color: AppCouleurs.bleu.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 3),
            Text(
              'Ajouter une séance',
              style: TextStyle(
                fontSize: 9,
                color: AppCouleurs.bleu.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _creerDepuisCreneau(
    AppState app,
    Map<String, dynamic> creneau,
  ) async {
    int? enseignant;
    int? salle;
    final groupes = <int>{};
    if (_mode == 'groupe' && _cibleId != null) groupes.add(_cibleId!);
    if (_mode == 'niveau' && _cibleId != null) {
      groupes.addAll(app.groupesDeNiveau(_cibleId).map((g) => g['id'] as int));
    }
    if (_mode == 'enseignant') enseignant = _cibleId;
    if (_mode == 'salle') salle = _cibleId;

    final resultat = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SessionFormDialog(
        app: app,
        semaineInitiale: app.semaine,
        creneauInitial: creneau['id'] as int,
        salleInitiale: salle,
        enseignantInitial: enseignant,
        groupesInitiaux: groupes.isEmpty ? null : groupes,
      ),
    );
    if (resultat != null) {
      await _charger();
      if (mounted) afficherMessage(context, resultat);
    }
  }

  Future<void> _ouvrirEdition(AppState app, Map<String, dynamic> seance) async {
    final resultat = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SessionFormDialog(app: app, seance: seance),
    );
    if (resultat != null) {
      await _charger();
      if (mounted) afficherMessage(context, resultat);
    }
  }

  Future<void> _supprimerSeance(
    AppState app,
    Map<String, dynamic> seance,
  ) async {
    final ok = await confirmer(
      context,
      titre: 'Supprimer la séance ?',
      message:
          '${seance['ecue_code']} · ${_groupesAffiches(app, seance)} — semaine ${seance['semaine']}, ${app.libelleCreneau(seance['creneau_id'])}.\n\n'
          'Seule la semaine ${seance['semaine']} sera affectée.',
    );
    if (!ok || !mounted) return;
    try {
      await app.api.delete('/seances/${seance['id']}');
      await _charger();
      if (mounted) afficherMessage(context, 'Séance supprimée');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  /// Groupes à afficher pour une séance.
  ///
  /// Un CM mutualisé concerne tous les groupes du niveau, y compris lorsque la
  /// séance a été créée avant cette règle avec un seul groupe enregistré.
  String _groupesAffiches(AppState app, Map<String, dynamic> seance) {
    final stockes = '${seance['groupes_noms'] ?? ''}';
    if ('${seance['type_seance']}' != 'CM') return stockes;
    if (!app.cmMutualise(seance['ecue_id'], seance['enseignant_id'])) {
      return stockes;
    }
    final noms = app
        .groupesMutualises(seance['ecue_id'], seance['enseignant_id'])
        .map((groupe) => '${groupe['nom'] ?? ''}')
        .where((nom) => nom.isNotEmpty)
        .toList();
    return noms.isEmpty ? stockes : noms.join(', ');
  }

  Widget _carteSeance(AppState app, Map<String, dynamic> seance) {
    final type = '${seance['type_seance']}';
    final couleur = _couleurType(type);
    final annulee = seance['statut'] == 'annulee';
    final effectuee = seance['statut'] == 'effectuee';
    final groupesNoms = _groupesAffiches(app, seance);
    // Un CM mutualisé est enregistré pour tous les groupes du niveau : même
    // en affichage « par groupe », le créneau doit les mentionner tous.
    final mutualise = type == 'CM' && groupesNoms.contains(',');
    final groupe = _groupeParParite(app);
    final niveau = '${seance['niveau_nom'] ?? ''}'.trim();
    final semestre = groupe
        ? '${seance['_semestre_nom'] ?? ''} · ${seance['_semestre_annee'] ?? ''}'
        : '';
    final contenu = <String>[
      if (_mode != 'enseignant') '${seance['enseignant_nom']}',
      if (groupe && niveau.isNotEmpty) 'Niveau : $niveau',
      if (!groupe && _mode != 'groupe' && _mode != 'niveau') groupesNoms,
      if (!groupe && (_mode == 'niveau' || (_mode == 'groupe' && mutualise)))
        groupesNoms,
      if (semestre.isNotEmpty) semestre,
      '${seance['salle_nom'] ?? 'Salle à définir'}',
    ];
    return InkWell(
      onTap: () => _detailSeance(app, seance),
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: annulee ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: couleur, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${seance['ecue_code']} — ${seance['ecue_nom']}',
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: couleur,
                        decoration: annulee ? TextDecoration.lineThrough : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (effectuee)
                    const Icon(
                      Icons.check_circle,
                      size: 12,
                      color: AppCouleurs.vert,
                    ),
                  if (seance['verrouillee'] == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 3),
                      child: Icon(
                        Icons.lock,
                        size: 11,
                        color: AppCouleurs.ambre,
                      ),
                    ),
                  const SizedBox(width: 3),
                  Text(
                    type,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: couleur,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              for (final ligne in contenu)
                Text(
                  ligne,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppCouleurs.texteDoux,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _couleurType(String type) => switch (type) {
    'CM' => AppCouleurs.bleu,
    'TD' => AppCouleurs.vert,
    'TP' => AppCouleurs.ambre,
    _ => AppCouleurs.texteDoux,
  };

  Future<void> _detailSeance(AppState app, Map<String, dynamic> seance) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> agir(Future<void> Function() action) async {
            try {
              await action();
              await _charger();
              if (context.mounted) Navigator.pop(context);
              if (mounted)
                afficherMessage(
                  this.context,
                  'Séance mise à jour pour la semaine ${seance['semaine']}',
                );
            } catch (e) {
              if (context.mounted)
                afficherMessage(context, e.toString(), erreur: true);
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Pastille(
                  '${seance['type_seance']}',
                  couleur: _couleurType('${seance['type_seance']}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${seance['ecue_code']} — ${seance['ecue_nom']}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ligneDetail(
                    Icons.schedule,
                    '${app.libelleCreneau(seance['creneau_id'])} · ${app.libelleSemaine(seance['semaine'] as int, semestreId: seance['_semestre_id'])}',
                  ),
                  _ligneDetail(
                    Icons.person_outline,
                    '${seance['enseignant_nom']}',
                  ),
                  if ('${seance['niveau_nom'] ?? ''}'.trim().isNotEmpty)
                    _ligneDetail(
                      Icons.school_outlined,
                      'Niveau : ${seance['niveau_nom']}',
                    ),
                  _ligneDetail(
                    Icons.groups_outlined,
                    _groupesAffiches(app, seance),
                  ),
                  if (_groupeParParite(app))
                    _ligneDetail(
                      Icons.event_note_outlined,
                      '${seance['_semestre_nom'] ?? ''} · ${seance['_semestre_annee'] ?? ''}',
                    ),
                  _ligneDetail(
                    Icons.meeting_room_outlined,
                    '${seance['salle_nom'] ?? 'Salle à définir'}',
                  ),
                  _ligneDetail(
                    Icons.info_outline,
                    'Statut : ${_statutLibelle('${seance['statut']}')}',
                  ),
                  if (seance['verrouillee'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Icon(Icons.lock, size: 15, color: AppCouleurs.ambre),
                          SizedBox(width: 6),
                          Text(
                            'Séance verrouillée',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppCouleurs.ambre,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if ((seance['notes'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${seance['notes']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
              if (app.peutModifier ||
                  (app.estEnseignant &&
                      app.utilisateur?.enseignantId == seance['enseignant_id']))
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showDialog<void>(
                      context: this.context,
                      builder: (context) =>
                          PresencesDialog(app: app, seance: seance),
                    );
                  },
                  icon: const Icon(Icons.how_to_reg_outlined, size: 17),
                  label: const Text('Présences'),
                ),
              if (app.peutModifier ||
                  (app.estEnseignant &&
                      app.utilisateur?.enseignantId == seance['enseignant_id']))
                if (seance['statut'] != 'effectuee')
                  TextButton.icon(
                    onPressed: () => agir(
                      () => app.api.post('/seances/${seance['id']}/statut', {
                        'statut': 'effectuee',
                      }),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 17),
                    label: const Text('Marquer effectuée'),
                  ),
              if (app.peutModifier ||
                  (app.estEnseignant &&
                      app.utilisateur?.enseignantId == seance['enseignant_id']))
                if (seance['statut'] != 'effectuee')
                  TextButton.icon(
                    onPressed: () => agir(
                      () => app.api.post('/seances/${seance['id']}/statut', {
                        'statut': seance['statut'] == 'annulee'
                            ? 'planifiee'
                            : 'annulee',
                      }),
                    ),
                    icon: Icon(
                      seance['statut'] == 'annulee'
                          ? Icons.event_available_outlined
                          : Icons.event_busy_outlined,
                      size: 17,
                    ),
                    label: Text(
                      seance['statut'] == 'annulee'
                          ? 'Rétablir la séance'
                          : 'Annuler la séance',
                    ),
                  ),
              if (app.peutModifier && seance['statut'] != 'effectuee')
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _ouvrirEdition(app, seance);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Modifier'),
                ),
              if (app.peutModifier && seance['statut'] != 'effectuee')
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _supprimerSeance(app, seance);
                  },
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('Supprimer'),
                ),
              if (app.peutModifier)
                TextButton.icon(
                  onPressed: () => agir(
                    () => app.api.post('/seances/${seance['id']}/verrouiller', {
                      'verrouillee': !(seance['verrouillee'] == true),
                    }),
                  ),
                  icon: Icon(
                    seance['verrouillee'] == true
                        ? Icons.lock_open
                        : Icons.lock_outline,
                    size: 17,
                  ),
                  label: Text(
                    seance['verrouillee'] == true
                        ? 'Déverrouiller'
                        : 'Verrouiller',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _ligneDetail(IconData icone, String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 17, color: AppCouleurs.texteDoux),
          const SizedBox(width: 9),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  String _statutLibelle(String statut) => switch (statut) {
    'effectuee' => 'Effectuée',
    'annulee' => 'Annulée',
    _ => 'Planifiée',
  };

  Map<String, dynamic>? _elementParId(
    List<Map<String, dynamic>> liste,
    dynamic id,
  ) {
    for (final e in liste) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  List<Map<String, dynamic>> _creneauxOrdonnes(AppState app) {
    final creneaux = List<Map<String, dynamic>>.from(app.creneaux);
    creneaux.sort((a, b) {
      final ja = (a['jour'] as int?) ?? 0;
      final jb = (b['jour'] as int?) ?? 0;
      if (ja != jb) return ja.compareTo(jb);
      final da = '${a['debut'] ?? ''}';
      final db = '${b['debut'] ?? ''}';
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      return '${a['fin'] ?? ''}'.compareTo('${b['fin'] ?? ''}');
    });
    return creneaux;
  }

  Set<dynamic> _niveauxIdsDeSeance(
    AppState app,
    Map<String, dynamic> seance,
  ) {
    final ids = <dynamic>{};
    final groupes = (seance['groupe_ids'] as List?) ?? [];
    for (final gid in groupes) {
      final groupe = _elementParId(app.groupes, gid);
      if (groupe == null) continue;
      final nid = groupe['niveau_id'];
      if (nid != null) ids.add(nid);
    }
    return ids;
  }

  Set<dynamic> _niveauxAvecAffectations(AppState app) {
    final ids = <dynamic>{};
    for (final affectation in app.affectations) {
      final ecue = _elementParId(app.ecues, affectation['ecue_id']);
      if (ecue == null) continue;
      final ue = _elementParId(app.ues, ecue['ue_id']);
      if (ue == null) continue;
      final brut = ue['niveau_ids'];
      if (brut is List && brut.isNotEmpty) {
        ids.addAll(brut.where((e) => e != null));
      } else if (ue['niveau_id'] != null) {
        ids.add(ue['niveau_id']);
      }
    }
    return ids;
  }

  Set<dynamic> _niveauxAvecSeances(AppState app) {
    final ids = <dynamic>{};
    for (final seance in _seances) {
      ids.addAll(_niveauxIdsDeSeance(app, seance));
    }
    return ids;
  }

  String _libelleLigneNiveau(Map<String, dynamic> niveau, AppState app) {
    final nom = '${niveau['nom'] ?? ''}'.trim();
    final filiere =
        '${niveau['filiere_code'] ?? niveau['filiere_nom'] ?? ''}'.trim();
    if (nom.isEmpty && filiere.isEmpty) return app.libelleNiveau(niveau['id']);
    if (filiere.isEmpty) return nom;
    if (nom.isEmpty) return filiere;
    return '$nom · $filiere';
  }

  List<Map<String, dynamic>> _niveauxGlobaux(AppState app) {
    final source = app.niveaux.isNotEmpty ? app.niveaux : app.niveauxTous;
    final niveaux = List<Map<String, dynamic>>.from(source);
    final avecSeances = _niveauxAvecSeances(app);
    final avecAffectations = _niveauxAvecAffectations(app);
    niveaux.sort((a, b) {
      final sa = avecSeances.contains(a['id']) ? 0 : 1;
      final sb = avecSeances.contains(b['id']) ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      final aa = avecAffectations.contains(a['id']) ? 0 : 1;
      final ab = avecAffectations.contains(b['id']) ? 0 : 1;
      if (aa != ab) return aa.compareTo(ab);
      final fa = '${a['filiere_code'] ?? a['filiere_nom'] ?? ''}'.toLowerCase();
      final fb = '${b['filiere_code'] ?? b['filiere_nom'] ?? ''}'.toLowerCase();
      final cf = fa.compareTo(fb);
      if (cf != 0) return cf;
      final oa = (a['ordre'] as int?) ?? 0;
      final ob = (b['ordre'] as int?) ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return '${a['nom'] ?? ''}'
          .toLowerCase()
          .compareTo('${b['nom'] ?? ''}'.toLowerCase());
    });
    return niveaux;
  }

  Map<String, dynamic>? _semestreCibleGlobal(
    AppState app,
    dynamic niveauId,
  ) {
    if (!_groupeParParite(app)) {
      if (app.semestreId == null) return null;
      return _elementParId(app.semestres, app.semestreId) ??
          _elementParId(app.semestresTous, app.semestreId);
    }
    final pariteSemestres = _semestresParite(app);
    if (pariteSemestres.isEmpty) return null;
    final idsParite = pariteSemestres.map((s) => s['id']).toSet();
    final courant = app.semestreCourantNiveau(niveauId as int);
    if (courant != null && idsParite.contains(courant)) {
      return _elementParId(pariteSemestres, courant);
    }
    for (final ue in app.ues) {
      final brut = ue['niveau_ids'];
      final niveauxUe = brut is List && brut.isNotEmpty
          ? brut.whereType<int>()
          : (ue['niveau_id'] is int
              ? <int>[ue['niveau_id'] as int]
              : const <int>[]);
      if (!niveauxUe.contains(niveauId)) continue;
      final sid = ue['semestre_id'];
      if (sid != null && idsParite.contains(sid)) {
        return _elementParId(pariteSemestres, sid);
      }
    }
    return pariteSemestres.first;
  }

  Future<void> _creerDepuisCelluleGlobale(
    AppState app,
    dynamic niveauId,
    Map<String, dynamic> creneau,
  ) async {
    final semestreCible = _semestreCibleGlobal(app, niveauId);
    if (semestreCible == null) {
      if (mounted) {
        afficherMessage(context, 'Aucun semestre cible disponible.', erreur: true);
      }
      return;
    }
    final reference = _groupeParParite(app) ? _semestreReference(app) : null;
    final lundi = reference == null
        ? null
        : lundiDeSemaine(reference, app.semaine);
    final semaineCible = lundi == null
        ? app.semaine
        : semaineDansSemestre(semestreCible, lundi, defaut: app.semaine);
    final groupes = app
        .groupesDeNiveau(niveauId)
        .map((g) => g['id'] as int)
        .toSet();

    final resultat = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SessionFormDialog(
        app: app,
        semaineInitiale: semaineCible,
        semestreInitial: semestreCible['id'] as int?,
        creneauInitial: creneau['id'] as int,
        groupesInitiaux: groupes.isEmpty ? null : groupes,
      ),
    );
    if (resultat != null) {
      await _charger();
      if (mounted) afficherMessage(context, resultat);
    }
  }

  Widget _grilleGlobale(AppState app) {
    final creneaux = _creneauxOrdonnes(app);
    final niveaux = _niveauxGlobaux(app);

    if (creneaux.isEmpty) {
      return const EtatVide(
        message:
            'Aucun créneau défini. Ajoutez des créneaux dans les paramètres.',
      );
    }
    if (niveaux.isEmpty) {
      return const EtatVide(
        message: 'Aucun niveau défini. Ajoutez des niveaux dans les paramètres.',
      );
    }

    // Index des séances par (niveau_id, creneau_id)
    final parCellule = <String, List<Map<String, dynamic>>>{};
    for (final seance in _seances) {
      final creneauId = seance['creneau_id'];
      if (creneauId == null) continue;
      for (final nid in _niveauxIdsDeSeance(app, seance)) {
        final cle = '$nid|$creneauId';
        (parCellule[cle] ??= <Map<String, dynamic>>[]).add(seance);
      }
    }

    // Regroupement des créneaux par jour pour l'en-tête
    final joursUtilises = <int>[];
    final parJour = <int, List<Map<String, dynamic>>>{};
    for (final c in creneaux) {
      final jour = (c['jour'] as int?) ?? 0;
      if (!parJour.containsKey(jour)) {
        joursUtilises.add(jour);
        parJour[jour] = <Map<String, dynamic>>[];
      }
      parJour[jour]!.add(c);
    }

    const double largeurNiveau = 190;
    const double largeurCreneau = 150;
    const double hauteurEnteteJour = 34;
    const double hauteurEnteteCreneau = 40;
    const double hauteurEntete = hauteurEnteteJour + hauteurEnteteCreneau;
    const double hauteurLigne = 100;
    final bordure = const BorderSide(color: Color(0xFFE2E8F0));

    Widget coinEntete() {
      return Container(
        width: largeurNiveau,
        height: hauteurEntete,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          border: Border.fromBorderSide(bordure),
        ),
        child: const Text(
          'Niveau · Filière',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppCouleurs.texteDoux,
          ),
        ),
      );
    }

    Widget enteteDroite() {
      return Row(
        children: [
          for (final jour in joursUtilises)
            Container(
              width: largeurCreneau * parJour[jour]!.length,
              decoration: BoxDecoration(
                border: Border(top: bordure, right: bordure, bottom: bordure),
              ),
              child: Column(
                children: [
                  Container(
                    height: hauteurEnteteJour,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      border: Border(bottom: bordure),
                    ),
                    child: Text(
                      jour >= 0 && jour < _jours.length ? _jours[jour] : 'Jour $jour',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppCouleurs.bleu,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: hauteurEnteteCreneau,
                    child: Row(
                      children: [
                        for (final c in parJour[jour]!)
                          Container(
                            width: largeurCreneau,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              border: Border(right: bordure),
                            ),
                            child: Text(
                              '${c['debut']}\n${c['fin']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppCouleurs.texte,
                                height: 1.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    Widget celluleGlobale(
      dynamic niveauId,
      Map<String, dynamic> creneau,
      List<Map<String, dynamic>> seances,
    ) {
      if (seances.isEmpty) {
        if (app.peutModifier) {
          return InkWell(
            onTap: () => _creerDepuisCelluleGlobale(app, niveauId, creneau),
            child: Center(
              child: Icon(
                Icons.add_circle_outline,
                size: 20,
                color: AppCouleurs.bleu.withValues(alpha: 0.28),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      }
      final items = <Widget>[
        for (final seance in seances)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: SizedBox(
              height: _groupeParParite(app) ? 92 : 78,
              child: _carteSeance(app, seance),
            ),
          ),
      ];
      if (app.peutModifier) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: InkWell(
              onTap: () => _creerDepuisCelluleGlobale(app, niveauId, creneau),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.add, size: 14, color: AppCouleurs.bleu),
                    SizedBox(width: 4),
                    Text(
                      'Ajouter',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppCouleurs.bleu,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      );
    }

    Widget celluleNiveau(Map<String, dynamic> niveau) {
      return Container(
        width: largeurNiveau,
        height: hauteurLigne,
        padding: const EdgeInsets.all(8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(left: bordure, right: bordure, bottom: bordure),
        ),
        child: Text(
          _libelleLigneNiveau(niveau, app),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppCouleurs.texte,
            height: 1.25,
          ),
        ),
      );
    }

    final corpsDroite = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final niveau in niveaux)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final jour in joursUtilises)
                for (final c in parJour[jour]!)
                  Container(
                    width: largeurCreneau,
                    height: hauteurLigne,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFDFF),
                      border: Border(right: bordure, bottom: bordure),
                    ),
                    child: celluleGlobale(
                      niveau['id'],
                      c,
                      (parCellule['${niveau['id']}|${c['id']}'] ?? const [])
                          .cast<Map<String, dynamic>>(),
                    ),
                  ),
            ],
          ),
      ],
    );

    final enteteFixe = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        coinEntete(),
        Expanded(
          child: Scrollbar(
            controller: _defilementGlobalHTete,
            thumbVisibility: true,
            notificationPredicate: (notif) => notif.depth >= 0,
            scrollbarOrientation: ScrollbarOrientation.top,
            child: SingleChildScrollView(
              controller: _defilementGlobalHTete,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: enteteDroite(),
            ),
          ),
        ),
      ],
    );

    final corpsDefilant = Expanded(
      child: Scrollbar(
        controller: _defilementGlobalV,
        thumbVisibility: true,
        notificationPredicate: (notif) => notif.depth >= 0,
        child: SingleChildScrollView(
          controller: _defilementGlobalV,
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final niveau in niveaux) celluleNiveau(niveau),
                ],
              ),
              Expanded(
                child: Scrollbar(
                  controller: _defilementGlobalHCorps,
                  thumbVisibility: true,
                  notificationPredicate: (notif) => notif.depth >= 0,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _defilementGlobalHCorps,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: corpsDroite,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            enteteFixe,
            corpsDefilant,
          ],
        ),
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  final String texte;
  final Color couleur;

  const _Legende(this.texte, this.couleur);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: couleur,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          texte,
          style: const TextStyle(
            fontSize: 10.5,
            color: AppCouleurs.texteDoux,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Rapport des conflits de salle, d'enseignant et de groupe.
class _DialogConflits extends StatelessWidget {
  const _DialogConflits({required this.conflits});

  final List<Map<String, dynamic>> conflits;

  @override
  Widget build(BuildContext context) {
    final reparables = conflits.any(
      (conflit) => ((conflit['seances'] as List?) ?? [])
          .whereType<Map>()
          .any((seance) => seance['deplacable'] == true),
    );
    return AlertDialog(
      title: Text(
        conflits.isEmpty
            ? 'Aucun conflit'
            : '${conflits.length} conflit(s) détecté(s)',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 680,
        child: conflits.isEmpty
            ? const Text(
                'Aucune salle, aucun enseignant et aucun groupe n’est '
                'mobilisé deux fois au même moment.',
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: conflits.length,
                  separatorBuilder: (_, _) => const Divider(height: 18),
                  itemBuilder: (context, index) =>
                      _LigneConflit(conflit: conflits[index]),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Fermer'),
        ),
        if (reparables)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Réparer automatiquement'),
          ),
      ],
    );
  }
}

class _LigneConflit extends StatelessWidget {
  const _LigneConflit({required this.conflit});

  final Map<String, dynamic> conflit;

  static const _libelles = {
    'salle': 'Salle',
    'enseignant': 'Enseignant',
    'groupe': 'Groupe',
  };

  @override
  Widget build(BuildContext context) {
    final seances = ((conflit['seances'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppCouleurs.rouge,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_libelles[conflit['type']] ?? conflit['type']} · '
                '${conflit['ressource']} — ${conflit['creneau']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Semaine du ${formaterDate('${conflit['lundi']}')}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        for (final seance in seances)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '• ${seance['semestre']} · S${seance['semaine']} · '
              '${seance['ecue']} · ${seance['enseignant']} · '
              '${seance['salle']}'
              '${seance['deplacable'] == true ? '' : ' (non déplaçable)'}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
