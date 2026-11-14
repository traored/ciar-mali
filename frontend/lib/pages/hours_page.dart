import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class HoursPage extends StatefulWidget {
  const HoursPage({super.key});

  @override
  State<HoursPage> createState() => _HoursPageState();
}

class _HoursPageState extends State<HoursPage> {
  Map<String, dynamic>? _donnees;
  bool _chargement = true;
  String? _erreur;
  bool _initialise = false;
  String _recherche = '';
  int? _enseignantFiltre;
  bool _exportEnCours = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialise) {
      _initialise = true;
      _charger();
    }
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    if (app.semestreId == null) {
      setState(() => _chargement = false);
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/heures', {'semestre_id': app.semestreId});
      if (mounted) setState(() => _donnees = donnees as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  List<Map<String, dynamic>> get _lignes {
    final lignes = (_donnees?['lignes'] as List?) ?? [];
    return lignes
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((ligne) {
          if (_enseignantFiltre != null && ligne['enseignant_id'] != _enseignantFiltre) {
            return false;
          }
          if (_recherche.trim().isEmpty) return true;
          final cible = _recherche.toLowerCase();
          return '${ligne['nom']} ${ligne['email']} ${ligne['departement']}'
                  .toLowerCase()
                  .contains(cible) ||
              (ligne['ecues'] as List? ?? []).any(
                (e) => '${e['code']} ${e['nom']}'.toLowerCase().contains(cible),
              );
        })
        .toList();
  }

  Future<void> _exporter({required bool pdf}) async {
    final app = context.read<AppState>();
    if (app.semestreId == null) return;
    setState(() => _exportEnCours = true);
    try {
      if (pdf) {
        final octets = await app.api.octets('/export/heures', {'semestre_id': app.semestreId});
        telechargerOctets(
          octets,
          'heures_enseignants_semestre_${app.semestreId}.pdf',
          'application/pdf',
        );
      } else {
        final octets = await app.api.octets('/export/heures.csv', {'semestre_id': app.semestreId});
        telechargerOctets(
          octets,
          'heures_enseignants_semestre_${app.semestreId}.csv',
          'text/csv',
        );
      }
      if (mounted) afficherMessage(context, pdf ? 'PDF téléchargé' : 'CSV téléchargé');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
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
            titre: 'Heures des enseignants',
            sousTitre: app.estEnseignant
                ? 'Votre charge horaire et le détail de vos interventions.'
                : 'Heures planifiées, heures effectuées et marge par enseignant.',
            actions: [
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
              OutlinedButton.icon(
                onPressed: _exportEnCours ? null : () => _exporter(pdf: false),
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: const Text('CSV'),
              ),
              ElevatedButton.icon(
                onPressed: _exportEnCours ? null : () => _exporter(pdf: true),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Exporter en PDF'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 90),
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
          else if (_donnees == null)
            const CarteSection(
              child: EtatVide(
                message: 'Aucun semestre sélectionné.',
                icone: Icons.event_busy_outlined,
              ),
            )
          else
            _contenu(app),
        ],
      ),
    );
  }

  Widget _contenu(AppState app) {
    final totaux = Map<String, dynamic>.from((_donnees!['totaux'] as Map?) ?? {});
    final lignes = _lignes;
    final totalPlanifiees = (totaux['planifiees'] as num?)?.toDouble() ?? 0;
    final totalEffectuees = (totaux['effectuees'] as num?)?.toDouble() ?? 0;
    final reste = (totaux['reste_a_faire'] as num?)?.toDouble() ?? 0;
    final taux = (totaux['taux'] as num?)?.toDouble() ?? 0;

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
                libelle: 'Heures planifiées',
                valeur: formaterHeures(totalPlanifiees),
                detail: '${totaux['enseignants'] ?? lignes.length} enseignant(s)',
                icone: Icons.schedule_outlined,
                couleur: AppCouleurs.bleu,
              ),
              CarteIndicateur(
                libelle: 'Heures effectuées',
                valeur: formaterHeures(totalEffectuees),
                detail: '${taux.toStringAsFixed(1).replaceAll('.', ',')} % de réalisation',
                icone: Icons.task_alt_outlined,
                couleur: AppCouleurs.vert,
              ),
              CarteIndicateur(
                libelle: 'Reste à effectuer',
                valeur: formaterHeures(reste),
                detail: 'Sur les séances planifiées',
                icone: Icons.pending_actions_outlined,
                couleur: AppCouleurs.ambre,
              ),
              CarteIndicateur(
                libelle: 'Taux global',
                valeur: '${taux.toStringAsFixed(1).replaceAll('.', ',')} %',
                detail: 'Progression du semestre',
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
          titre: 'Suivi par enseignant',
          sousTitre:
              'Les heures effectuées correspondent aux séances marquées « effectuée ». Touchez une ligne pour le détail par ECUE.',
          action: Pastille('${lignes.length} ligne${lignes.length > 1 ? 's' : ''}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: LayoutBuilder(
                  builder: (context, contraintes) {
                    final champ = TextField(
                      onChanged: (v) => setState(() => _recherche = v),
                      decoration: const InputDecoration(
                        hintText: 'Rechercher un enseignant ou un ECUE…',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                    );
                    final filtre = DropdownButtonFormField<int?>(
                      initialValue: _enseignantFiltre,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, labelText: 'Enseignant'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Tous')),
                        for (final ligne in ((_donnees!['lignes'] as List?) ?? []))
                          DropdownMenuItem<int?>(
                            value: ligne['enseignant_id'] as int,
                            child: Text('${ligne['nom']}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _enseignantFiltre = v),
                    );
                    if (contraintes.maxWidth < 640) {
                      return Column(
                        children: [
                          champ,
                          const SizedBox(height: 10),
                          filtre,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 3, child: champ),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: filtre),
                      ],
                    );
                  },
                ),
              ),
              if (lignes.isEmpty)
                const EtatVide(
                  message: 'Aucune heure enregistrée pour ces critères.',
                  icone: Icons.timer_off_outlined,
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    horizontalMargin: 4,
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('ENSEIGNANT')),
                      DataColumn(label: Text('DÉPARTEMENT')),
                      DataColumn(label: Text('MAX'), numeric: true),
                      DataColumn(label: Text('PLANIFIÉES'), numeric: true),
                      DataColumn(label: Text('EFFECTUÉES'), numeric: true),
                      DataColumn(label: Text('RESTE'), numeric: true),
                      DataColumn(label: Text('PROGRESSION')),
                      DataColumn(label: Text('DÉTAIL')),
                    ],
                    rows: [
                      for (final ligne in lignes)
                        DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 200,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${ligne['nom']}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ('${ligne['email']}'.isNotEmpty)
                                      Text(
                                        '${ligne['email']}',
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
                            DataCell(Text('${ligne['departement'] ?? '—'}')),
                            DataCell(Text('${ligne['heures_max']} h')),
                            DataCell(Text(formaterHeures((ligne['planifiees'] as num?) ?? 0))),
                            DataCell(Text(formaterHeures((ligne['effectuees'] as num?) ?? 0))),
                            DataCell(Text(formaterHeures((ligne['reste_a_faire'] as num?) ?? 0))),
                            DataCell(
                              SizedBox(
                                width: 150,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: BarreProgression(
                                        valeur: ((ligne['taux'] as num?) ?? 0) / 100,
                                        couleur: _couleurTaux(((ligne['taux'] as num?) ?? 0).toDouble()),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${((ligne['taux'] as num?) ?? 0).toStringAsFixed(0)} %',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'Voir le détail',
                                icon: const Icon(Icons.visibility_outlined, size: 18, color: AppCouleurs.bleu),
                                onPressed: () => _ouvrirDetail(ligne),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: AppCouleurs.texteDoux),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Marge = volume maximum autorisé moins les heures planifiées. '
                      'Une marge négative signale une surcharge.',
                      style: TextStyle(fontSize: 11, color: AppCouleurs.texteDoux.withValues(alpha: 0.95)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _couleurTaux(double taux) {
    if (taux >= 80) return AppCouleurs.vert;
    if (taux >= 40) return AppCouleurs.ambre;
    if (taux > 0) return AppCouleurs.bleu;
    return const Color(0xFF94A3B8);
  }

  Future<void> _ouvrirDetail(Map<String, dynamic> ligne) async {
    final ecues = ((ligne['ecues'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ligne['nom']}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${ligne['departement'] ?? 'Département non renseigné'} · maximum ${ligne['heures_max']} h',
              style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        content: SizedBox(
          width: 680,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.66),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _miniIndicateur(
                          'Planifiées',
                          formaterHeures((ligne['planifiees'] as num?) ?? 0),
                          AppCouleurs.bleu,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniIndicateur(
                          'Effectuées',
                          formaterHeures((ligne['effectuees'] as num?) ?? 0),
                          AppCouleurs.vert,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniIndicateur(
                          'Marge',
                          formaterHeures((ligne['marge'] as num?) ?? 0),
                          (((ligne['marge'] as num?) ?? 0) < 0) ? AppCouleurs.rouge : AppCouleurs.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (ecues.isEmpty)
                    const EtatVide(
                      message: 'Aucune séance planifiée pour cet enseignant.',
                      icone: Icons.event_busy_outlined,
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 16,
                        horizontalMargin: 0,
                        columns: const [
                          DataColumn(label: Text('ECUE')),
                          DataColumn(label: Text('UE')),
                          DataColumn(label: Text('CM'), numeric: true),
                          DataColumn(label: Text('TD'), numeric: true),
                          DataColumn(label: Text('TP'), numeric: true),
                          DataColumn(label: Text('PLANIFIÉES'), numeric: true),
                          DataColumn(label: Text('EFFECTUÉES'), numeric: true),
                        ],
                        rows: [
                          for (final ecue in ecues)
                            DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 220,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${ecue['code']}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                        ),
                                        Text(
                                          '${ecue['nom']}',
                                          style: const TextStyle(fontSize: 10.5, color: AppCouleurs.texteDoux),
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
                                DataCell(Text(formaterHeures((ecue['planifiees'] as num?) ?? 0))),
                                DataCell(
                                  Pastille(
                                    formaterHeures((ecue['effectuees'] as num?) ?? 0),
                                    couleur: AppCouleurs.vert,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Widget _miniIndicateur(String libelle, String valeur, Color couleur) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: couleur.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valeur,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: couleur),
          ),
          const SizedBox(height: 2),
          Text(libelle, style: const TextStyle(fontSize: 11, color: AppCouleurs.texteDoux)),
        ],
      ),
    );
  }
}
