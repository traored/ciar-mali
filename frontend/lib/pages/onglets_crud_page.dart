import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../crud/configs.dart';
import '../crud/crud_config.dart';
import '../crud/generic_crud_page.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Page regroupant plusieurs référentiels sous forme d'onglets.
class OngletsCrudPage extends StatefulWidget {
  final String titre;
  final String sousTitre;
  final List<OngletCrud> onglets;
  final IconData icone;

  const OngletsCrudPage({
    super.key,
    required this.titre,
    required this.sousTitre,
    required this.onglets,
    this.icone = Icons.folder_copy_outlined,
  });

  @override
  State<OngletsCrudPage> createState() => _OngletsCrudPageState();
}

class OngletCrud {
  final String libelle;
  final IconData? icone;
  final ConfigCrud Function(AppState) config;
  final Widget Function()? page;

  const OngletCrud({
    required this.libelle,
    required this.config,
    this.icone,
    this.page,
  });
}

class _OngletsCrudPageState extends State<OngletsCrudPage>
    with SingleTickerProviderStateMixin {
  late final TabController _controleur;

  @override
  void initState() {
    super.initState();
    _controleur = TabController(length: widget.onglets.length, vsync: this);
    _controleur.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppCouleurs.bleu.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icone, size: 20, color: AppCouleurs.bleu),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.titre,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.sousTitre,
                          style: const TextStyle(fontSize: 12.5, color: AppCouleurs.texteDoux),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TabBar(
                controller: _controleur,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppCouleurs.bleu,
                unselectedLabelColor: AppCouleurs.texteDoux,
                indicatorColor: AppCouleurs.bleu,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: [
                  for (final onglet in widget.onglets)
                    Tab(
                      height: 44,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onglet.icone != null) ...[
                            Icon(onglet.icone, size: 16),
                            const SizedBox(width: 7),
                          ],
                          Text(onglet.libelle),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _controleur,
            children: [
              for (final onglet in widget.onglets)
                onglet.page != null
                    ? KeyedSubtree(
                        key: ValueKey(onglet.libelle),
                        child: onglet.page!(),
                      )
                    : GenericCrudPage(
                        key: ValueKey(onglet.libelle),
                        config: onglet.config,
                      ),
            ],
          ),
        ),
        if (_controleur.index < widget.onglets.length)
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Builder(
              builder: (context) {
                final config = widget.onglets[_controleur.index].config(app);
                final total = config.source(app).length;
                return Row(
                  children: [
                    Pastille('$total ${config.nomSingulier}${total > 1 ? 's' : ''}'),
                    const Spacer(),
                    Text(
                      'Données synchronisées avec le serveur',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppCouleurs.texteDoux.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

// Pages prêtes à l'emploi ------------------------------------------------------

class StructurePage extends StatelessWidget {
  const StructurePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OngletsCrudPage(
      titre: 'Structure pédagogique',
      sousTitre: 'Départements, filières, niveaux et groupes d’étudiants.',
      icone: Icons.account_tree_outlined,
      onglets: [
        OngletCrud(
          libelle: 'Départements',
          icone: Icons.business_outlined,
          config: configDepartements,
        ),
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
          libelle: 'Groupes',
          icone: Icons.groups_outlined,
          config: configGroupes,
        ),
      ],
    );
  }
}

class AcademiquePage extends StatelessWidget {
  const AcademiquePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OngletsCrudPage(
      titre: 'Programme académique',
      sousTitre: 'Semestres et semaines de cours, unités d’enseignement, ECUE et affectations (CM communs inclus).',
      icone: Icons.menu_book_outlined,
      onglets: [
        OngletCrud(
          libelle: 'Semestres & semaines',
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
        OngletCrud(
          libelle: 'Affectations',
          icone: Icons.assignment_ind_outlined,
          config: configAffectations,
        ),
      ],
    );
  }
}

class RessourcesPage extends StatelessWidget {
  const RessourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OngletsCrudPage(
      titre: 'Ressources',
      sousTitre: 'Enseignants, salles et créneaux horaires.',
      icone: Icons.inventory_2_outlined,
      onglets: [
        OngletCrud(
          libelle: 'Enseignants',
          icone: Icons.person_outline,
          config: configEnseignants,
        ),
        OngletCrud(
          libelle: 'Salles',
          icone: Icons.meeting_room_outlined,
          config: configSalles,
        ),
        OngletCrud(
          libelle: 'Créneaux',
          icone: Icons.schedule_outlined,
          config: configCreneaux,
        ),
      ],
    );
  }
}
