import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Espace enseignant : totaux de tous les ECUE, tous semestres confondus.
class SuiviGlobalPage extends StatefulWidget {
  const SuiviGlobalPage({super.key});

  @override
  State<SuiviGlobalPage> createState() => _SuiviGlobalPageState();
}

class _SuiviGlobalPageState extends State<SuiviGlobalPage> {
  bool _initialise = false;
  bool _chargement = true;
  String? _erreur;
  Map<String, dynamic>? _donnees;
  final _scrollEcues = ScrollController();
  final _scrollSemestres = ScrollController();
  final _scrollParites = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    _initialise = true;
    _charger();
  }

  @override
  void dispose() {
    _scrollEcues.dispose();
    _scrollSemestres.dispose();
    _scrollParites.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees =
          await app.api.get('/heures/global') as Map<String, dynamic>;
      if (mounted) setState(() => _donnees = donnees);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Map<String, dynamic> get _totaux =>
      (_donnees?['totaux'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> get _ecues {
    final ecues = (_donnees?['ecues'] as List?) ?? const [];
    return ecues
        .whereType<Map>()
        .map((element) => Map<String, dynamic>.from(element))
        .toList();
  }

  List<Map<String, dynamic>> get _semestres {
    final semestres = (_donnees?['semestres'] as List?) ?? const [];
    return semestres
        .whereType<Map>()
        .map((element) => Map<String, dynamic>.from(element))
        .toList();
  }

  /// Répartition des heures par année universitaire, semestres impairs et
  /// pairs (1, 3, 5 / 2, 4, 6).
  List<Map<String, dynamic>> get _parites {
    final parites = (_donnees?['parites'] as List?) ?? const [];
    return parites
        .whereType<Map>()
        .map((element) => Map<String, dynamic>.from(element))
        .toList();
  }

  double _valeur(Map<String, dynamic> ligne, String cle) =>
      (ligne[cle] as num?)?.toDouble() ?? 0;

  String _semestreLibelle(Map<String, dynamic> ligne) {
    final nom = '${ligne['semestre'] ?? ''}'.trim();
    final annee = '${ligne['annee'] ?? ''}'.trim();
    if (nom.isEmpty) return annee.isEmpty ? '—' : annee;
    return annee.isEmpty ? nom : '$nom · $annee';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final enseignant = (_donnees?['enseignant'] as Map?)
        ?.cast<String, dynamic>();
    final nom = '${enseignant?['nom'] ?? app.utilisateur?.nomComplet ?? ''}'
        .trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Suivi global',
            sousTitre: 'Le total de vos heures sur tous vos ECUE, toutes années confondues.',
            actions: [
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_erreur != null)
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
          else if (_ecues.isEmpty)
            const CarteSection(
              child: EtatVide(
                message: 'Aucun ECUE ne vous est affecté pour le moment.',
                icone: Icons.timer_off_outlined,
              ),
            )
          else
            _contenu(nom),
        ],
      ),
    );
  }

  Widget _contenu(String nom) {
    final totales = _valeur(_totaux, 'planifiees');
    final effectuees = _valeur(_totaux, 'effectuees');
    final restantes = _valeur(_totaux, 'restantes');
    final taux = _valeur(_totaux, 'taux');
    final maximum = (_donnees?['enseignant'] as Map?)?['heures_max'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Pastille(nom, couleur: AppCouleurs.bleu),
          ),
        LayoutBuilder(
          builder: (context, contraintes) {
            final largeur = contraintes.maxWidth;
            final colonnes = largeur > 1100 ? 4 : (largeur > 760 ? 2 : 1);
            const espace = 14.0;
            final taille = (largeur - espace * (colonnes - 1)) / colonnes;
            final cartes = [
              CarteIndicateur(
                libelle: 'Heures totales',
                valeur: formaterHeures(totales),
                detail:
                    '${_ecues.length} ECUE'
                    '${maximum is num ? ' · maximum ${formaterHeures(maximum)}' : ''}',
                icone: Icons.hourglass_top_outlined,
                couleur: AppCouleurs.bleu,
              ),
              CarteIndicateur(
                libelle: 'Heures effectuées',
                valeur: formaterHeures(effectuees),
                detail: 'Séances marquées « effectuée »',
                icone: Icons.task_alt_outlined,
                couleur: AppCouleurs.vert,
              ),
              CarteIndicateur(
                libelle: 'Heures restantes',
                valeur: formaterHeures(restantes),
                detail: 'Reste à effectuer sur tous vos ECUE',
                icone: Icons.pending_actions_outlined,
                couleur: AppCouleurs.ambre,
              ),
              CarteIndicateur(
                libelle: 'Taux de réalisation',
                valeur: '${taux.toStringAsFixed(1).replaceAll('.', ',')} %',
                detail: 'Progression globale',
                icone: Icons.trending_up_outlined,
                couleur: AppCouleurs.violet,
              ),
            ];
            return Wrap(
              spacing: espace,
              runSpacing: espace,
              children: [
                for (final carte in cartes)
                  SizedBox(width: taille, child: carte),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        CarteSection(
          padding: const EdgeInsets.only(bottom: 8),
          titre: 'Détail par ECUE',
          sousTitre:
              'Total ${formaterHeures(totales)} · effectuées '
              '${formaterHeures(effectuees)} · restantes '
              '${formaterHeures(restantes)}.',
          action: Pastille('${_ecues.length} ECUE'),
          child: _tableEcues(),
        ),
        const SizedBox(height: 18),
        CarteSection(
          padding: const EdgeInsets.only(bottom: 8),
          titre: 'Répartition par semestre',
          sousTitre: 'Vos heures semestre par semestre.',
          action: Pastille('${_semestres.length} semestre(s)'),
          child: _tableSemestres(),
        ),
        const SizedBox(height: 18),
        CarteSection(
          padding: const EdgeInsets.only(bottom: 8),
          titre: 'Répartition impairs / pairs',
          sousTitre:
              'Vos heures par année, semestres impairs (1, 3, 5) et pairs '
              '(2, 4, 6).',
          action: Pastille('${_parites.length} année(s)'),
          child: _tableParites(),
        ),
      ],
    );
  }

  Widget _tableEcues() {
    return Scrollbar(
      controller: _scrollEcues,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollEcues,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          horizontalMargin: 4,
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('SEMESTRE')),
            DataColumn(label: Text('ECUE')),
            DataColumn(label: Text('UE')),
            DataColumn(label: Text('CM'), numeric: true),
            DataColumn(label: Text('TD'), numeric: true),
            DataColumn(label: Text('TP'), numeric: true),
            DataColumn(label: Text('TOTALES'), numeric: true),
            DataColumn(label: Text('EFFECTUÉES'), numeric: true),
            DataColumn(label: Text('RESTANTES'), numeric: true),
          ],
          rows: [
            for (final ecue in _ecues)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 190,
                      child: Text(
                        _semestreLibelle(ecue),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${ecue['code'] ?? '—'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            '${ecue['nom'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppCouleurs.texteDoux,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(Text('${ecue['ue'] ?? '—'}')),
                  DataCell(Text(formaterHeures(_valeur(ecue, 'cm')))),
                  DataCell(Text(formaterHeures(_valeur(ecue, 'td')))),
                  DataCell(Text(formaterHeures(_valeur(ecue, 'tp')))),
                  DataCell(Text(formaterHeures(_valeur(ecue, 'totales')))),
                  DataCell(
                    Pastille(
                      formaterHeures(_valeur(ecue, 'effectuees')),
                      couleur: AppCouleurs.vert,
                    ),
                  ),
                  DataCell(
                    Pastille(
                      formaterHeures(_valeur(ecue, 'restantes')),
                      couleur: AppCouleurs.ambre,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _tableSemestres() {
    if (_semestres.isEmpty) {
      return const EtatVide(
        message: 'Aucune séance planifiée.',
        icone: Icons.event_busy_outlined,
      );
    }
    return Scrollbar(
      controller: _scrollSemestres,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollSemestres,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          horizontalMargin: 4,
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('SEMESTRE')),
            DataColumn(label: Text('ANNÉE')),
            DataColumn(label: Text('TOTALES'), numeric: true),
            DataColumn(label: Text('EFFECTUÉES'), numeric: true),
            DataColumn(label: Text('RESTANTES'), numeric: true),
          ],
          rows: [
            for (final semestre in _semestres)
              DataRow(
                cells: [
                  DataCell(Text('${semestre['nom'] ?? '—'}')),
                  DataCell(Text('${semestre['annee'] ?? '—'}')),
                  DataCell(
                    Text(formaterHeures(_valeur(semestre, 'planifiees'))),
                  ),
                  DataCell(
                    Pastille(
                      formaterHeures(_valeur(semestre, 'effectuees')),
                      couleur: AppCouleurs.vert,
                    ),
                  ),
                  DataCell(
                    Pastille(
                      formaterHeures(_valeur(semestre, 'restantes')),
                      couleur: AppCouleurs.ambre,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _groupeParite(Map<String, dynamic> entree, String cle) {
    final groupe = entree[cle];
    return groupe is Map
        ? Map<String, dynamic>.from(groupe)
        : const <String, dynamic>{};
  }

  DataRow _ligneParite(Map<String, dynamic> entree, String cle) {
    final groupe = _groupeParite(entree, cle);
    final impairs = cle == 'impairs';
    return DataRow(
      cells: [
        DataCell(Text('${entree['annee'] ?? '—'}')),
        DataCell(
          Pastille(
            impairs ? 'Impairs' : 'Pairs',
            couleur: impairs ? AppCouleurs.bleu : AppCouleurs.violet,
          ),
        ),
        DataCell(Text('${groupe['semestres'] ?? 0}')),
        DataCell(Text(formaterHeures(_valeur(groupe, 'planifiees')))),
        DataCell(
          Pastille(
            formaterHeures(_valeur(groupe, 'effectuees')),
            couleur: AppCouleurs.vert,
          ),
        ),
        DataCell(
          Pastille(
            formaterHeures(_valeur(groupe, 'restantes')),
            couleur: AppCouleurs.ambre,
          ),
        ),
      ],
    );
  }

  Widget _tableParites() {
    if (_parites.isEmpty) {
      return const EtatVide(
        message: 'Aucune séance planifiée.',
        icone: Icons.event_busy_outlined,
      );
    }
    return Scrollbar(
      controller: _scrollParites,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollParites,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          horizontalMargin: 4,
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('ANNÉE')),
            DataColumn(label: Text('PARITÉ')),
            DataColumn(label: Text('SEMESTRES'), numeric: true),
            DataColumn(label: Text('TOTALES'), numeric: true),
            DataColumn(label: Text('EFFECTUÉES'), numeric: true),
            DataColumn(label: Text('RESTANTES'), numeric: true),
          ],
          rows: [
            for (final entree in _parites) ...[
              _ligneParite(entree, 'impairs'),
              _ligneParite(entree, 'pairs'),
            ],
          ],
        ),
      ),
    );
  }
}
