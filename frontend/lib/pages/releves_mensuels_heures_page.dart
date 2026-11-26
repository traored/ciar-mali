import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class RelevesMensuelsHeuresPage extends StatefulWidget {
  const RelevesMensuelsHeuresPage({super.key});

  @override
  State<RelevesMensuelsHeuresPage> createState() =>
      _RelevesMensuelsHeuresPageState();
}

class _RelevesMensuelsHeuresPageState
    extends State<RelevesMensuelsHeuresPage> {
  bool _chargement = true;
  bool _exportEnCours = false;
  String? _erreur;
  Map<String, dynamic>? _donnees;
  late int _mois;
  late int _annee;

  static const _moisNoms = <int, String>{
    1: 'Janvier',
    2: 'Février',
    3: 'Mars',
    4: 'Avril',
    5: 'Mai',
    6: 'Juin',
    7: 'Juillet',
    8: 'Août',
    9: 'Septembre',
    10: 'Octobre',
    11: 'Novembre',
    12: 'Décembre',
  };

  @override
  void initState() {
    super.initState();
    final maintenant = DateTime.now();
    _mois = maintenant.month;
    _annee = maintenant.year;
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final app = context.read<AppState>();
      final donnees = await app.api.get('/heures/mensuel', {
        'mois': _mois,
        'annee': _annee,
      });
      if (!mounted) return;
      setState(() => _donnees = Map<String, dynamic>.from(donnees as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  List<Map<String, dynamic>> get _lignes {
    final lignes = (_donnees?['lignes'] as List?) ?? const [];
    return lignes
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic>? get _maLigne {
    final lignes = _lignes;
    if (lignes.isEmpty) return null;
    return lignes.first;
  }

  Future<void> _exporter() async {
    final app = context.read<AppState>();
    setState(() => _exportEnCours = true);
    try {
      final octets = await app.api.octets('/heures/mensuel/export', {
        'mois': _mois,
        'annee': _annee,
      });
      telechargerOctets(
        octets,
        'releve_mensuel_heures_${_annee}_${_mois.toString().padLeft(2, '0')}.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted) afficherMessage(context, 'Export téléchargé.');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  void _voirDetail(Map<String, dynamic> ligne) {
    final ecues = ((ligne['ecues'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Charge mensuelle - ${ligne['nom_complet'] ?? ''}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _carteDetail('Heures totales',
                        formaterHeures((ligne['planifiees'] as num?) ?? 0), AppCouleurs.bleu),
                    _carteDetail('Heures effectuées',
                        formaterHeures((ligne['effectuees'] as num?) ?? 0), AppCouleurs.vert),
                    _carteDetail('Heures restantes',
                        formaterHeures((ligne['reste_a_faire'] as num?) ?? 0), AppCouleurs.ambre),
                  ],
                ),
                const SizedBox(height: 16),
                if (ecues.isEmpty)
                  const Text('Aucune séance pour ce mois.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(label: Text('ECUE')),
                        DataColumn(label: Text('TOTAL'), numeric: true),
                        DataColumn(label: Text('EFFECTUÉES'), numeric: true),
                        DataColumn(label: Text('RESTANTES'), numeric: true),
                      ],
                      rows: [
                        for (final ecue in ecues)
                          DataRow(cells: [
                            DataCell(SizedBox(
                              width: 260,
                              child: Text(
                                '${ecue['code'] ?? ''} - ${ecue['nom'] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                            DataCell(Text(formaterHeures((ecue['planifiees'] as num?) ?? 0))),
                            DataCell(Text(formaterHeures((ecue['effectuees'] as num?) ?? 0))),
                            DataCell(Text(formaterHeures((ecue['restantes'] as num?) ?? 0))),
                          ]),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _carteDetail(String titre, String valeur, Color couleur) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: couleur.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux)),
          const SizedBox(height: 4),
          Text(valeur, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: couleur)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final estAdmin = app.peutModifier;
    final annees = [for (var a = DateTime.now().year - 3; a <= DateTime.now().year + 2; a++) a];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Relevés mensuels des heures',
            sousTitre: estAdmin
                ? 'Charges mensuelles des enseignants par mois et par année.'
                : 'Votre relevé mensuel d\'heures : totales, effectuées et restantes.',
            actions: [
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
              if (estAdmin)
                ElevatedButton.icon(
                  onPressed: _exportEnCours ? null : _exporter,
                  icon: _exportEnCours
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Exporter'),
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
                  width: 180,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(_mois),
                    initialValue: _mois,
                    decoration: const InputDecoration(labelText: 'Mois', isDense: true),
                    items: [
                      for (final e in _moisNoms.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _mois = v);
                      _charger();
                    },
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(_annee),
                    initialValue: _annee,
                    decoration: const InputDecoration(labelText: 'Année', isDense: true),
                    items: [
                      for (final a in annees)
                        DropdownMenuItem(value: a, child: Text('$a')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _annee = v);
                      _charger();
                    },
                  ),
                ),
                Pastille('${_moisNoms[_mois]} $_annee', couleur: AppCouleurs.bleu),
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
                action: ElevatedButton(onPressed: _charger, child: const Text('Réessayer')),
              ),
            )
          else if (estAdmin)
            _vueAdmin()
          else
            _vueEnseignant(),
        ],
      ),
    );
  }

  Widget _vueEnseignant() {
    final ligne = _maLigne;
    if (ligne == null) {
      return const CarteSection(
        child: EtatVide(message: 'Aucune donnée disponible pour ce mois.', icone: Icons.event_busy_outlined),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, contraintes) {
            final largeur = contraintes.maxWidth;
            final colonnes = largeur > 900 ? 3 : (largeur > 560 ? 2 : 1);
            const espace = 14.0;
            final taille = (largeur - espace * (colonnes - 1)) / colonnes;
            final cartes = [
              CarteIndicateur(
                libelle: 'Heures totales',
                valeur: formaterHeures((ligne['planifiees'] as num?) ?? 0),
                icone: Icons.hourglass_top_outlined,
                couleur: AppCouleurs.bleu,
              ),
              CarteIndicateur(
                libelle: 'Heures effectuées',
                valeur: formaterHeures((ligne['effectuees'] as num?) ?? 0),
                icone: Icons.task_alt_outlined,
                couleur: AppCouleurs.vert,
              ),
              CarteIndicateur(
                libelle: 'Heures restantes',
                valeur: formaterHeures((ligne['reste_a_faire'] as num?) ?? 0),
                icone: Icons.pending_actions_outlined,
                couleur: AppCouleurs.ambre,
              ),
            ];
            return Wrap(
              spacing: espace,
              runSpacing: espace,
              children: [for (final carte in cartes) SizedBox(width: taille, child: carte)],
            );
          },
        ),
        const SizedBox(height: 16),
        CarteSection(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Détail mensuel de ${ligne['nom_complet'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _voirDetail(ligne),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Voir détail'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vueAdmin() {
    final lignes = _lignes;
    if (lignes.isEmpty) {
      return const CarteSection(
        child: EtatVide(message: 'Aucun enseignant trouvé.', icone: Icons.people_outline),
      );
    }
    return CarteSection(
      padding: const EdgeInsets.only(bottom: 8),
      titre: 'Enseignants',
      sousTitre: 'Charges mensuelles pour ${_moisNoms[_mois]} $_annee.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          horizontalMargin: 4,
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('MATRICULE')),
            DataColumn(label: Text('PRÉNOM')),
            DataColumn(label: Text('NOM')),
            DataColumn(label: Text('HEURES TOTALES'), numeric: true),
            DataColumn(label: Text('EFFECTUÉES'), numeric: true),
            DataColumn(label: Text('RESTANTES'), numeric: true),
            DataColumn(label: Text('DÉTAIL')),
          ],
          rows: [
            for (final ligne in lignes)
              DataRow(cells: [
                DataCell(Text('${ligne['matricule'] ?? '-'}')),
                DataCell(Text('${ligne['prenom'] ?? '-'}')),
                DataCell(Text('${ligne['nom'] ?? '-'}')),
                DataCell(Text(formaterHeures((ligne['planifiees'] as num?) ?? 0))),
                DataCell(Text(formaterHeures((ligne['effectuees'] as num?) ?? 0))),
                DataCell(Text(formaterHeures((ligne['reste_a_faire'] as num?) ?? 0))),
                DataCell(IconButton(
                  tooltip: 'Voir détail',
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: () => _voirDetail(ligne),
                )),
              ]),
          ],
        ),
      ),
    );
  }
}
