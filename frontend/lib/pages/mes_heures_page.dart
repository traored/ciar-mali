import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Espace enseignant : suivi de la charge horaire personnelle
/// (heures totales, effectuées et restantes) pour un semestre.
class MesHeuresPage extends StatefulWidget {
  const MesHeuresPage({super.key});

  @override
  State<MesHeuresPage> createState() => _MesHeuresPageState();
}

class _MesHeuresPageState extends State<MesHeuresPage> {
  bool _initialise = false;
  bool _chargement = true;
  bool _auto = true;
  String? _erreur;
  int? _semestreId;
  List<int> _candidats = [];
  Map<String, dynamic>? _donnees;
  final _scrollDetail = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    _initialise = true;
    final app = context.read<AppState>();
    final candidats = <int>[];
    void ajouter(int? id) {
      if (id != null && !candidats.contains(id)) candidats.add(id);
    }

    ajouter(_semestreCourant(app));
    ajouter(app.semestreId);
    for (final semestre in app.semestres) {
      ajouter(semestre['id'] as int?);
    }
    _candidats = candidats;
    _semestreId = app.semestreId ??
        _semestreCourant(app) ??
        (candidats.isEmpty ? null : candidats.first);
    _charger();
  }

  @override
  void dispose() {
    _scrollDetail.dispose();
    super.dispose();
  }

  /// Semestre courant de l'année universitaire courante (S1 de septembre à
  /// janvier, S2 de février à août).
  int? _semestreCourant(AppState app) {
    final maintenant = DateTime.now();
    final debut = maintenant.month >= 9 ? maintenant.year : maintenant.year - 1;
    final annee = '$debut-${debut + 1}';
    final numero = (maintenant.month >= 9 || maintenant.month <= 1) ? 1 : 2;
    final motif = RegExp('semestre\\s*$numero\\b', caseSensitive: false);
    for (final semestre in app.semestres) {
      if ('${semestre['annee'] ?? ''}' != annee) continue;
      if (motif.hasMatch('${semestre['nom'] ?? ''}')) {
        return semestre['id'] as int?;
      }
    }
    return null;
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    final aEssayer = _auto && _candidats.isNotEmpty
        ? _candidats
        : [?_semestreId];
    if (aEssayer.isEmpty) {
      setState(() => _chargement = false);
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      Map<String, dynamic>? meilleur;
      int? meilleurId;
      var meilleuresHeures = -1.0;
      for (final semestreId in aEssayer) {
        final donnees = await app.api.get('/heures', {
          'semestre_id': semestreId,
        }) as Map<String, dynamic>;
        if (!mounted) return;
        final lignes = (donnees['lignes'] as List?) ?? const [];
        final planifiees = lignes.fold<double>(
          0,
          (total, element) =>
              total +
              (((element as Map)['planifiees'] as num?)?.toDouble() ?? 0),
        );
        if (planifiees > meilleuresHeures) {
          meilleur = donnees;
          meilleurId = semestreId;
          meilleuresHeures = planifiees;
        }
        // Le semestre actif de l'application est prioritaire dès qu'il
        // contient des heures planifiées.
        if (_auto && semestreId == app.semestreId && planifiees > 0) break;
      }
      if (!mounted) return;
      setState(() {
        if (meilleurId != null) _semestreId = meilleurId;
        _donnees = meilleur;
        _auto = false;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Map<String, dynamic>? get _ligne {
    final lignes = (_donnees?['lignes'] as List?) ?? const [];
    for (final element in lignes) {
      if (element is Map) return Map<String, dynamic>.from(element);
    }
    return null;
  }

  List<Map<String, dynamic>> get _ecues {
    final ecues = (_ligne?['ecues'] as List?) ?? const [];
    return ecues
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  double _heures(Map<String, dynamic> ligne, String cle) =>
      (ligne[cle] as num?)?.toDouble() ?? 0;

  double _totales(Map<String, dynamic> ecue) {
    final totales = (ecue['totales'] as num?)?.toDouble();
    return totales ?? _heures(ecue, 'planifiees');
  }

  double _restantes(Map<String, dynamic> ecue) {
    final restantes = (ecue['restantes'] as num?)?.toDouble();
    if (restantes != null) return restantes;
    return (_heures(ecue, 'planifiees') - _heures(ecue, 'effectuees'))
        .clamp(0, double.infinity)
        .toDouble();
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
            titre: 'Suivi de mes heures',
            sousTitre:
                'Vos heures totales, effectuées et restantes pour le semestre sélectionné.',
            actions: [
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
                  child: DropdownButtonFormField<int>(
                    key: ValueKey<int?>(_semestreId),
                    initialValue: app.semestres.any((s) => s['id'] == _semestreId)
                        ? _semestreId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Semestre',
                      isDense: true,
                    ),
                    items: [
                      for (final semestre in app.semestres)
                        DropdownMenuItem(
                          value: semestre['id'] as int,
                          child: Text(
                            '${semestre['nom']} · ${semestre['annee']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: (valeur) {
                      if (valeur == null || valeur == _semestreId) return;
                      setState(() {
                        _semestreId = valeur;
                        _donnees = null;
                        _auto = false;
                      });
                      _charger();
                    },
                  ),
                ),
                if (_ligne != null)
                  Pastille(
                    '${_ligne!['nom'] ?? ''}',
                    couleur: AppCouleurs.bleu,
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
              child: EtatVide(
                message: _erreur!,
                icone: Icons.cloud_off_outlined,
                action: ElevatedButton(
                  onPressed: _charger,
                  child: const Text('Réessayer'),
                ),
              ),
            )
          else if (_ligne == null)
            const CarteSection(
              child: EtatVide(
                message: 'Aucune heure enregistrée pour ce semestre.',
                icone: Icons.timer_off_outlined,
              ),
            )
          else
            _contenu(),
        ],
      ),
    );
  }

  Widget _contenu() {
    final ligne = _ligne!;
    final planifiees = (ligne['planifiees'] as num?)?.toDouble() ?? 0;
    final effectuees = (ligne['effectuees'] as num?)?.toDouble() ?? 0;
    final total = planifiees;
    final reste = (planifiees - effectuees).clamp(0, double.infinity).toDouble();
    final taux = total > 0 ? effectuees / total * 100 : 0.0;
    final maximum = (ligne['heures_max'] as num?)?.toDouble() ?? 0;
    final marge = (ligne['marge'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, contraintes) {
            final largeur = contraintes.maxWidth;
            final colonnes = largeur > 1100 ? 4 : (largeur > 760 ? 2 : 1);
            const espace = 14.0;
            final taille = (largeur - espace * (colonnes - 1)) / colonnes;
            final cartes = [
              CarteIndicateur(
                libelle: 'Heures totales',
                valeur: formaterHeures(total),
                detail: 'Volume planifié · maximum ${formaterHeures(maximum)}',
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
                valeur: formaterHeures(reste),
                detail: 'Reste à effectuer',
                icone: Icons.pending_actions_outlined,
                couleur: AppCouleurs.ambre,
              ),
              CarteIndicateur(
                libelle: 'Taux de réalisation',
                valeur: '${taux.toStringAsFixed(1).replaceAll('.', ',')} %',
                detail: 'Progression de votre charge',
                icone: Icons.trending_up_outlined,
                couleur: AppCouleurs.violet,
              ),
            ];
            return Wrap(
              spacing: espace,
              runSpacing: espace,
              children: [
                for (final carte in cartes) SizedBox(width: taille, child: carte),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        CarteSection(
          padding: const EdgeInsets.only(bottom: 8),
          titre: 'Détail par ECUE',
          sousTitre:
              'Total ${formaterHeures(total)} · effectuées '
              '${formaterHeures(effectuees)} · restantes '
              '${formaterHeures(reste)} · marge sur le maximum '
              '${formaterHeures(marge)}.',
          action: Pastille('${_ecues.length} ECUE'),
          child: _ecues.isEmpty
              ? const EtatVide(
                  message: 'Aucune séance planifiée pour ce semestre.',
                  icone: Icons.event_busy_outlined,
                )
              : Scrollbar(
                  controller: _scrollDetail,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollDetail,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      horizontalMargin: 4,
                      showCheckboxColumn: false,
                      columns: const [
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
                                  width: 240,
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
                              DataCell(Text(formaterHeures((ecue['cm'] as num?) ?? 0))),
                              DataCell(Text(formaterHeures((ecue['td'] as num?) ?? 0))),
                              DataCell(Text(formaterHeures((ecue['tp'] as num?) ?? 0))),
                              DataCell(Text(formaterHeures(_totales(ecue)))),
                              DataCell(
                                Pastille(
                                  formaterHeures((ecue['effectuees'] as num?) ?? 0),
                                  couleur: AppCouleurs.vert,
                                ),
                              ),
                              DataCell(
                                Pastille(
                                  formaterHeures(_restantes(ecue)),
                                  couleur: AppCouleurs.ambre,
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
}
