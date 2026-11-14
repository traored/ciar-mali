import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _donnees;
  bool _chargement = true;
  String? _erreur;
  bool _generation = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/tableau-de-bord', {'semestre_id': app.semestreId});
      if (mounted) setState(() => _donnees = donnees as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _generer() async {
    final app = context.read<AppState>();
    final ok = await confirmer(
      context,
      titre: 'Générer l’emploi du temps',
      message:
          'Le générateur va recalculer les séances du semestre sélectionné. Les séances verrouillées sont conservées. Continuer ?',
      action: 'Générer',
      danger: false,
    );
    if (!ok || !mounted) return;
    setState(() => _generation = true);
    try {
      final resultat = await app.api.post('/generer', {
        'semestre_id': app.semestreId,
        'remplacer': true,
      });
      await _charger();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Génération terminée', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${resultat['message']}', style: const TextStyle(fontSize: 13)),
                if ((resultat['non_placees'] as List).isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Points à vérifier :', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final point in resultat['non_placees'] as List)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppCouleurs.ambre),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${point['ecue']} · ${point['groupes']} (${point['type']}) — ${point['raison']}',
                                      style: const TextStyle(fontSize: 12),
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
              ],
            ),
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _generation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final semestre = app.semestreSelectionne;
    return RefreshIndicator(
      onRefresh: _charger,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EntetePage(
              titre: 'Tableau de bord',
              sousTitre: semestre == null
                  ? 'Vue d’ensemble de l’activité académique.'
                  : '${semestre['nom']} · ${semestre['annee']} — ${app.libelleSemaine(app.semaine)}',
              actions: [
                OutlinedButton.icon(
                  onPressed: _charger,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Actualiser'),
                ),
                if (app.peutModifier)
                  ElevatedButton.icon(
                    onPressed: _generation ? null : _generer,
                    icon: _generation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_generation ? 'Génération…' : 'Générer l’emploi du temps'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_chargement)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erreur != null)
              CarteSection(
                child: EtatVide(
                  message: _erreur!,
                  icone: Icons.cloud_off_outlined,
                  action: ElevatedButton(onPressed: _charger, child: const Text('Réessayer')),
                ),
              )
            else if (_donnees != null)
              _contenu(app),
          ],
        ),
      ),
    );
  }

  Widget _contenu(AppState app) {
    final indicateurs = _donnees!['indicateurs'] as Map<String, dynamic>;
    final charge = Map<String, dynamic>.from(_donnees!['charge_jours'] as Map);
    final alertes = _donnees!['alertes'] as List;
    final seances = _donnees!['prochaines_seances'] as List;
    final semaineCourante = _donnees!['semaine_courante'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, contraintes) {
            final largeur = contraintes.maxWidth;
            final colonnes = largeur > 1250 ? 4 : (largeur > 800 ? 3 : (largeur > 520 ? 2 : 1));
            final espace = 14.0;
            final taille = (largeur - espace * (colonnes - 1)) / colonnes;
            final cartes = [
              CarteIndicateur(
                libelle: 'Séances planifiées',
                valeur: '${indicateurs['seances']}',
                detail: 'Semaine $semaineCourante',
                icone: Icons.event_note_outlined,
                couleur: AppCouleurs.bleu,
              ),
              CarteIndicateur(
                libelle: 'Heures planifiées',
                valeur: formaterHeures((indicateurs['heures_planifiees'] as num?) ?? 0),
                detail: 'Toutes semaines confondues',
                icone: Icons.schedule_outlined,
                couleur: AppCouleurs.teal,
              ),
              CarteIndicateur(
                libelle: 'Heures effectuées',
                valeur: formaterHeures((indicateurs['heures_effectuees'] as num?) ?? 0),
                detail: '${indicateurs['taux_realisation']} % de réalisation',
                icone: Icons.task_alt_outlined,
                couleur: AppCouleurs.vert,
              ),
              CarteIndicateur(
                libelle: 'Enseignants actifs',
                valeur: '${indicateurs['enseignants']}',
                detail: '${indicateurs['groupes']} groupes · ${indicateurs['salles']} salles',
                icone: Icons.groups_2_outlined,
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
        LayoutBuilder(
          builder: (context, contraintes) {
            final graphe = CarteSection(
              titre: 'Charge de la semaine',
              sousTitre: 'Heures de cours programmées par jour — ${app.periodeSemaine(semaineCourante)}.',
              child: _grapheCharge(charge),
            );
            final alertesCarte = CarteSection(
              titre: 'Alertes',
              sousTitre: 'Points de vigilance détectés automatiquement.',
              child: alertes.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.verified_outlined, color: AppCouleurs.vert, size: 34),
                            SizedBox(height: 8),
                            Text('Aucune alerte', style: TextStyle(color: AppCouleurs.texteDoux, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final alerte in alertes.take(6))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: AppCouleurs.ambre.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.warning_amber_rounded, size: 17, color: AppCouleurs.ambre),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${alerte['message']}',
                                    style: const TextStyle(fontSize: 12, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            );
            if (contraintes.maxWidth < 900) {
              return Column(
                children: [graphe, const SizedBox(height: 18), alertesCarte],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: graphe),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: alertesCarte),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        CarteSection(
          titre: 'Séances de la semaine $semaineCourante',
          sousTitre: '${app.periodeSemaine(semaineCourante)} — les prochains créneaux programmés.',
          action: TextButton.icon(
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Actualiser'),
          ),
          child: seances.isEmpty
              ? const EtatVide(
                  message: 'Aucune séance programmée pour cette semaine.',
                  icone: Icons.event_busy_outlined,
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 22,
                    horizontalMargin: 4,
                    columns: const [
                      DataColumn(label: Text('JOUR')),
                      DataColumn(label: Text('HORAIRE')),
                      DataColumn(label: Text('ECUE')),
                      DataColumn(label: Text('TYPE')),
                      DataColumn(label: Text('GROUPE(S)')),
                      DataColumn(label: Text('SALLE')),
                      DataColumn(label: Text('ENSEIGNANT')),
                      DataColumn(label: Text('STATUT')),
                    ],
                    rows: [
                      for (final seance in seances)
                        DataRow(
                          cells: [
                            DataCell(Text(_jour(seance['jour'] as int?))),
                            DataCell(Text('${seance['debut']} – ${seance['fin']}')),
                            DataCell(
                              SizedBox(
                                width: 190,
                                child: Text(
                                  '${seance['ecue']} · ${seance['ecue_nom']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Pastille('${seance['type']}', couleur: _couleurType('${seance['type']}'))),
                            DataCell(Text('${seance['groupes']}')),
                            DataCell(Text('${seance['salle'] ?? '—'}')),
                            DataCell(
                              SizedBox(
                                width: 150,
                                child: Text(
                                  '${seance['enseignant']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Pastille(
                                '${seance['statut']}',
                                couleur: _couleurStatut('${seance['statut']}'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _grapheCharge(Map<String, dynamic> charge) {
    final valeurs = [
      for (final jour in ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'])
        (charge[jour] as num?)?.toDouble() ?? 0,
    ];
    final maxi = valeurs.fold<double>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < valeurs.length; i++) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    valeurs[i] == 0 ? '—' : formaterHeures(valeurs[i]),
                    style: const TextStyle(fontSize: 10.5, color: AppCouleurs.texteDoux, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    height: 26 + (125 * valeurs[i] / maxi),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: valeurs[i] == 0
                            ? [const Color(0xFFE2E8F0), const Color(0xFFE2E8F0)]
                            : [AppCouleurs.bleu, const Color(0xFF60A5FA)],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'][i],
                    style: const TextStyle(fontSize: 10.5, color: AppCouleurs.texteDoux, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _jour(int? jour) {
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
    if (jour == null || jour < 0 || jour >= jours.length) return '—';
    return jours[jour];
  }

  Color _couleurType(String type) => switch (type) {
        'CM' => AppCouleurs.bleu,
        'TD' => AppCouleurs.vert,
        'TP' => AppCouleurs.ambre,
        _ => AppCouleurs.texteDoux,
      };

  Color _couleurStatut(String statut) => switch (statut) {
        'effectuee' => AppCouleurs.vert,
        'annulee' => AppCouleurs.rouge,
        _ => AppCouleurs.bleu,
      };
}
