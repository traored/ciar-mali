import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../crud/configs.dart';
import '../crud/generic_crud_page.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  bool _creation = false;

  Future<void> _creerComptesParDefaut() async {
    final app = context.read<AppState>();
    final confirme = await confirmer(
      context,
      titre: 'Comptes par défaut',
      message:
          'Un compte sera créé pour chaque étudiant et enseignant qui n’en possède pas encore.\n\n'
          'Identifiant : prénom (prénom2, prénom3… en cas de doublon)\n'
          'Mot de passe : matricule\n\n'
          'Les comptes existants ne seront ni modifiés ni supprimés.',
      action: 'Créer les comptes',
      danger: false,
    );
    if (!confirme || !mounted) return;
    setState(() => _creation = true);
    try {
      final reponse = await app.api.post(
        '/utilisateurs/comptes-par-defaut',
        {},
      ) as Map<String, dynamic>;
      await app.rafraichir();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _DialogueComptesParDefaut(donnees: reponse),
      );
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _creation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.estAdmin) {
      return const Center(
        child: EtatVide(
          message:
              'Seul un administrateur peut gérer les comptes utilisateurs.',
          icone: Icons.lock_outline,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppCouleurs.violet.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: AppCouleurs.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rôles : administrateur (tous droits), gestionnaire (édition des référentiels et séances), '
                  'enseignant (ses séances et son relevé d’heures), lecteur (consultation).',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppCouleurs.texteDoux.withValues(alpha: 0.95),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              FilledButton.icon(
                onPressed: _creation ? null : _creerComptesParDefaut,
                icon: _creation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Comptes par défaut'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const Expanded(child: GenericCrudPage(config: configUtilisateurs)),
      ],
    );
  }
}

class _DialogueComptesParDefaut extends StatelessWidget {
  final Map<String, dynamic> donnees;

  const _DialogueComptesParDefaut({required this.donnees});

  @override
  Widget build(BuildContext context) {
    final comptes = ((donnees['comptes'] as List?) ?? [])
        .map((element) => Map<String, dynamic>.from(element as Map))
        .toList();
    final ignores = ((donnees['ignores'] as List?) ?? [])
        .map((element) => Map<String, dynamic>.from(element as Map))
        .toList();
    final etudiants = (donnees['etudiants_crees'] as num?)?.toInt() ?? 0;
    final enseignants = (donnees['enseignants_crees'] as num?)?.toInt() ?? 0;
    return AlertDialog(
      title: const Text(
        'Comptes par défaut',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pastille('$etudiants étudiant(s)', couleur: AppCouleurs.bleu),
                Pastille(
                  '$enseignants enseignant(s)',
                  couleur: AppCouleurs.teal,
                ),
                if (ignores.isNotEmpty)
                  Pastille(
                    '${ignores.length} ignoré(s)',
                    couleur: AppCouleurs.ambre,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              comptes.isEmpty
                  ? 'Tous les étudiants et enseignants disposent déjà d’un compte.'
                  : 'Communiquez ces identifiants aux intéressés. Le mot de passe par défaut est le matricule.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppCouleurs.texteDoux,
              ),
            ),
            if (comptes.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 360,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 18,
                    horizontalMargin: 4,
                    columns: const [
                      DataColumn(label: Text('IDENTIFIANT')),
                      DataColumn(label: Text('NOM COMPLET')),
                      DataColumn(label: Text('RÔLE')),
                      DataColumn(label: Text('MOT DE PASSE')),
                    ],
                    rows: [
                      for (final compte in comptes)
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '${compte['identifiant'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DataCell(Text('${compte['nom_complet'] ?? ''}')),
                            DataCell(Text('${compte['role'] ?? ''}')),
                            DataCell(Text('${compte['mot_de_passe'] ?? ''}')),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (ignores.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Enseignants ignorés (matricule manquant)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              for (final ignore in ignores)
                Text(
                  '• ${ignore['nom_complet'] ?? '—'} — ${ignore['motif'] ?? ''}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
