import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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

  /// Parité des semestres affichés pour un enseignant : `impairs`, `pairs`
  /// ou `tous` (le semestre sélectionné dans l'en-tête uniquement).
  String _parite = 'impairs';

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
      final app = context.read<AppState>();
      _mode = app.estEnseignant ? 'enseignant' : 'niveau';
      _parite = _pariteCourante();
      _cibleId = _premiereCible(app);
      _charger(autoNiveau: !app.estEnseignant);
    }
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

  /// Numéro d'un semestre d'après son nom (« Semestre 3 » → 3).
  int? _numeroSemestre(String nom) {
    final correspondance = RegExp(
      r'semestre\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(nom);
    return correspondance == null
        ? null
        : int.tryParse(correspondance.group(1)!);
  }

  /// L'enseignant consulte-t-il plusieurs semestres de même parité ?
  bool _groupeParParite(AppState app) =>
      app.estEnseignant && _mode == 'enseignant' && _parite != 'tous';

  String get _libelleParite =>
      _parite == 'pairs' ? 'Semestres pairs' : 'Semestres impairs';

  /// Semestres impairs ou pairs de l'année universitaire courante.
  ///
  /// Les semestres désactivés et sans affectation sont écartés ; un semestre
  /// où l'enseignant a réellement des cours reste affiché même s'il n'est pas
  /// marqué actif.
  List<Map<String, dynamic>> _semestresParite(AppState app) {
    final periode = _parite == 'pairs' ? 2 : 1;
    final complets = app.semestresTous.isNotEmpty
        ? app.semestresTous
        : app.semestres;
    final liste = <Map<String, dynamic>>[];
    for (final semestre in complets) {
      if ('${semestre['annee'] ?? ''}' != _anneeCourante) continue;
      final numero = _numeroSemestre('${semestre['nom'] ?? ''}');
      if (numero == null || (numero.isOdd ? 1 : 2) != periode) continue;
      final id = semestre['id'];
      final affecte = app.affectations.any(
        (affectation) => affectation['semestre_id'] == id,
      );
      if (semestre['actif'] != true &&
          !affecte &&
          !app.semestresAvecSeances.contains(id)) {
        continue;
      }
      liste.add({...semestre, '_numero': numero});
    }
    liste.sort((a, b) => (a['_numero'] as int).compareTo(b['_numero'] as int));
    return liste;
  }

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
        return app.niveaux.isEmpty ? null : app.niveaux.first['id'] as int;
      default:
        return app.groupes.isEmpty ? null : app.groupes.first['id'] as int;
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
        return '${element['nom_affichage'] ?? element['nom_complet']}';
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
            'semaine': app.semaine,
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
      _cibleId = _premiereCible(app);
    });
    _charger(autoNiveau: mode == 'niveau');
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
    // Un étudiant ne consulte que son groupe ou son niveau.
    final modes = app.estLecteur
        ? {
            for (final cle in const ['groupe', 'niveau'])
              cle: _libellesModes[cle]!,
          }
        : _libellesModes;

    if (_cibleId == null && options.isNotEmpty) {
      _cibleId = options.first['id'] as int;
      WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
    }

    // Le semestre ou la semaine par défaut change (sélection dans l'en-tête) :
    // la grille doit suivre la nouvelle semaine. Un changement de semestre
    // relance aussi la recherche d'un niveau pourvu de séances.
    final changementSemestre =
        _semestreCharge != null && _semestreCharge != app.semestreId;
    final changementSemaine =
        _semaineChargee != null && _semaineChargee != app.semaine;
    if (changementSemestre || changementSemaine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_semestreCharge != app.semestreId) {
          _charger(autoNiveau: _mode == 'niveau');
        } else if (_semaineChargee != app.semaine) {
          _charger();
        }
      });
    }

    return SingleChildScrollView(
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
                  if (app.estEnseignant)
                    _filtre(
                      label: 'Période',
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('parite-$_parite'),
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
                            : (v) {
                                setState(() => _cibleId = v);
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
                    _grille(app),
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

    return SingleChildScrollView(
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
                    '${app.libelleCreneau(seance['creneau_id'])} · ${app.libelleSemaine(seance['semaine'] as int)}',
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
