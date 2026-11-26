import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../crud/configs.dart';
import '../../crud/generic_crud_page.dart';
import '../../crud/notes_configs.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import '../onglets_crud_page.dart';
import 'commun.dart';

/// Module 1 — Étudiants : inscriptions, matricules, parcours et historique.
class NotesEtudiantsPage extends StatelessWidget {
  const NotesEtudiantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OngletsCrudPage(
      titre: 'Étudiants',
      sousTitre:
          'Inscriptions administratives, matricules, parcours et historique universitaire.',
      icone: Icons.school_outlined,
      onglets: [
        OngletCrud(
          libelle: 'Étudiants',
          icone: Icons.badge_outlined,
          config: configNotesEtudiants,
        ),
        OngletCrud(
          libelle: 'Inscriptions',
          icone: Icons.how_to_reg_outlined,
          config: configNotesInscriptions,
        ),
        OngletCrud(
          libelle: 'Parcours & historique',
          icone: Icons.timeline_outlined,
          config: configNotesEtudiants,
          page: () => const NotesParcoursPage(),
        ),
      ],
    );
  }
}

/// Module 2 — Formations : filières, niveaux, semestres, UE et ECUE.
class NotesFormationsPage extends StatelessWidget {
  const NotesFormationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OngletsCrudPage(
      titre: 'Formations',
      sousTitre: 'Filières, niveaux, semestres, unités d’enseignement et ECUE.',
      icone: Icons.account_balance_outlined,
      onglets: [
        OngletCrud(
          libelle: 'Filières',
          icone: Icons.route_outlined,
          config: configFilieres,
        ),
        OngletCrud(
          libelle: 'Niveaux',
          icone: Icons.stairs_outlined,
          config: configNiveaux,
        ),
        OngletCrud(
          libelle: 'Semestres',
          icone: Icons.date_range_outlined,
          config: configSemestres,
        ),
        OngletCrud(
          libelle: 'UE',
          icone: Icons.library_books_outlined,
          config: configUE,
        ),
        OngletCrud(
          libelle: 'ECUE',
          icone: Icons.article_outlined,
          config: configECUE,
        ),
      ],
    );
  }
}

/// Module 3 — Évaluations.
class NotesEvaluationsPage extends StatelessWidget {
  const NotesEvaluationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GenericCrudPage(config: configNotesEvaluations);
  }
}

class NotesParcoursPage extends StatefulWidget {
  const NotesParcoursPage({super.key});

  @override
  State<NotesParcoursPage> createState() => _NotesParcoursPageState();
}

class _NotesParcoursPageState extends State<NotesParcoursPage> {
  final _recherche = TextEditingController();
  String _filtre = '';
  int? _enCours;
  Map<String, dynamic>? _detail;
  String? _erreur;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _ouvrir(Map<String, dynamic> etudiant) async {
    final app = context.read<AppState>();
    setState(() {
      _enCours = etudiant['id'] as int;
      _detail = null;
      _erreur = null;
    });
    try {
      final donnees =
          await app.api.get('/notes/etudiants/${etudiant['id']}') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _detail = donnees);
      final parcours = (donnees['parcours'] as List?) ?? [];
      await showDialog<void>(
        context: context,
        builder: (context) => _DialogueParcours(donnees: donnees, parcours: parcours),
      );
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cible = _filtre.trim().toLowerCase();
    final etudiants = app.etudiantsNotes.where((etudiant) {
      if (cible.isEmpty) return true;
      return '${etudiant['matricule']} ${etudiant['nom_complet']} ${etudiant['filiere_nom']}'
          .toLowerCase()
          .contains(cible);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: 'Parcours & historique',
            sousTitre:
                'Consultez le parcours annuel d’un étudiant, ses résultats et ses décisions.',
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await app.rafraichir();
                    if (context.mounted) afficherMessage(context, 'Données actualisées');
                  } catch (e) {
                    if (context.mounted) afficherMessage(context, e.toString(), erreur: true);
                  }
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          CarteTableau(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      ChampRecherche(
                        controleur: _recherche,
                        hint: 'Rechercher un étudiant…',
                        onChanged: (v) => setState(() => _filtre = v),
                      ),
                      const Spacer(),
                      Pastille('${etudiants.length} étudiant(s)'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_erreur != null)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
                  ),
                if (etudiants.isEmpty)
                  const EtatVide(
                    message: 'Aucun étudiant ne correspond à la recherche.',
                    icone: Icons.search_off_outlined,
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 22,
                      horizontalMargin: 18,
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('MATRICULE')),
                        DataColumn(label: Text('ÉTUDIANT')),
                        DataColumn(label: Text('SEXE')),
                        DataColumn(label: Text('FILIÈRE')),
                        DataColumn(label: Text('INSCRIPTIONS')),
                        DataColumn(label: Text('PARCOURS')),
                      ],
                      rows: [
                        for (final etudiant in etudiants)
                          DataRow(
                            cells: [
                              DataCell(Text('${etudiant['matricule'] ?? '—'}')),
                              DataCell(Text('${etudiant['nom_complet'] ?? '—'}')),
                              DataCell(Text('${etudiant['sexe'] ?? '—'}')),
                              DataCell(Text('${etudiant['filiere_code'] ?? '—'}')),
                              DataCell(Text('${etudiant['nb_inscriptions'] ?? 0}')),
                              DataCell(
                                TextButton.icon(
                                  onPressed: _enCours == etudiant['id']
                                      ? null
                                      : () => _ouvrir(etudiant),
                                  icon: _enCours == etudiant['id']
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.visibility_outlined, size: 16),
                                  label: const Text('Consulter'),
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
          if (_detail != null) const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DialogueParcours extends StatelessWidget {
  final Map<String, dynamic> donnees;
  final List parcours;

  const _DialogueParcours({required this.donnees, required this.parcours});

  @override
  Widget build(BuildContext context) {
    final etudiant = donnees['etudiant'] as Map<String, dynamic>? ?? {};
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${etudiant['nom_complet'] ?? 'Étudiant'}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${etudiant['matricule'] ?? ''} · ${etudiant['filiere'] ?? '—'}',
            style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: parcours.isEmpty
              ? const EtatVide(
                  message: 'Aucune inscription enregistrée pour cet étudiant.',
                  icone: Icons.timeline_outlined,
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final inscription in parcours)
                        _BlocInscription(inscription: inscription as Map<String, dynamic>),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    );
  }
}

class _BlocInscription extends StatelessWidget {
  final Map<String, dynamic> inscription;

  const _BlocInscription({required this.inscription});

  @override
  Widget build(BuildContext context) {
    final resultats = (inscription['resultats'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppCouleurs.fond,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined, size: 18, color: AppCouleurs.bleu),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${inscription['niveau'] ?? '—'} · ${inscription['filiere'] ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              Pastille('${inscription['annee'] ?? ''}'),
              const SizedBox(width: 6),
              Pastille(
                '${inscription['statut'] ?? ''}',
                couleur: couleurStatut('${inscription['statut'] ?? ''}'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Groupe : ${inscription['groupe'] ?? '—'} · Inscription : ${inscription['date_inscription'] ?? '—'}',
            style: const TextStyle(fontSize: 11.5, color: AppCouleurs.texteDoux),
          ),
          const SizedBox(height: 10),
          if (resultats.isEmpty)
            const Text(
              'Aucun résultat enregistré pour ce parcours.',
              style: TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 34,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 40,
                columns: const [
                  DataColumn(label: Text('SEMESTRE')),
                  DataColumn(label: Text('SESSION')),
                  DataColumn(label: Text('MOYENNE')),
                  DataColumn(label: Text('CRÉDITS')),
                  DataColumn(label: Text('MENTION')),
                  DataColumn(label: Text('DÉCISION')),
                ],
                rows: [
                  for (final resultat in resultats)
                    DataRow(
                      cells: [
                        DataCell(Text('${resultat['semestre'] ?? '—'}')),
                        DataCell(Text('S${resultat['session'] ?? 1}')),
                        DataCell(Text(noteTexte(resultat['moyenne']))),
                        DataCell(
                          Text(
                            '${resultat['credits_obtenus'] ?? 0}/${resultat['credits_total'] ?? 0}',
                          ),
                        ),
                        DataCell(Text('${resultat['mention'] ?? '—'}')),
                        DataCell(
                          Pastille(
                            '${resultat['decision'] ?? resultat['statut'] ?? '—'}',
                            couleur: couleurStatut(
                              '${resultat['decision'] ?? resultat['statut'] ?? ''}',
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
    );
  }
}
