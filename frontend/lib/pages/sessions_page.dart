import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/semestres_parite.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'notes/presences_dialog.dart';
import 'notes/suivi_cours_dialog.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<Map<String, dynamic>> _seances = [];
  bool _chargement = true;
  String? _erreur;
  bool _initialise = false;
  int _semaine = 0;
  int? _semestreId;
  int? _enseignantId;
  int? _groupeId;
  String? _statut;
  final TextEditingController _recherche = TextEditingController();
  String _filtreTexte = '';

  /// Défilement horizontal du tableau : la barre reste visible pour atteindre
  /// les colonnes de droite (statut, verrou, actions).
  final ScrollController _defilementTableau = ScrollController();
  final ScrollController _defilementVertical = ScrollController();

  static const _jours = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
  ];

  @override
  void dispose() {
    _recherche.dispose();
    _defilementTableau.dispose();
    _defilementVertical.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialise) {
      _initialise = true;
      final app = context.read<AppState>();
      _semestreId = app.semestreId;
      _semaine = app.semainePourDate(DateTime.now(), _semestreId);
      if (app.estEnseignant) {
        _enseignantId = app.utilisateur?.enseignantId;
      }
      _charger();
    }
  }

  int get _periodeCourante =>
      (DateTime.now().month >= 9 || DateTime.now().month <= 1) ? 1 : 2;

  List<Map<String, dynamic>> _semestresPariteTous(AppState app) {
    final source =
        app.semestresTous.isNotEmpty ? app.semestresTous : app.semestres;
    final liste = <Map<String, dynamic>>[];
    for (final s in source) {
      if ('${s['annee'] ?? ''}' != _anneeCourante) continue;
      final numero = numeroSemestre('${s['nom'] ?? ''}');
      if (numero == null || (numero.isOdd ? 1 : 2) != _periodeCourante) {
        continue;
      }
      liste.add({...s, '_numero': numero});
    }
    liste.sort((a, b) => (a['_numero'] as int).compareTo(b['_numero'] as int));
    return liste;
  }

  bool _modePariteTous(AppState app) => _groupeId == null;

  Future<void> _charger() async {
    final app = context.read<AppState>();
    if (_modePariteTous(app)) {
      await _chargerTousGroupes(app);
      return;
    }
    final semestreId = _semestreId ?? app.semestreId;
    if (semestreId == null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.liste('/seances', {
        'semestre_id': semestreId,
        if (_semaine > 0) 'semaine': _semaine,
        if (_enseignantId != null) 'enseignant_id': _enseignantId,
        if (_groupeId != null) 'groupe_id': _groupeId,
        if (_statut != null) 'statut': _statut,
      });
      if (mounted) setState(() => _seances = donnees);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _chargerTousGroupes(AppState app) async {
    final semestres = _semestresPariteTous(app);
    final reference = semestres.firstWhere(
      (s) => s['id'] == _semestreId,
      orElse: () => semestres.isNotEmpty
          ? semestres.first
          : <String, dynamic>{'id': _semestreId ?? app.semestreId},
    );
    final lundi = (_semaine > 0 && reference.isNotEmpty)
        ? lundiDeSemaine(reference, _semaine)
        : null;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final cibles = semestres.isNotEmpty
          ? semestres
          : [
              if ((_semestreId ?? app.semestreId) != null)
                {'id': _semestreId ?? app.semestreId},
            ];
      final resultats = await Future.wait([
        for (final s in cibles)
          app.api.liste('/seances', {
            'semestre_id': s['id'],
            if (_semaine > 0)
              'semaine': lundi == null
                  ? _semaine
                  : semaineDansSemestre(s, lundi, defaut: _semaine),
            if (_enseignantId != null) 'enseignant_id': _enseignantId,
            if (_statut != null) 'statut': _statut,
          }),
      ]);
      final seances = <Map<String, dynamic>>[];
      for (final liste in resultats) {
        for (final s in liste) {
          seances.add(Map<String, dynamic>.from(s));
        }
      }
      // dédoublonner par id
      final vus = <int>{};
      final uniques = <Map<String, dynamic>>[];
      for (final s in seances) {
        final id = s['id'];
        if (id is int) {
          if (vus.contains(id)) continue;
          vus.add(id);
        }
        uniques.add(s);
      }
      if (mounted) setState(() => _seances = uniques);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  List<Map<String, dynamic>> get _seancesAffichees {
    final q = _filtreTexte.trim().toLowerCase();
    if (q.isEmpty) return _seances;
    return _seances.where((s) {
      final jourIndex = ((s['creneau_jour'] as int?) ?? 1) - 1;
      final jour = jourIndex >= 0 && jourIndex < _jours.length ? _jours[jourIndex] : '';
      final texte = [
        s['semaine'],
        jour,
        s['creneau_heure_debut'],
        s['creneau_heure_fin'],
        s['ecue_code'],
        s['ecue_nom'],
        s['type_seance'],
        s['groupes_noms'],
        s['enseignant_nom'],
        s['salle_nom'],
        _statutLibelle('${s['statut']}'),
        s['notes'],
      ].join(' ').toLowerCase();
      return texte.contains(q);
    }).toList();
  }

  String get _anneeCourante {
    final m = DateTime.now();
    final debut = m.month >= 9 ? m.year : m.year - 1;
    return '$debut-${debut + 1}';
  }

  List<int> _semestresGroupe(AppState app, int groupeId) {
    final annee = _anneeCourante;
    final enseignantId = app.utilisateur?.enseignantId;
    final semestresComplets =
        app.semestresTous.isNotEmpty ? app.semestresTous : app.semestres;
    final ids = <int>{};
    for (final a in app.affectations) {
      if (enseignantId != null && a['enseignant_id'] != enseignantId) continue;
      final gid = a['groupe_id'];
      final concerneGroupe = gid == groupeId;
      final concerneNiveau = gid == null &&
          app.groupesDeNiveauECUE(a['ecue_id']).any((g) => g['id'] == groupeId);
      if (!concerneGroupe && !concerneNiveau) continue;
      final sid = a['semestre_id'];
      if (sid is! int) continue;
      final sem = semestresComplets.where((s) => s['id'] == sid).firstOrNull;
      if (sem != null && '${sem['annee'] ?? ''}' == annee) ids.add(sid);
    }
    final liste = ids.toList();
    liste.sort((a, b) {
      final sa = semestresComplets.where((s) => s['id'] == a).firstOrNull;
      final sb = semestresComplets.where((s) => s['id'] == b).firstOrNull;
      return '${sa?['nom'] ?? ''}'.compareTo('${sb?['nom'] ?? ''}');
    });
    return liste;
  }

  int _semaineCourantePour(int? semestreId, AppState app) {
    final id = semestreId ?? app.semestreId;
    final max = app.nombreSemainesDe(id);
    final semaine = app.semainePourDate(DateTime.now(), id);
    return semaine.clamp(1, max);
  }

  void _changerGroupe(int? groupeId) {
    if (groupeId == _groupeId) return;
    final app = context.read<AppState>();
    int? semestreCible = _semestreId ?? app.semestreId;
    if (groupeId == null) {
      // Garder le semestre courant pour afficher tous les groupes sur la même période.
      semestreCible = _semestreId ?? app.semestreId;
    } else {
      final semestres = _semestresGroupe(app, groupeId);
      if (semestres.isNotEmpty) {
        final periode =
            (DateTime.now().month >= 9 || DateTime.now().month <= 1) ? 1 : 2;
        int choisi = semestres.first;
        final semestresComplets =
            app.semestresTous.isNotEmpty ? app.semestresTous : app.semestres;
        for (final sid in semestres) {
          final sem = semestresComplets.where((s) => s['id'] == sid).firstOrNull;
          final numero = numeroSemestre('${sem?['nom'] ?? ''}');
          if (numero != null && (numero.isOdd ? 1 : 2) == periode) {
            choisi = sid;
            break;
          }
        }
        semestreCible = choisi;
      }
    }
    setState(() {
      _groupeId = groupeId;
      _erreur = null;
      _semestreId = semestreCible;
      _semaine = _semaineCourantePour(semestreCible, app);
    });
    _charger();
  }

  Future<void> _generer() async {
    final app = context.read<AppState>();
    final ok = await confirmer(
      context,
      titre: 'Générer les séances',
      message: 'Les séances non verrouillées du semestre seront remplacées par une nouvelle proposition. Continuer ?',
      action: 'Générer',
      danger: false,
    );
    if (!ok || !mounted) return;
    try {
      final resultat = await app.api.post('/generer', {
        'semestre_id': _semestreId ?? app.semestreId,
        'remplacer': true,
      });
      await _charger();
      if (!mounted) return;
      afficherMessage(context, '${resultat['message']}');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scrollbar(
      controller: _defilementVertical,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _defilementVertical,
        padding: const EdgeInsets.all(24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Séances',
            sousTitre:
                'Créneaux planifiés, verrouillage et suivi de réalisation — ${_modePariteTous(app) ? libellePeriodeComplete(_periodeCourante == 1 ? 'impairs' : 'pairs', _anneeCourante) : app.libelleSemestre(_semestreId ?? app.semestreId)}'
                '${_semaine > 0 ? ' · ${app.libelleSemaine(_semaine, semestreId: _semestreId ?? app.semestreId)}' : ''}.',
            actions: [
              OutlinedButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
              if (app.peutModifier) ...[
                OutlinedButton.icon(
                  onPressed: _generer,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Générer'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _ouvrirFormulaire(app),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nouvelle séance'),
                ),
              ],
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
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      ChampRecherche(
                        controleur: _recherche,
                        hint: 'Rechercher une séance…',
                        onChanged: (v) => setState(() => _filtreTexte = v),
                      ),
                      _filtre(
                        'Semaine',
                        SizedBox(
                          width: 245,
                          child: Builder(
                            builder: (context) {
                              final semestreId = _semestreId ?? app.semestreId;
                              final maxSemaines = app.nombreSemainesDe(semestreId);
                              final semaineValeur =
                                  (_semaine >= 0 && _semaine <= maxSemaines)
                                      ? _semaine
                                      : 0;
                              return DropdownButtonFormField<int>(
                                key: ValueKey('semaine-$semestreId-$semaineValeur'),
                                initialValue: semaineValeur,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 0,
                                    child: Text(
                                      'Toutes',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  for (var i = 1; i <= maxSemaines; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        app.libelleSemaine(
                                          i,
                                          court: true,
                                          semestreId: semestreId,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  setState(() => _semaine = v ?? 0);
                                  _charger();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      _filtre(
                        'Enseignant',
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<int?>(
                            initialValue: _enseignantId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: [
                              if (!app.estEnseignant)
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(
                                    'Tous',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              for (final e in (app.estEnseignant
                                  ? app.enseignants.where(
                                      (x) => x['id'] == app.utilisateur?.enseignantId,
                                    )
                                  : app.enseignants))
                                DropdownMenuItem<int?>(
                                  value: e['id'] as int,
                                  child: Text(
                                    app.libelleEnseignant(e),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                            onChanged: app.estEnseignant
                                ? null
                                : (v) {
                                    setState(() => _enseignantId = v);
                                    _charger();
                                  },
                          ),
                        ),
                      ),
                      _filtre(
                        'Groupe',
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int?>(
                            key: ValueKey('groupe-$_groupeId'),
                            initialValue: (app.estEnseignant
                                        ? app.groupesDeEnseignant(app.utilisateur?.enseignantId)
                                        : app.groupes)
                                    .any((g) => g['id'] == _groupeId)
                                ? _groupeId
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
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text(
                                  'Tous',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              for (final g in (app.estEnseignant
                                  ? app.groupesDeEnseignant(app.utilisateur?.enseignantId)
                                  : app.groupes))
                                DropdownMenuItem<int?>(
                                  value: g['id'] as int,
                                  child: Text(
                                    app.libelleGroupe(g['id']),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                            onChanged: _changerGroupe,
                          ),
                        ),
                      ),
                      _filtre(
                        'Statut',
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String?>(
                            initialValue: _statut,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'Tous',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'planifiee',
                                child: Text(
                                  'Planifiée',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'effectuee',
                                child: Text(
                                  'Effectuée',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'annulee',
                                child: Text(
                                  'Annulée',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() => _statut = v);
                              _charger();
                            },
                          ),
                        ),
                      ),
                      if (_semaine > 0 ||
                          (app.estEnseignant
                              ? _groupeId != null
                              : _enseignantId != null) ||
                          _groupeId != null ||
                          _statut != null ||
                          _filtreTexte.trim().isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            _recherche.clear();
                            setState(() {
                              _filtreTexte = '';
                              _semaine = _semaineCourantePour(
                                _semestreId ?? app.semestreId,
                                app,
                              );
                              _enseignantId = app.estEnseignant
                                  ? app.utilisateur?.enseignantId
                                  : null;
                              _groupeId = null;
                              _statut = null;
                            });
                            _charger();
                          },
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 17,
                          ),
                          label: const Text('Réinitialiser'),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Pastille(
                          _filtreTexte.trim().isEmpty
                              ? '${_seances.length} séance${_seances.length > 1 ? 's' : ''}'
                              : '${_seancesAffichees.length} / ${_seances.length} séance${_seances.length > 1 ? 's' : ''}',
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_chargement)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 70),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_erreur != null)
                  EtatVide(
                    message: _erreur!,
                    icone: Icons.cloud_off_outlined,
                    action: ElevatedButton(
                      onPressed: _charger,
                      child: const Text('Réessayer'),
                    ),
                  )
                else if (_seancesAffichees.isEmpty)
                  EtatVide(
                    message: _filtreTexte.trim().isEmpty
                        ? 'Aucune séance ne correspond aux filtres.'
                        : 'Aucune séance ne correspond à la recherche.',
                    icone: Icons.event_busy_outlined,
                    action: app.peutModifier && _filtreTexte.trim().isEmpty
                        ? TextButton.icon(
                            onPressed: () => _ouvrirFormulaire(app),
                            icon: const Icon(Icons.add),
                            label: const Text('Créer une séance'),
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
                        columnSpacing: 20,
                        horizontalMargin: 16,
                        columns: [
                          const DataColumn(label: Text('SEMAINE')),
                          const DataColumn(label: Text('JOUR')),
                          const DataColumn(label: Text('HORAIRE')),
                          const DataColumn(label: Text('ECUE')),
                          const DataColumn(label: Text('TYPE')),
                          const DataColumn(label: Text('GROUPE(S)')),
                          const DataColumn(label: Text('ENSEIGNANT')),
                          const DataColumn(label: Text('SALLE')),
                          const DataColumn(label: Text('STATUT')),
                          const DataColumn(label: Text('VERROU')),
                          if (app.peutModifier ||
                              app.estEnseignant ||
                              app.utilisateur?.role == 'lecteur')
                            const DataColumn(label: Text('ACTIONS')),
                        ],
                        rows: [
                          for (final seance in _seancesAffichees)
                            DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('S${seance['semaine']}'),
                                      Builder(
                                        builder: (_) {
                                          final periode = app.periodeSemaine(
                                            seance['semaine'] as int,
                                            court: true,
                                          );
                                          if (periode.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Text(
                                            periode,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppCouleurs.texteDoux,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Text(_jour(seance['creneau_jour'] as int?)),
                                ),
                                DataCell(
                                  Text(
                                    '${seance['creneau_debut']} – ${seance['creneau_fin']}',
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 220,
                                    child: Text(
                                      '${seance['ecue_code']} · ${seance['ecue_nom']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Pastille(
                                    '${seance['type_seance']}',
                                    couleur: _couleurType(
                                      '${seance['type_seance']}',
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 150,
                                    child: Text(
                                      '${seance['groupes_noms']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 160,
                                    child: Text(
                                      '${seance['enseignant_nom']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text('${seance['salle_nom'] ?? '—'}')),
                                DataCell(
                                  Pastille(
                                    _statutLibelle('${seance['statut']}'),
                                    couleur: _couleurStatut(
                                      '${seance['statut']}',
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Icon(
                                    seance['verrouillee'] == true
                                        ? Icons.lock
                                        : Icons.lock_open,
                                    size: 16,
                                    color: seance['verrouillee'] == true
                                        ? AppCouleurs.ambre
                                        : AppCouleurs.texteDoux,
                                  ),
                                ),
                                if (app.peutModifier ||
                                    app.estEnseignant ||
                                    app.utilisateur?.role == 'lecteur')
                                  DataCell(_actions(app, seance)),
                              ],
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

  Widget _filtre(String label, Widget enfant) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppCouleurs.texteDoux,
          ),
        ),
        const SizedBox(height: 5),
        enfant,
      ],
    );
  }

  Widget _actions(AppState app, Map<String, dynamic> seance) {
    final peutStatut =
        app.peutModifier ||
        (app.estEnseignant &&
            app.utilisateur?.enseignantId == seance['enseignant_id']);
    final modifiable =
        app.peutModifier &&
        seance['verrouillee'] != true &&
        seance['statut'] != 'effectuee';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (peutStatut)
          IconButton(
            tooltip: 'Feuille de présence',
            icon: const Icon(
              Icons.how_to_reg_outlined,
              size: 18,
              color: AppCouleurs.teal,
            ),
            onPressed: () => _ouvrirPresences(app, seance),
          ),
        if (peutStatut)
          IconButton(
            tooltip: 'Suivi cours',
            icon: const Icon(
              Icons.menu_book_outlined,
              size: 18,
              color: AppCouleurs.teal,
            ),
            onPressed: () => _ouvrirSuiviCours(app, seance),
          ),
        if (peutStatut)
          PopupMenuButton<String>(
            tooltip: 'Changer le statut',
            icon: const Icon(
              Icons.fact_check_outlined,
              size: 18,
              color: AppCouleurs.teal,
            ),
            onSelected: (statut) => _changerStatut(app, seance, statut),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'planifiee',
                child: Text('Marquer planifiée'),
              ),
              PopupMenuItem(
                value: 'effectuee',
                child: Text('Marquer effectuée'),
              ),
              PopupMenuItem(value: 'annulee', child: Text('Marquer annulée')),
            ],
          ),
        if (peutStatut && seance['statut'] != 'effectuee')
          IconButton(
            tooltip: seance['statut'] == 'annulee'
                ? 'Rétablir la séance'
                : 'Annuler la séance',
            icon: Icon(
              seance['statut'] == 'annulee'
                  ? Icons.event_available_outlined
                  : Icons.event_busy_outlined,
              size: 18,
              color: seance['statut'] == 'annulee'
                  ? AppCouleurs.vert
                  : AppCouleurs.ambre,
            ),
            onPressed: () => _changerStatut(
              app,
              seance,
              seance['statut'] == 'annulee' ? 'planifiee' : 'annulee',
            ),
          ),
        if (app.peutModifier) ...[
          IconButton(
            tooltip: seance['verrouillee'] == true
                ? 'Déverrouiller'
                : 'Verrouiller',
            icon: Icon(
              seance['verrouillee'] == true
                  ? Icons.lock_open
                  : Icons.lock_outline,
              size: 18,
              color: AppCouleurs.ambre,
            ),
            onPressed: () async {
              try {
                await app.api.post('/seances/${seance['id']}/verrouiller', {
                  'verrouillee': !(seance['verrouillee'] == true),
                });
                await _charger();
                if (mounted) afficherMessage(context, 'Verrouillage modifié');
              } catch (e) {
                if (mounted) {
                  afficherMessage(context, e.toString(), erreur: true);
                }
              }
            },
          ),
          if (modifiable)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppCouleurs.bleu,
              ),
              onPressed: () => _ouvrirFormulaire(app, seance: seance),
            )
          else
            IconButton(
              tooltip: _raisonNonModifiable(seance),
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: Color(0xFFCBD5E1),
              ),
              onPressed: null,
            ),
          if (modifiable)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppCouleurs.rouge,
              ),
              onPressed: () => _supprimerSeance(app, seance),
            )
          else
            IconButton(
              tooltip: _raisonNonModifiable(seance),
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Color(0xFFCBD5E1),
              ),
              onPressed: null,
            ),
        ],
      ],
    );
  }

  /// Pourquoi la modification d'une séance est indisponible.
  String _raisonNonModifiable(Map<String, dynamic> seance) {
    if (seance['verrouillee'] == true) {
      return 'Séance verrouillée : déverrouillez-la pour la modifier ou la supprimer';
    }
    if (seance['statut'] == 'effectuee') {
      return 'Séance effectuée : repassez-la en « planifiée » pour la modifier ou la supprimer';
    }
    return 'Modification indisponible';
  }

  Future<void> _ouvrirPresences(
    AppState app,
    Map<String, dynamic> seance,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => PresencesDialog(app: app, seance: seance),
    );
  }

  Future<void> _ouvrirSuiviCours(
    AppState app,
    Map<String, dynamic> seance,
  ) async {
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SuiviCoursDialog(app: app, seance: seance),
    );
    await _charger();
  }

  Future<void> _changerStatut(
    AppState app,
    Map<String, dynamic> seance,
    String statut,
  ) async {
    try {
      await app.api.post('/seances/${seance['id']}/statut', {'statut': statut});
      await _charger();
      if (mounted) {
        afficherMessage(
          context,
          statut == 'annulee'
              ? 'Séance annulée pour la semaine ${seance['semaine']} uniquement'
              : statut == 'planifiee'
              ? 'Séance rétablie pour la semaine ${seance['semaine']}'
              : 'Statut mis à jour',
        );
      }
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
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
          '${seance['ecue_code']} · ${seance['groupes_noms']} — semaine ${seance['semaine']}, ${_jour(seance['creneau_jour'] as int?)} ${seance['creneau_debut']}.\n\n'
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

  Future<void> _ouvrirFormulaire(
    AppState app, {
    Map<String, dynamic>? seance,
  }) async {
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

  String _jour(int? jour) {
    if (jour == null || jour < 0 || jour >= _jours.length) return '—';
    return _jours[jour];
  }

  String _statutLibelle(String statut) => switch (statut) {
    'effectuee' => 'Effectuée',
    'annulee' => 'Annulée',
    _ => 'Planifiée',
  };

  Color _couleurStatut(String statut) => switch (statut) {
    'effectuee' => AppCouleurs.vert,
    'annulee' => AppCouleurs.rouge,
    _ => AppCouleurs.bleu,
  };

  Color _couleurType(String type) => switch (type) {
    'CM' => AppCouleurs.bleu,
    'TD' => AppCouleurs.vert,
    'TP' => AppCouleurs.ambre,
    _ => AppCouleurs.texteDoux,
  };
}

class SessionFormDialog extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic>? seance;

  // Valeurs de pré-remplissage utilisées depuis la grille de l'emploi du temps.
  final int? semaineInitiale;
  final int? semestreInitial;
  final int? creneauInitial;
  final int? salleInitiale;
  final int? enseignantInitial;
  final Set<int>? groupesInitiaux;

  const SessionFormDialog({
    super.key,
    required this.app,
    this.seance,
    this.semaineInitiale,
    this.semestreInitial,
    this.creneauInitial,
    this.salleInitiale,
    this.enseignantInitial,
    this.groupesInitiaux,
  });

  @override
  State<SessionFormDialog> createState() => _SessionFormDialogState();
}

class _SessionFormDialogState extends State<SessionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _semestreId;
  late int _semaine;
  int? _creneauId;
  int? _salleId;
  int? _enseignantId;
  int? _ecueId;
  String _type = 'CM';
  String _statut = 'planifiee';
  bool _verrouillee = false;
  late Set<int> _groupes;
  late int _semaineFin;
  bool _reguliere = false;
  final _notes = TextEditingController();

  bool _enregistrement = false;
  String? _erreur;

  bool get _edition => widget.seance != null;

  @override
  void initState() {
    super.initState();
    final s = widget.seance;
    final app = widget.app;
    _semestreId =
        (s?['semestre_id'] as int?) ??
        widget.semestreInitial ??
        app.semestreId ??
        1;
    _semaine = (s?['semaine'] as int?) ?? widget.semaineInitiale ?? app.semaine;
    _semaineFin = app.nombreSemainesDe(_semestreId);
    _creneauId =
        (s?['creneau_id'] as int?) ??
        widget.creneauInitial ??
        (app.creneaux.isEmpty ? null : app.creneaux.first['id'] as int);
    _salleId =
        (s?['salle_id'] as int?) ??
        widget.salleInitiale ??
        (app.salles.isEmpty ? null : app.salles.first['id'] as int);
    _ecueId = (s?['ecue_id'] as int?) ?? _ecueParDefaut(app);
    _type = (s?['type_seance'] as String?) ?? 'CM';
    _enseignantId = app.estEnseignant
        ? app.utilisateur?.enseignantId
        : ((s?['enseignant_id'] as int?) ??
            widget.enseignantInitial ??
            _premierEnseignant(app));
    _statut = (s?['statut'] as String?) ?? 'planifiee';
    _verrouillee = (s?['verrouillee'] as bool?) ?? false;
    _notes.text = (s?['notes'] as String?) ?? '';
    final existants = (s?['groupe_ids'] as List?)?.map((e) => e as int).toSet();
    if (existants != null && existants.isNotEmpty) {
      _groupes = existants;
    } else {
      _groupes = _groupesParDefaut(app);
    }
  }

  List<Map<String, dynamic>> _ecuesDisponibles(AppState app) =>
      app.ecuesDeSemestre(_semestreId);

  /// Choisit l'ECUE le plus pertinent d'après le contexte de la grille
  /// (enseignant et/ou groupes déjà sélectionnés).
  int? _ecueParDefaut(AppState app) {
    final liste = _ecuesDisponibles(app);
    if (liste.isEmpty) return null;
    final enseignant = widget.enseignantInitial;
    final prefill = widget.groupesInitiaux ?? const <int>{};
    final correspondants = liste.where((ecue) {
      final okEnseignant =
          enseignant == null ||
          app.affectations.any(
            (a) =>
                a['ecue_id'] == ecue['id'] && a['enseignant_id'] == enseignant,
          );
      final okGroupe =
          prefill.isEmpty ||
          prefill.any(
            (g) => app.affectations.any(
              (a) => a['ecue_id'] == ecue['id'] && a['groupe_id'] == g,
            ),
          );
      return okEnseignant && okGroupe;
    }).toList();
    return (correspondants.isNotEmpty
            ? correspondants.first
            : liste.first)['id']
        as int;
  }

  int? _premierEnseignant(AppState app) {
    final liste = _enseignantsDisponibles(app);
    return liste.isEmpty ? null : liste.first['id'] as int;
  }

  List<Map<String, dynamic>> _enseignantsDisponibles(AppState app) {
    if (app.estEnseignant) {
      return app.enseignants
          .where((e) => e['id'] == app.utilisateur?.enseignantId)
          .toList();
    }
    final liste = app.enseignantsDeECUEPourType(_ecueId, _type);
    final enseignantSession = widget.seance?['enseignant_id'];
    if (_enseignantId != null && !liste.any((e) => e['id'] == _enseignantId)) {
      // Conserve l'enseignant de la séance en édition pour éviter de perdre la donnée.
      if (_enseignantId == enseignantSession) {
        return [
          ...app.enseignants.where((e) => e['id'] == _enseignantId),
          ...liste,
        ];
      }
    }
    return liste;
  }

  List<Map<String, dynamic>> _groupesDisponibles(
    AppState app, {
    bool inclureSelection = true,
  }) {
    // Un CM mutualisé (CM commun) concerne tous les groupes du niveau.
    final mutualise = _type == 'CM' && app.cmMutualise(_ecueId, _enseignantId);
    final liste = [
      ...(mutualise
          ? app.groupesMutualises(_ecueId, _enseignantId)
          : app.groupesDeECUEEnseignant(_ecueId, _enseignantId)),
    ];
    if (inclureSelection) {
      for (final id in _groupes) {
        if (!liste.any((g) => g['id'] == id)) {
          liste.addAll(app.groupes.where((g) => g['id'] == id));
        }
      }
    }
    return liste;
  }

  /// Groupes à sélectionner automatiquement pour le type de séance courant.
  Set<int> _groupesPourType(AppState app) {
    if (_type == 'CM' && app.cmMutualise(_ecueId, _enseignantId)) {
      final tous = app
          .groupesMutualises(_ecueId, _enseignantId)
          .map((g) => g['id'] as int)
          .toSet();
      if (tous.isNotEmpty) return tous;
    }
    final eligibles = app.groupesDeECUEEnseignant(_ecueId, _enseignantId);
    return {if (eligibles.isNotEmpty) eligibles.first['id'] as int};
  }

  Set<int> _groupesParDefaut(AppState app) {
    final prefill = widget.groupesInitiaux;
    if (prefill != null && prefill.isNotEmpty) {
      final eligibles = _groupesDisponibles(app, inclureSelection: false);
      final communs = eligibles
          .where((g) => prefill.contains(g['id']))
          .map((g) => g['id'] as int)
          .toSet();
      if (communs.isNotEmpty) return communs;
    }
    if (_type == 'CM' && app.cmMutualise(_ecueId, _enseignantId)) {
      final tous = app
          .groupesMutualises(_ecueId, _enseignantId)
          .map((g) => g['id'] as int)
          .toSet();
      if (tous.isNotEmpty) return tous;
    }
    return _groupesPourType(app);
  }

  void _choisirECUE(AppState app, int? valeur) {
    setState(() {
      _ecueId = valeur;
      if (app.estEnseignant) {
        _enseignantId = app.utilisateur?.enseignantId;
      } else {
        final enseignants = app.enseignantsDeECUEPourType(valeur, _type);
        if (!enseignants.any((e) => e['id'] == _enseignantId)) {
          _enseignantId = enseignants.isEmpty
              ? null
              : enseignants.first['id'] as int;
        }
      }
      _groupes = _groupesPourType(app);
    });
  }

  void _choisirEnseignant(AppState app, int? valeur) {
    setState(() {
      _enseignantId = valeur;
      _groupes = _groupesPourType(app);
    });
  }

  void _choisirType(AppState app, String? valeur) {
    setState(() {
      _type = valeur ?? 'CM';
      if (app.estEnseignant) {
        _enseignantId = app.utilisateur?.enseignantId;
      } else {
        final enseignantsEligibles = app.enseignantsDeECUEPourType(_ecueId, _type);
        if (_enseignantId != null &&
            !enseignantsEligibles.any((e) => e['id'] == _enseignantId)) {
          _enseignantId = enseignantsEligibles.isEmpty
              ? null
              : enseignantsEligibles.first['id'] as int?;
        }
      }
      if (_type == 'CM' && app.cmMutualise(_ecueId, _enseignantId)) {
        // CM mutualisé : tous les groupes du niveau suivent le cours.
        _groupes = _groupesPourType(app);
        return;
      }
      final eligibles = app.groupesDeECUEEnseignant(_ecueId, _enseignantId);
      final ids = eligibles.map((g) => g['id'] as int).toSet();
      final restants = _groupes.where(ids.contains).toSet();
      _groupes = restants.isEmpty ? _groupesPourType(app) : restants;
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ecues = _ecuesDisponibles(app);
    final enseignants = _enseignantsDisponibles(app);
    final groupesDisponibles = _groupesDisponibles(app);
    final mutualise = _type == 'CM' && app.cmMutualise(_ecueId, _enseignantId);
    final taille = MediaQuery.sizeOf(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Text(
        _edition ? 'Modifier la séance' : 'Nouvelle séance',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: taille.height * 0.72),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue:
                              app.semestres.any((s) => s['id'] == _semestreId)
                              ? _semestreId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Semestre',
                          ),
                          items: [
                            for (final s in app.semestres)
                              DropdownMenuItem(
                                value: s['id'] as int,
                                child: Text(app.libelleSemestre(s['id'])),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _semestreId = v;
                              _semaine = 1;
                              _semaineFin = app.nombreSemainesDe(v);
                              _reguliere = false;
                              final liste = _ecuesDisponibles(app);
                              _ecueId = liste.isEmpty
                                  ? null
                                  : liste.first['id'] as int;
                              final enseignants = app.enseignantsDeECUEPourType(
                                _ecueId,
                                _type,
                              );
                              _enseignantId = enseignants.isEmpty
                                  ? null
                                  : enseignants.first['id'] as int;
                              _groupes = _groupesPourType(app);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _semaine,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Semaine',
                          ),
                          items: [
                            for (
                              var i = 1;
                              i <= app.nombreSemainesDe(_semestreId);
                              i++
                            )
                              DropdownMenuItem(
                                value: i,
                                child: Text(
                                  app.libelleSemaine(
                                    i,
                                    court: true,
                                    semestreId: _semestreId,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _semaine = v;
                              if (_semaineFin < v) {
                                _semaineFin = app.nombreSemainesDe(_semestreId);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_edition)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'La modification ne concerne que la semaine $_semaine '
                        '(${app.periodeSemaine(_semaine, semestreId: _semestreId)}).',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppCouleurs.texteDoux,
                        ),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppCouleurs.bordure),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Séance régulière',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: const Text(
                              'Répète la séance chaque semaine. L’annulation ou la suppression ne touchera ensuite que la semaine choisie.',
                              style: TextStyle(fontSize: 11),
                            ),
                            value: _reguliere,
                            onChanged: (v) => setState(() {
                              _reguliere = v;
                              if (v && _semaineFin < _semaine) {
                                _semaineFin = app.nombreSemainesDe(_semestreId);
                              }
                            }),
                          ),
                          if (_reguliere) ...[
                            const SizedBox(height: 2),
                            DropdownButtonFormField<int>(
                              initialValue: _semaineFin >= _semaine
                                  ? _semaineFin
                                  : app.nombreSemainesDe(_semestreId),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Répéter jusqu’à',
                              ),
                              items: [
                                for (
                                  var i = _semaine;
                                  i <= app.nombreSemainesDe(_semestreId);
                                  i++
                                )
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      app.libelleSemaine(
                                        i,
                                        court: true,
                                        semestreId: _semestreId,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(() {
                                if (v != null) _semaineFin = v;
                              }),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Semaine $_semaine : ${app.periodeSemaine(_semaine, semestreId: _semestreId)} '
                              '→ semaine $_semaineFin : ${app.periodeSemaine(_semaineFin, semestreId: _semestreId)}.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppCouleurs.texteDoux,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: app.ecues.any((e) => e['id'] == _ecueId)
                              ? _ecueId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'ECUE'),
                          items: [
                            for (final e in ecues)
                              DropdownMenuItem(
                                value: e['id'] as int,
                                child: Text(
                                  app.libelleECUE(e['id']),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          validator: (v) =>
                              v == null ? 'Choisissez un ECUE' : null,
                          onChanged: (v) => _choisirECUE(app, v),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _type,
                          decoration: const InputDecoration(
                            labelText: 'Type de séance',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'CM',
                              child: Text('CM — Cours magistral'),
                            ),
                            DropdownMenuItem(
                              value: 'TD',
                              child: Text('TD — Travaux dirigés'),
                            ),
                            DropdownMenuItem(
                              value: 'TP',
                              child: Text('TP — Travaux pratiques'),
                            ),
                          ],
                          onChanged: (v) => _choisirType(app, v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue:
                              enseignants.any((e) => e['id'] == _enseignantId)
                              ? _enseignantId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Enseignant',
                          ),
                          items: [
                            for (final e in enseignants)
                              DropdownMenuItem(
                                value: e['id'] as int,
                                child: Text(
                                  app.libelleEnseignant(e),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          validator: (v) =>
                              v == null ? 'Choisissez un enseignant' : null,
                          onChanged: app.estEnseignant
                              ? null
                              : (v) => _choisirEnseignant(app, v),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue:
                              app.creneaux.any((c) => c['id'] == _creneauId)
                              ? _creneauId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Créneau',
                          ),
                          items: [
                            for (final c in app.creneaux)
                              DropdownMenuItem(
                                value: c['id'] as int,
                                child: Text(
                                  app.libelleCreneau(c['id']),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          validator: (v) =>
                              v == null ? 'Choisissez un créneau' : null,
                          onChanged: (v) => setState(() => _creneauId = v),
                        ),
                      ),
                    ],
                  ),
                  if (enseignants.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Aucun enseignant n’est affecté à cet ECUE. Ajoutez une affectation dans « Programme ».',
                        style: TextStyle(
                          color: AppCouleurs.rouge,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue:
                              app.salles.any((s) => s['id'] == _salleId)
                              ? _salleId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Salle'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('— À définir —'),
                            ),
                            for (final s in app.salles)
                              DropdownMenuItem<int?>(
                                value: s['id'] as int,
                                child: Text(
                                  '${s['nom']} · ${s['capacite']} places',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _salleId = v),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _statut,
                          decoration: const InputDecoration(
                            labelText: 'Statut',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'planifiee',
                              child: Text('Planifiée'),
                            ),
                            DropdownMenuItem(
                              value: 'effectuee',
                              child: Text('Effectuée'),
                            ),
                            DropdownMenuItem(
                              value: 'annulee',
                              child: Text('Annulée'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _statut = v ?? 'planifiee'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Groupes concernés',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (mutualise)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'CM mutualisé : tous les groupes du niveau sont concernés.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppCouleurs.teal,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppCouleurs.bordure),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final groupe in groupesDisponibles)
                          FilterChip(
                            label: Text(
                              app.libelleGroupe(groupe['id']),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: _groupes.contains(groupe['id']),
                            onSelected: mutualise
                                ? null
                                : (selectionne) {
                                    setState(() {
                                      if (selectionne) {
                                        _groupes.add(groupe['id'] as int);
                                      } else {
                                        _groupes.remove(groupe['id']);
                                      }
                                    });
                                  },
                          ),
                        if (groupesDisponibles.isEmpty)
                          Text(
                            _ecueId == null || _enseignantId == null
                                ? 'Sélectionnez d’abord un ECUE et un enseignant.'
                                : 'Aucun groupe n’est affecté à cet enseignant pour cet ECUE.',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (_groupes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sélectionnez au moins un groupe.',
                        style: TextStyle(
                          color: AppCouleurs.rouge,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (facultatif)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Verrouiller la séance',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Une séance verrouillée n’est pas remplacée par le générateur.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _verrouillee,
                    onChanged: (v) => setState(() => _verrouillee = v),
                  ),
                  if (_erreur != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
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
              : Text(_edition ? 'Enregistrer' : 'Créer la séance'),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_enseignantId == null) {
      setState(
        () => _erreur = 'Sélectionnez un enseignant affecté à cet ECUE.',
      );
      return;
    }
    if (_groupes.isEmpty) {
      setState(() => _erreur = 'Sélectionnez au moins un groupe.');
      return;
    }
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final payload = {
        'semestre_id': _semestreId,
        'semaine': _semaine,
        'creneau_id': _creneauId,
        'salle_id': _salleId,
        'enseignant_id': _enseignantId,
        'ecue_id': _ecueId,
        'type_seance': _type,
        'statut': _statut,
        'verrouillee': _verrouillee,
        'notes': _notes.text.trim(),
        'groupe_ids': _groupes.toList(),
      };
      late String message;
      if (_edition) {
        payload.remove('verrouillee');
        await widget.app.api.put('/seances/${widget.seance!['id']}', payload);
        message = 'Séance modifiée pour la semaine $_semaine uniquement';
      } else if (_reguliere) {
        payload['semaine_fin'] = _semaineFin;
        final resultat = await widget.app.api.post(
          '/seances/reguliere',
          payload,
        );
        message = '${resultat['message'] ?? 'Séances régulières créées.'}';
        final conflits = resultat['conflits'];
        if (conflits is List && conflits.isNotEmpty) {
          final semaines = conflits
              .map((conflit) => conflit is Map ? conflit['semaine'] : conflit)
              .join(', ');
          message += ' Semaine(s) ignorée(s) : $semaines.';
        }
      } else {
        await widget.app.api.post('/seances', payload);
        message = 'Séance créée pour la semaine $_semaine';
      }
      if (mounted) Navigator.pop(context, message);
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
