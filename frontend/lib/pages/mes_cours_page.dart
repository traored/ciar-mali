import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Période de semestres proposée dans « Mes cours ».
enum ModePeriode { impairs, pairs, toutesAnnees }

/// Espace dédié aux enseignants : leurs cours d'un semestre et, pour chaque
/// cours, la liste des étudiants inscrits.
class MesCoursPage extends StatefulWidget {
  const MesCoursPage({super.key});

  @override
  State<MesCoursPage> createState() => _MesCoursPageState();
}

class _MesCoursPageState extends State<MesCoursPage> {
  final TextEditingController _recherche = TextEditingController();
  bool _initialise = false;
  bool _chargement = false;
  String? _erreur;
  int? _semestreId;
  ModePeriode _mode = ModePeriode.impairs;
  String _filtre = '';
  List<Map<String, dynamic>> _cours = [];
  List<int> _courants = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    final app = context.read<AppState>();
    // Pendant la connexion, les référentiels ne sont pas encore chargés :
    // ouvrir la page maintenant la figerait sur une liste vide.
    if (app.chargementDonnees) return;
    _initialiser(app);
  }

  /// Prépare la page : période en cours de l'année courante et premier
  /// semestre à afficher, puis chargement des cours.
  void _initialiser(AppState app) {
    if (_initialise) return;
    _initialise = true;
    // Par défaut, on affiche la période en cours de l'année courante :
    // semestres impairs (1, 3, 5) de septembre à janvier, semestres pairs
    // (2, 4, 6) de février à août.
    _mode = _periodeCourante() == 1 ? ModePeriode.impairs : ModePeriode.pairs;
    final courants = _semestresCourants(app);
    _courants = courants;
    // Le sélecteur « Toutes les années » ouvre sur le semestre courant, puis
    // sur le semestre actif de l'application, puis sur une affectation.
    final candidats = <int>[];
    void ajouter(int? id) {
      if (id != null && !candidats.contains(id)) candidats.add(id);
    }

    for (final id in courants) {
      ajouter(id);
    }
    ajouter(app.semestreId);
    for (final semestre in app.semestres) {
      final id = semestre['id'] as int?;
      if (id != null && app.affectations.any((a) => a['semestre_id'] == id)) {
        ajouter(id);
      }
    }
    for (final semestre in app.semestres) {
      ajouter(semestre['id'] as int?);
    }
    _semestreId = courants.isNotEmpty
        ? courants.first
        : app.semestreId ?? (candidats.isEmpty ? null : candidats.first);
    _charger();
  }

  /// Année universitaire courante (ex. « 2026-2027 »).
  String get _anneeCourante {
    final maintenant = DateTime.now();
    final debut = maintenant.month >= 9 ? maintenant.year : maintenant.year - 1;
    return '$debut-${debut + 1}';
  }

  /// 1 pour les semestres impairs (septembre-janvier), 2 pour les pairs.
  int _periodeCourante() {
    final maintenant = DateTime.now();
    return (maintenant.month >= 9 || maintenant.month <= 1) ? 1 : 2;
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

  /// Tous les semestres connus, y compris ceux hors du périmètre de
  /// l'enseignant : le semestre courant de l'année courante doit rester
  /// sélectionnable même sans cours affecté.
  List<Map<String, dynamic>> _semestresComplets(AppState app) =>
      app.semestresTous.isNotEmpty ? app.semestresTous : app.semestres;

  /// Semestres de la période courante de l'année universitaire courante.
  ///
  /// Les semestres 1, 3 et 5 se déroulent de septembre à janvier ; les
  /// semestres 2, 4 et 6 de février à août. On privilégie ceux où
  /// l'enseignant a une affectation, puis les semestres actifs.
  List<int> _semestresCourants(AppState app) {
    final annee = _anneeCourante;
    final periode = _periodeCourante();
    var candidats = <Map<String, dynamic>>[];
    for (final semestre in _semestresComplets(app)) {
      if ('${semestre['annee'] ?? ''}' != annee) continue;
      final numero = _numeroSemestre('${semestre['nom'] ?? ''}');
      if (numero == null) continue;
      if ((numero.isOdd ? 1 : 2) != periode) continue;
      candidats.add(semestre);
    }
    if (candidats.isEmpty) return const [];
    // Les semestres désactivés (parcours « Master » ou « Ingénieur ») ne
    // doivent pas primer sur les semestres réellement ouverts.
    final actifs = candidats.where((s) => s['actif'] == true).toList();
    if (actifs.isNotEmpty) candidats = actifs;
    candidats.sort((a, b) {
      final aAffecte = app.affectations.any(
        (affectation) => affectation['semestre_id'] == a['id'],
      );
      final bAffecte = app.affectations.any(
        (affectation) => affectation['semestre_id'] == b['id'],
      );
      if (aAffecte != bAffecte) return aAffecte ? -1 : 1;
      final actif = (b['actif'] == true ? 1 : 0) - (a['actif'] == true ? 1 : 0);
      if (actif != 0) return actif;
      return '${a['nom']}'.compareTo('${b['nom']}');
    });
    return candidats.map((semestre) => semestre['id'] as int).toList();
  }

  /// Semestres impairs ou pairs de l'année courante, selon [_mode].
  ///
  /// Les semestres désactivés et sans affectation (Master 2, Ingénieur 5)
  /// sont écartés ; un semestre où l'enseignant a réellement des cours reste
  /// affiché même s'il n'est pas marqué actif.
  List<Map<String, dynamic>> _semestresParite(AppState app) {
    final periode = _mode == ModePeriode.pairs ? 2 : 1;
    final liste = <Map<String, dynamic>>[];
    for (final semestre in _semestresComplets(app)) {
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

  /// Semestres proposés dans le sélecteur : ceux de l'enseignant, ceux de
  /// la période courante et celui actuellement affiché.
  List<Map<String, dynamic>> _optionsSemestres(AppState app) {
    final ids = <int>{};
    for (final semestre in app.semestres) {
      final id = semestre['id'];
      if (id is int) ids.add(id);
    }
    ids.addAll(_courants);
    final affiche = _semestreId;
    if (affiche != null) ids.add(affiche);
    final options = _semestresComplets(app)
        .where((semestre) => ids.contains(semestre['id']))
        .toList();
    options.sort((a, b) {
      final annee = '${b['annee']}'.compareTo('${a['annee']}');
      if (annee != 0) return annee;
      return '${a['nom']}'.compareTo('${b['nom']}');
    });
    return options;
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    if (_mode == ModePeriode.toutesAnnees) {
      await _chargerSemestre();
    } else {
      await _chargerParite();
    }
  }

  /// Charge en une seule liste les cours de tous les semestres de la parité
  /// choisie pour l'année courante (par exemple 1, 3 et 5).
  Future<void> _chargerParite() async {
    final app = context.read<AppState>();
    final semestres = _semestresParite(app);
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    if (semestres.isEmpty) {
      if (mounted) {
        setState(() {
          _cours = [];
          _chargement = false;
        });
      }
      return;
    }
    try {
      final reponses = await Future.wait(
        semestres.map(
          (semestre) =>
              app.api.get('/notes/mes-cours', {'semestre_id': semestre['id']}),
        ),
      );
      final cours = <Map<String, dynamic>>[];
      for (var index = 0; index < semestres.length; index++) {
        final semestre = semestres[index];
        final donnees = reponses[index];
        final liste = donnees is Map
            ? (donnees['cours'] as List?) ?? const []
            : const [];
        for (final element in liste) {
          if (element is! Map) continue;
          cours.add({
            ...Map<String, dynamic>.from(element),
            'semestre_id': semestre['id'],
            'semestre_nom': '${semestre['nom'] ?? ''}',
            'semestre_annee': '${semestre['annee'] ?? ''}',
            '_numero': semestre['_numero'],
          });
        }
      }
      cours.sort((a, b) {
        final numero = ((a['_numero'] as num?) ?? 0).compareTo(
          (b['_numero'] as num?) ?? 0,
        );
        if (numero != 0) return numero;
        return '${a['ecue_code'] ?? ''}'.compareTo('${b['ecue_code'] ?? ''}');
      });
      if (!mounted) return;
      setState(() {
        _cours = cours;
        // Le sélecteur « Toutes les années » repartira du premier semestre
        // de la période affichée.
        if (!semestres.any((semestre) => semestre['id'] == _semestreId)) {
          _semestreId = semestres.first['id'] as int;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  /// Charge les cours d'un seul semestre (mode « Toutes les années »).
  Future<void> _chargerSemestre() async {
    final app = context.read<AppState>();
    final id = _semestreId;
    if (id == null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/notes/mes-cours', {
        'semestre_id': id,
      }) as Map<String, dynamic>;
      final semestre = _semestresComplets(app).firstWhere(
        (element) => element['id'] == id,
        orElse: () => const <String, dynamic>{},
      );
      final cours = ((donnees['cours'] as List?) ?? [])
          .whereType<Map>()
          .map(
            (element) => <String, dynamic>{
              ...Map<String, dynamic>.from(element),
              'semestre_id': id,
              'semestre_nom': '${semestre['nom'] ?? ''}',
              'semestre_annee': '${semestre['annee'] ?? ''}',
            },
          )
          .toList();
      if (mounted) setState(() => _cours = cours);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _changerMode(ModePeriode? mode) {
    if (mode == null || mode == _mode) return;
    setState(() {
      _mode = mode;
      _cours = [];
    });
    if (mode == ModePeriode.toutesAnnees) {
      final app = context.read<AppState>();
      final options = _optionsSemestres(app);
      if (!options.any((semestre) => semestre['id'] == _semestreId)) {
        _semestreId = options.isEmpty ? null : options.first['id'] as int;
      }
      if (_semestreId != null) _chargerSemestre();
    } else {
      _chargerParite();
    }
  }

  void _changerSemestre(int? id) {
    if (id == null || id == _semestreId) return;
    setState(() {
      _semestreId = id;
      _cours = [];
    });
    _chargerSemestre();
  }

  List<Map<String, dynamic>> get _affiches {
    final cible = _filtre.trim().toLowerCase();
    if (cible.isEmpty) return _cours;
    return _cours.where((cours) {
      final texte =
          '${cours['ecue_code']} ${cours['ecue_nom']} ${cours['ue_code']} ${cours['ue_nom']} ${cours['niveau_nom']} ${cours['filiere_code']}'
              .toLowerCase();
      return texte.contains(cible);
    }).toList();
  }

  int get _totalEtudiants => _cours.fold(
    0,
    (total, cours) => total + ((cours['nb_etudiants'] as num?)?.toInt() ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Le chargement des référentiels peut se terminer après la première
    // construction, sans que didChangeDependencies soit rejoué : on initialise
    // alors la page dès que les données sont disponibles.
    if (!_initialise && !app.chargementDonnees) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialise) return;
        _initialiser(context.read<AppState>());
      });
    }
    final cours = _affiches;
    final semestres = _optionsSemestres(app);
    final enParite = _mode != ModePeriode.toutesAnnees;
    final libelleParite = _mode == ModePeriode.pairs ? 'pairs' : 'impairs';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Mes cours',
            sousTitre: enParite
                ? 'Vos cours des semestres $libelleParite de $_anneeCourante '
                      'et les étudiants inscrits à chacun.'
                : 'Vos cours du semestre sélectionné et les étudiants inscrits à chacun.',
            actions: [
              if (enParite || _semestreId != null)
                OutlinedButton.icon(
                  onPressed: _chargement ? null : _charger,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualiser'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          CarteSection(
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<ModePeriode>(
                    key: ValueKey<ModePeriode>(_mode),
                    initialValue: _mode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Semestres',
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: ModePeriode.impairs,
                        child: Text(
                          'Impairs · 1, 3, 5 · $_anneeCourante',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      DropdownMenuItem(
                        value: ModePeriode.pairs,
                        child: Text(
                          'Pairs · 2, 4, 6 · $_anneeCourante',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const DropdownMenuItem(
                        value: ModePeriode.toutesAnnees,
                        child: Text(
                          'Toutes les années',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                    onChanged: _changerMode,
                  ),
                ),
                if (!enParite)
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey<int?>(_semestreId),
                      initialValue: semestres.any((s) => s['id'] == _semestreId)
                          ? _semestreId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Semestre',
                        isDense: true,
                      ),
                      items: [
                        for (final semestre in semestres)
                          DropdownMenuItem(
                            value: semestre['id'] as int,
                            child: Text(
                              '${semestre['nom']} · ${semestre['annee']}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                      onChanged: _changerSemestre,
                    ),
                  ),
                ChampRecherche(
                  controleur: _recherche,
                  hint: 'Rechercher un cours',
                  onChanged: (valeur) => setState(() => _filtre = valeur),
                ),
                if (_cours.isNotEmpty)
                  Pastille(
                    '${_cours.length} cours · $_totalEtudiants étudiants',
                    couleur: AppCouleurs.teal,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_erreur != null)
            CarteSection(
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 40,
                    color: AppCouleurs.rouge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _erreur!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppCouleurs.rouge),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _charger,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            )
          else if (!enParite && _semestreId == null)
            const EtatVide(
              message: 'Aucun semestre ne vous est affecté pour le moment.',
              icone: Icons.event_busy_outlined,
            )
          else if (cours.isEmpty)
            EtatVide(
              message: enParite
                  ? 'Aucun cours ne vous est affecté sur les semestres '
                        '$libelleParite de $_anneeCourante.'
                  : 'Aucun cours ne vous est affecté pour ce semestre.',
              icone: Icons.menu_book_outlined,
            )
          else
            Column(
              children: [
                for (final element in cours) ...[
                  _CarteCours(cours: element, afficherSemestre: enParite),
                  const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CarteCours extends StatelessWidget {
  final Map<String, dynamic> cours;
  final bool afficherSemestre;

  const _CarteCours({required this.cours, this.afficherSemestre = false});

  @override
  Widget build(BuildContext context) {
    final groupes = ((cours['groupes'] as List?) ?? [])
        .map((g) => '${(g as Map)['nom'] ?? ''}')
        .where((nom) => nom.isNotEmpty)
        .toList();
    final etudiants = ((cours['etudiants'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cmCommun = cours['cm_commun'] == true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppCouleurs.bleu.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.menu_book_outlined,
              color: AppCouleurs.bleu,
            ),
          ),
          title: Text(
            '${cours['ecue_code']} — ${cours['ecue_nom']}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (afficherSemestre &&
                    '${cours['semestre_nom'] ?? ''}'.isNotEmpty)
                  Pastille(
                    '${cours['semestre_nom']} · ${cours['semestre_annee']}',
                    couleur: AppCouleurs.bleu,
                  ),
                if ('${cours['ue_code'] ?? ''}'.isNotEmpty)
                  Text(
                    'UE ${cours['ue_code']} · ${cours['ue_nom']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppCouleurs.texteDoux,
                    ),
                  ),
                if ('${cours['niveau_nom'] ?? ''}'.isNotEmpty)
                  Pastille(
                    '${cours['niveau_nom']} · ${cours['filiere_code']}',
                    couleur: AppCouleurs.violet,
                  ),
                Pastille(
                  '${cours['nb_etudiants'] ?? 0} étudiant(s)',
                  couleur: AppCouleurs.teal,
                ),
                if (cmCommun)
                  const Pastille('CM commun', couleur: AppCouleurs.ambre)
                else if (groupes.isNotEmpty)
                  Pastille('Groupes : ${groupes.join(', ')}'),
                Pastille(
                  'CM ${cours['heures_cm'] ?? 0} h · TD ${cours['heures_td'] ?? 0} h · TP ${cours['heures_tp'] ?? 0} h',
                  couleur: AppCouleurs.texteDoux,
                ),
              ],
            ),
          ),
          children: [
            const Divider(height: 18),
            if (etudiants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Aucun étudiant inscrit à ce cours pour ce semestre.',
                  style: TextStyle(color: AppCouleurs.texteDoux),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 38,
                    dataRowMaxHeight: 44,
                    columnSpacing: 28,
                    columns: const [
                      DataColumn(label: Text('Matricule')),
                      DataColumn(label: Text('Nom et prénom')),
                      DataColumn(label: Text('Groupe')),
                      DataColumn(label: Text('Statut')),
                    ],
                    rows: [
                      for (final etudiant in etudiants)
                        DataRow(
                          cells: [
                            DataCell(Text('${etudiant['matricule'] ?? ''}')),
                            DataCell(
                              Text(
                                '${etudiant['nom_complet'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            DataCell(Text('${etudiant['groupe_nom'] ?? '—'}')),
                            DataCell(
                              Pastille(
                                '${etudiant['statut'] ?? ''}',
                                couleur: _couleurStatut(
                                  '${etudiant['statut'] ?? ''}',
                                ),
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
    );
  }
}

Color _couleurStatut(String statut) {
  switch (statut.toLowerCase()) {
    case 'inscrit':
    case 'redoublant':
      return AppCouleurs.bleu;
    case 'admis':
    case 'validé':
      return AppCouleurs.vert;
    case 'abandon':
    case 'exclu':
      return AppCouleurs.rouge;
    default:
      return AppCouleurs.violet;
  }
}
