import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'dashboard_page.dart';
import 'hours_page.dart';
import 'import_page.dart';
import 'mes_cours_page.dart';
import 'mes_heures_page.dart';
import 'notes/notes_deliberations_page.dart';
import 'notes/notes_documents_page.dart';
import 'notes/notes_etudiants_page.dart';
import 'notes/notes_points_jury_page.dart';
import 'notes/notes_passages_page.dart';
import 'notes/notes_resultats_page.dart';
import 'notes/notes_saisie_page.dart';
import 'notes/notes_statistiques_page.dart';
import 'onglets_crud_page.dart';
import 'sessions_page.dart';
import 'suivi_global_page.dart';
import 'timetable_page.dart';
import 'users_page.dart';

class _Destination {
  final String cle;
  final String libelle;
  final IconData icone;
  final String section;
  final List<String> roles;

  const _Destination({
    required this.cle,
    required this.libelle,
    required this.icone,
    required this.section,
    required this.roles,
  });
}

const _destinations = <_Destination>[
  _Destination(
    cle: 'mes-cours',
    libelle: 'Mes cours',
    icone: Icons.menu_book_outlined,
    section: 'Mon espace',
    roles: ['enseignant'],
  ),
  _Destination(
    cle: 'mes-heures',
    libelle: 'Suivi de mes heures',
    icone: Icons.timer_outlined,
    section: 'Mon espace',
    roles: ['enseignant'],
  ),
  _Destination(
    cle: 'suivi-global',
    libelle: 'Suivi global',
    icone: Icons.insights_outlined,
    section: 'Mon espace',
    roles: ['enseignant'],
  ),
  _Destination(
    cle: 'dashboard',
    libelle: 'Tableau de bord',
    icone: Icons.dashboard_outlined,
    section: 'Pilotage',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'emploi',
    libelle: 'Emploi du temps',
    icone: Icons.calendar_month_outlined,
    section: 'Pilotage',
    roles: ['admin', 'gestionnaire', 'enseignant', 'lecteur'],
  ),
  _Destination(
    cle: 'seances',
    libelle: 'Séances',
    icone: Icons.event_note_outlined,
    section: 'Pilotage',
    roles: ['admin', 'gestionnaire', 'enseignant'],
  ),
  _Destination(
    cle: 'heures',
    libelle: 'Heures enseignants',
    icone: Icons.timer_outlined,
    section: 'Pilotage',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'structure',
    libelle: 'Structure',
    icone: Icons.account_tree_outlined,
    section: 'Référentiels',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'programme',
    libelle: 'Programme',
    icone: Icons.menu_book_outlined,
    section: 'Référentiels',
    roles: ['admin', 'gestionnaire', 'enseignant'],
  ),
  _Destination(
    cle: 'ressources',
    libelle: 'Ressources',
    icone: Icons.inventory_2_outlined,
    section: 'Référentiels',
    roles: ['admin', 'gestionnaire', 'enseignant'],
  ),
  _Destination(
    cle: 'import',
    libelle: 'Import Excel',
    icone: Icons.upload_file_outlined,
    section: 'Administration',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'utilisateurs',
    libelle: 'Utilisateurs & rôles',
    icone: Icons.admin_panel_settings_outlined,
    section: 'Administration',
    roles: ['admin'],
  ),
  _Destination(
    cle: 'notes-etudiants',
    libelle: 'Étudiants',
    icone: Icons.school_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'notes-formations',
    libelle: 'Formations',
    icone: Icons.account_balance_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'notes-evaluations',
    libelle: 'Évaluations',
    icone: Icons.assignment_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'notes-saisie',
    libelle: 'Saisie des notes',
    icone: Icons.edit_note_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire', 'enseignant'],
  ),
  _Destination(
    cle: 'notes-resultats',
    libelle: 'Résultats',
    icone: Icons.calculate_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'notes-deliberations',
    libelle: 'Délibérations',
    icone: Icons.gavel_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'notes-points-jury',
    libelle: 'Points jury',
    icone: Icons.workspace_premium_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
  _Destination(
    cle: 'notes-documents',
    libelle: 'Documents',
    icone: Icons.description_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire', 'lecteur'],
  ),
  _Destination(
    cle: 'notes-statistiques',
    libelle: 'Statistiques',
    icone: Icons.query_stats_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire', 'enseignant'],
  ),
  _Destination(
    cle: 'notes-passages',
    libelle: 'Passages en classe supérieure',
    icone: Icons.upgrade_outlined,
    section: 'Gestion des notes',
    roles: ['admin', 'gestionnaire'],
  ),
];

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  String _actif = 'dashboard';
  bool _menuOuvert = false;
  bool _notesOuvert = false;
  final ScrollController _defilementMenu = ScrollController();

  @override
  void dispose() {
    _defilementMenu.dispose();
    super.dispose();
  }

  void _naviguer(String cle) {
    setState(() {
      _actif = cle;
      _menuOuvert = false;
      if (_destinations.any(
        (d) => d.cle == cle && d.section == 'Gestion des notes',
      )) {
        _notesOuvert = true;
      }
    });
  }

  Widget _contenu() {
    switch (_actif) {
      case 'mes-cours':
        return const MesCoursPage();
      case 'mes-heures':
        return const MesHeuresPage();
      case 'suivi-global':
        return const SuiviGlobalPage();
      case 'emploi':
        return const TimetablePage();
      case 'seances':
        return const SessionsPage();
      case 'heures':
        return const HoursPage();
      case 'notes-etudiants':
        return const NotesEtudiantsPage();
      case 'notes-formations':
        return const NotesFormationsPage();
      case 'notes-evaluations':
        return const NotesEvaluationsPage();
      case 'notes-saisie':
        return const NotesSaisiePage();
      case 'notes-resultats':
        return const NotesResultatsPage();
      case 'notes-deliberations':
        return const NotesDeliberationsPage();
      case 'notes-points-jury':
        return const NotesPointsJuryPage();
      case 'notes-documents':
        return const NotesDocumentsPage();
      case 'notes-statistiques':
        return const NotesStatistiquesPage();
      case 'notes-passages':
        return const NotesPassagesPage();
      case 'structure':
        return const StructurePage();
      case 'programme':
        return const AcademiquePage();
      case 'ressources':
        return const RessourcesPage();
      case 'import':
        return const ImportPage();
      case 'utilisateurs':
        return const UsersPage();
      default:
        return const DashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.utilisateur?.role ?? 'lecteur';
    final destinations = _destinations
        .where((d) => d.roles.contains(role))
        .toList();
    if (!destinations.any((d) => d.cle == _actif)) {
      _actif = destinations.isEmpty ? 'dashboard' : destinations.first.cle;
    }
    final large = MediaQuery.sizeOf(context).width >= 1080;

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              if (large) _barreLaterale(app, destinations),
              Expanded(
                child: Column(
                  children: [
                    _barreSuperieure(app, large: large),
                    const Divider(height: 1),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(_actif),
                          child: _contenu(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!large && _menuOuvert) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _menuOuvert = false),
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: Material(
                elevation: 12,
                child: _barreLaterale(app, destinations, compact: true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barreLaterale(
    AppState app,
    List<_Destination> destinations, {
    bool compact = false,
  }) {
    final sections = <String, List<_Destination>>{};
    for (final destination in destinations) {
      sections.putIfAbsent(destination.section, () => []).add(destination);
    }
    final role = app.utilisateur?.role ?? 'lecteur';

    return Container(
      width: compact ? 270 : 258,
      color: AppCouleurs.bleuNuit,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF0D9488)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CIAR-Mali',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Emplois du temps',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (compact)
                    IconButton(
                      onPressed: () => setState(() => _menuOuvert = false),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Fermer le menu',
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Color(0xFF1E2E4F), height: 1),
            ),
            Expanded(
              child: Scrollbar(
                controller: _defilementMenu,
                thumbVisibility: true,
                child: ListView(
                  controller: _defilementMenu,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                  children: [
                    for (final entree in sections.entries) ...[
                      if (entree.key == 'Gestion des notes') ...[
                        _enteteNotes(
                          ouvert: _notesOuvert,
                          actif: entree.value.any((d) => d.cle == _actif),
                          titre: role == 'lecteur'
                              ? 'Mon espace'
                              : 'Gestion des notes',
                        ),
                        if (_notesOuvert)
                          for (final destination in entree.value)
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: _elementNavigation(destination, app),
                            ),
                        const SizedBox(height: 10),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Text(
                            entree.key.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        for (final destination in entree.value)
                          _elementNavigation(destination, app),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFF1E3A8A),
                      child: Text(
                        _initiales(app.utilisateur?.nomComplet ?? '?'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.utilisateur?.nomComplet ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _libelleRole(role),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Changer de mot de passe',
                      onPressed: () => _dialogueMotDePasse(app),
                      icon: const Icon(
                        Icons.key_outlined,
                        color: Color(0xFF94A3B8),
                        size: 17,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Se déconnecter',
                      onPressed: () => app.deconnexion(),
                      icon: const Icon(
                        Icons.logout,
                        color: Color(0xFFF87171),
                        size: 17,
                      ),
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

  Widget _enteteNotes({
    required bool ouvert,
    required bool actif,
    required String titre,
  }) {
    final surligne = actif && !ouvert;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: surligne
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: () => setState(() => _notesOuvert = !_notesOuvert),
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 18,
                  color: surligne ? Colors.white : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    titre,
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight: surligne ? FontWeight.w700 : FontWeight.w600,
                      color: surligne ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: ouvert ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.expand_more,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _elementNavigation(_Destination destination, AppState app) {
    final actif = _actif == destination.cle;
    final libelle = app.estLecteur && destination.cle == 'notes-documents'
        ? 'Mon relevé de notes'
        : destination.libelle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: actif
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: () => _naviguer(destination.cle),
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              children: [
                Icon(
                  destination.icone,
                  size: 18,
                  color: actif ? Colors.white : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    libelle,
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                      color: actif ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                if (actif)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5EEAD4),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barreSuperieure(AppState app, {required bool large}) {
    final semestres = app.semestres;
    final etroit = MediaQuery.sizeOf(context).width < 760;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: etroit ? 10 : 20, vertical: 11),
      child: Row(
        children: [
          if (!large)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: () => setState(() => _menuOuvert = true),
                icon: const Icon(Icons.menu, size: 22),
                tooltip: 'Menu',
              ),
            ),
          Expanded(
            child: Row(
              children: [
                // Sur téléphone, l'espace est réservé aux sélecteurs et aux
                // actions : l'indicateur de synchronisation y est masqué pour
                // que le bouton de déconnexion reste visible.
                if (!etroit) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: app.chargementDonnees
                          ? AppCouleurs.ambre
                          : AppCouleurs.vert,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      app.chargementDonnees
                          ? 'Synchronisation…'
                          : 'Données à jour',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppCouleurs.texteDoux,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (semestres.isNotEmpty)
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: etroit ? 160 : 260),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppCouleurs.bordure),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: app.semestreId,
                    isDense: true,
                    isExpanded: true,
                    icon: const Icon(Icons.expand_more, size: 18),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppCouleurs.texte,
                    ),
                    items: [
                      for (final semestre in semestres)
                        DropdownMenuItem(
                          value: semestre['id'] as int,
                          child: Row(
                            children: [
                              Icon(
                                semestre['actif'] == true
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 13,
                                color: semestre['actif'] == true
                                    ? AppCouleurs.vert
                                    : AppCouleurs.texteDoux,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  '${semestre['nom']} · ${semestre['annee']}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (valeur) {
                      app.selectionnerSemestre(valeur);
                      setState(() {});
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Actualiser les données',
            onPressed: app.chargementDonnees
                ? null
                : () async {
                    try {
                      await app.rafraichir();
                      if (mounted)
                        afficherMessage(context, 'Données actualisées');
                    } catch (e) {
                      if (mounted)
                        afficherMessage(context, e.toString(), erreur: true);
                    }
                  },
            icon: const Icon(
              Icons.sync,
              size: 19,
              color: AppCouleurs.texteDoux,
            ),
          ),
          if (!large)
            IconButton(
              tooltip: 'Se déconnecter',
              onPressed: () => app.deconnexion(),
              icon: const Icon(
                Icons.logout,
                size: 19,
                color: AppCouleurs.rouge,
              ),
            ),
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            tooltip: 'Mon compte',
            offset: const Offset(0, 42),
            onSelected: (valeur) {
              if (valeur == 'motdepasse') _dialogueMotDePasse(app);
              if (valeur == 'deconnexion') app.deconnexion();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'motdepasse',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.key_outlined, size: 18),
                  title: Text(
                    'Changer de mot de passe',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'deconnexion',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.logout,
                    size: 18,
                    color: AppCouleurs.rouge,
                  ),
                  title: Text(
                    'Se déconnecter',
                    style: TextStyle(fontSize: 13, color: AppCouleurs.rouge),
                  ),
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppCouleurs.bordure),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppCouleurs.bleu.withValues(alpha: 0.10),
                    child: Text(
                      _initiales(app.utilisateur?.nomComplet ?? '?'),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppCouleurs.bleu,
                      ),
                    ),
                  ),
                  if (large) ...[
                    const SizedBox(width: 8),
                    Text(
                      _libelleRole(app.utilisateur?.role ?? ''),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ],
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: AppCouleurs.texteDoux,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogueMotDePasse(AppState app) async {
    final ancien = TextEditingController();
    final nouveau = TextEditingController();
    final confirmation = TextEditingController();
    String? erreur;
    bool envoi = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setEtat) => AlertDialog(
          title: const Text(
            'Changer de mot de passe',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ancien,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe actuel',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nouveau,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le nouveau mot de passe',
                  ),
                ),
                if (erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    erreur!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppCouleurs.rouge,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: envoi ? null : () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: envoi
                  ? null
                  : () async {
                      if (nouveau.text.length < 4) {
                        setEtat(
                          () => erreur = 'Le nouveau mot de passe doit contenir au moins 4 caractères.',
                        );
                        return;
                      }
                      if (nouveau.text != confirmation.text) {
                        setEtat(
                          () => erreur = 'La confirmation ne correspond pas au nouveau mot de passe.',
                        );
                        return;
                      }
                      setEtat(() {
                        envoi = true;
                        erreur = null;
                      });
                      try {
                        await app.api.post('/auth/mot-de-passe', {
                          'ancien': ancien.text,
                          'nouveau': nouveau.text,
                        });
                        if (context.mounted) Navigator.pop(context);
                        if (mounted)
                          afficherMessage(this.context, 'Mot de passe modifié');
                      } catch (e) {
                        setEtat(() {
                          erreur = e.toString();
                          envoi = false;
                        });
                      }
                    },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    ancien.dispose();
    nouveau.dispose();
    confirmation.dispose();
  }

  String _initiales(String nom) {
    final morceaux = nom
        .trim()
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty)
        .toList();
    if (morceaux.isEmpty) return '?';
    if (morceaux.length == 1) {
      return morceaux.first
          .substring(0, morceaux.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${morceaux.first[0]}${morceaux.last[0]}'.toUpperCase();
  }

  String _libelleRole(String role) => switch (role) {
    'admin' => 'Administrateur',
    'gestionnaire' => 'Gestionnaire',
    'enseignant' => 'Enseignant',
    _ => 'Lecteur',
  };
}
