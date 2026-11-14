import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Module 8 — Statistiques : moyennes, taux de réussite et analyse par UE.
class NotesStatistiquesPage extends StatefulWidget {
  const NotesStatistiquesPage({super.key});

  @override
  State<NotesStatistiquesPage> createState() => _NotesStatistiquesPageState();
}

class _NotesStatistiquesPageState extends State<NotesStatistiquesPage> {
  int? _semestreId;
  int _session = 1;
  int? _niveauId;
  bool _chargement = false;
  String? _erreur;
  Map<String, dynamic>? _donnees;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _charger();
    }
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    if (_semestreId == null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/notes/statistiques', {
        'semestre_id': _semestreId,
        'session': _session,
        if (_niveauId != null) 'niveau_id': _niveauId,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _donnees = donnees);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final donnees = _donnees ?? {};
    final ues = (donnees['ues'] as List?) ?? [];
    final mentions = Map<String, dynamic>.from(donnees['mentions'] as Map? ?? {});
    final tauxSaisie = ((donnees['taux_saisie'] as num?) ?? 0).toDouble() / 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Statistiques',
            sousTitre: 'Analyse des résultats, mentions et performance par unité d’enseignement.',
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
              spacing: 18,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                selecteurSemestre(
                  app,
                  _semestreId,
                  (valeur) => app.selectionnerSemestre(valeur),
                ),
                selecteurSession(_session, (valeur) {
                  setState(() => _session = valeur ?? 1);
                  _charger();
                }),
                selecteurNiveau(app, _niveauId, (valeur) {
                  setState(() => _niveauId = valeur);
                  _charger();
                }),
                if ('${donnees['semestre'] ?? ''}'.isNotEmpty)
                  Pastille(donnees['semestre'].toString(), couleur: AppCouleurs.violet),
              ],
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 14),
            Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
          ],
          const SizedBox(height: 16),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            LayoutBuilder(
              builder: (context, contraintes) {
                final cartes = [
                  CarteIndicateur(
                    libelle: 'Étudiants inscrits',
                    valeur: '${donnees['etudiants'] ?? 0}',
                    icone: Icons.people_outline,
                    couleur: AppCouleurs.bleu,
                    detail: '${donnees['resultats'] ?? 0} résultat(s)',
                  ),
                  CarteIndicateur(
                    libelle: 'Moyenne générale',
                    valeur: '/${noteTexte(donnees['moyenne_generale'])}',
                    icone: Icons.analytics_outlined,
                    couleur: AppCouleurs.violet,
                    detail: 'sur 20',
                  ),
                  CarteIndicateur(
                    libelle: 'Taux de réussite',
                    valeur: '${noteTexte(donnees['taux_reussite'], decimales: 1)} %',
                    icone: Icons.trending_up_outlined,
                    couleur: AppCouleurs.vert,
                    detail: '${donnees['admis'] ?? 0} admis',
                  ),
                  CarteIndicateur(
                    libelle: 'Taux de saisie',
                    valeur: '${noteTexte(donnees['taux_saisie'], decimales: 1)} %',
                    icone: Icons.fact_check_outlined,
                    couleur: AppCouleurs.ambre,
                    detail:
                        '${donnees['notes_saisies'] ?? 0} / ${donnees['notes_attendues'] ?? 0} notes',
                  ),
                ];
                if (contraintes.maxWidth < 900) {
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final carte in cartes)
                        SizedBox(width: (contraintes.maxWidth - 14) / 2, child: carte),
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var i = 0; i < cartes.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: cartes[i]),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, contraintes) {
                final progression = CarteSection(
                  titre: 'Avancement de la saisie',
                  sousTitre:
                      '${donnees['evaluations'] ?? 0} évaluation(s) programmée(s) pour le semestre.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: BarreProgression(valeur: tauxSaisie)),
                          const SizedBox(width: 12),
                          Text(
                            '${noteTexte(donnees['taux_saisie'], decimales: 1)} %',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${donnees['notes_saisies'] ?? 0} note(s) saisie(s) sur ${donnees['notes_attendues'] ?? 0} attendue(s).',
                        style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
                      ),
                    ],
                  ),
                );
                final mentionsCarte = CarteSection(
                  titre: 'Répartition des mentions',
                  sousTitre: 'Selon la moyenne générale du semestre.',
                  child: mentions.isEmpty
                      ? const Text(
                          'Aucune mention calculée pour le moment.',
                          style: TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entree in mentions.entries)
                              Pastille(
                                '${entree.key} : ${entree.value}',
                                couleur: couleurStatut(entree.key),
                              ),
                          ],
                        ),
                );
                if (contraintes.maxWidth < 900) {
                  return Column(
                    children: [
                      progression,
                      const SizedBox(height: 16),
                      mentionsCarte,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: progression),
                    const SizedBox(width: 16),
                    Expanded(child: mentionsCarte),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            CarteTableau(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Text(
                      'Résultats par unité d’enseignement',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Divider(height: 1),
                  if (ues.isEmpty)
                    const EtatVide(
                      message: 'Aucune unité d’enseignement pour ce semestre.',
                      icone: Icons.library_books_outlined,
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 22,
                        horizontalMargin: 18,
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('CODE')),
                          DataColumn(label: Text('UNITÉ D’ENSEIGNEMENT')),
                          DataColumn(label: Text('CRÉDITS'), numeric: true),
                          DataColumn(label: Text('INSCRITS'), numeric: true),
                          DataColumn(label: Text('MOYENNE')),
                          DataColumn(label: Text('TAUX DE RÉUSSITE')),
                          DataColumn(label: Text('PROGRESSION')),
                        ],
                        rows: [
                          for (final ue in ues)
                            DataRow(
                              cells: [
                                DataCell(Text('${ue['code'] ?? '—'}')),
                                DataCell(
                                  SizedBox(
                                    width: 230,
                                    child: Text(
                                      '${ue['nom'] ?? '—'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(Text('${ue['credits'] ?? 0}')),
                                DataCell(Text('${ue['inscrits'] ?? 0}')),
                                DataCell(Text('/${noteTexte(ue['moyenne'])}')),
                                DataCell(
                                  Pastille(
                                    '${noteTexte(ue['taux_reussite'], decimales: 1)} %',
                                    couleur: _couleurTaux(
                                      ((ue['taux_reussite'] as num?) ?? 0).toDouble(),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 150,
                                    child: BarreProgression(
                                      valeur:
                                          ((ue['taux_reussite'] as num?) ?? 0).toDouble() / 100,
                                      couleur: _couleurTaux(
                                        ((ue['taux_reussite'] as num?) ?? 0).toDouble(),
                                      ),
                                    ),
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
          ],
        ],
      ),
    );
  }

  Color _couleurTaux(double taux) {
    if (taux >= 75) return AppCouleurs.vert;
    if (taux >= 50) return AppCouleurs.ambre;
    return AppCouleurs.rouge;
  }
}
