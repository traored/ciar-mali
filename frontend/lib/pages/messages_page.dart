import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Espace « Messages » : notifications reçues d'un administrateur.
///
/// Un administrateur peut y composer un message et cocher les groupes de
/// destinataires (autres administrateurs, gestionnaires, enseignants,
/// étudiants). Chaque compte retrouve ici les messages qui le concernent.
/// L'expéditeur conserve une copie de ses envois et peut les supprimer.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  bool _chargement = true;
  bool _marquage = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await context.read<AppState>().chargerNotifications();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _marquerLue(AppState app, int id) async {
    try {
      await app.marquerNotificationLue(id);
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  Future<void> _supprimer(AppState app, int id, String titre) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce message ?'),
        content: Text(
          '« $titre » sera supprimé définitivement de la boîte de tous les '
          'destinataires.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppCouleurs.rouge),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    try {
      await app.supprimerNotification(id);
      if (mounted) afficherMessage(context, 'Message supprimé.');
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    }
  }

  Future<void> _toutMarquerLues(AppState app) async {
    setState(() => _marquage = true);
    try {
      final nombre = await app.marquerToutesNotificationsLues();
      if (!mounted) return;
      afficherMessage(
        context,
        nombre == 0
            ? 'Toutes les notifications étaient déjà lues.'
            : '$nombre notification(s) marquée(s) comme lue(s).',
      );
    } catch (e) {
      if (mounted) afficherMessage(context, e.toString(), erreur: true);
    } finally {
      if (mounted) setState(() => _marquage = false);
    }
  }

  Future<void> _composer(AppState app) async {
    final reponse = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogueNouveauMessage(app: app),
    );
    if (reponse == null || !mounted) return;
    final nombre = (reponse['nombre_destinataires'] as num?)?.toInt() ?? 0;
    afficherMessage(context, 'Message envoyé à $nombre destinataire(s).');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nonLues = app.notificationsNonLues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(app, nonLues),
        const Divider(height: 1),
        Expanded(child: _corps(app)),
      ],
    );
  }

  Widget _entete(AppState app, int nonLues) {
    final actions = <Widget>[
      if (nonLues > 0)
        OutlinedButton.icon(
          onPressed: _marquage ? null : () => _toutMarquerLues(app),
          icon: _marquage
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.done_all_outlined, size: 18),
          label: Text('Tout marquer comme lu ($nonLues)'),
        ),
      if (app.estAdmin)
        FilledButton.icon(
          onPressed: () => _composer(app),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Nouveau message'),
        ),
    ];
    final titre = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppCouleurs.bleu.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.mark_email_unread_outlined,
            size: 18,
            color: AppCouleurs.bleu,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (nonLues > 0) ...[
                    const SizedBox(width: 8),
                    Pastille(
                      '$nonLues non lue${nonLues > 1 ? 's' : ''}',
                      couleur: AppCouleurs.rouge,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Notifications envoyées par un administrateur.',
                style: TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          if (contraintes.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titre,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: actions),
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titre),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _corps(AppState app) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 42,
                color: AppCouleurs.texteDoux,
              ),
              const SizedBox(height: 12),
              Text(
                _erreur!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppCouleurs.texteDoux),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (app.notifications.isEmpty) {
      return EtatVide(
        icone: Icons.inbox_outlined,
        message: app.estAdmin
            ? 'Aucun message reçu pour le moment.\nUtilisez « Nouveau message » pour envoyer une notification.'
            : 'Aucun message reçu pour le moment.',
        action: app.estAdmin
            ? FilledButton.icon(
                onPressed: () => _composer(app),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Nouveau message'),
              )
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: app.notifications.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final notification = app.notifications[index];
        return _carte(app, notification);
      },
    );
  }

  Widget _carte(AppState app, Map<String, dynamic> notification) {
    final lu = notification['lu'] == true;
    final id = (notification['id'] as num).toInt();
    final titre = '${notification['titre'] ?? ''}';
    final message = '${notification['message'] ?? ''}';
    final auteur = '${notification['auteur_nom'] ?? ''}';
    final date = _formaterDate('${notification['cree_le'] ?? ''}');
    final auteurId = notification['auteur_id'];
    final estAuteur =
        app.estAdmin &&
        auteurId is num &&
        auteurId.toInt() == app.utilisateur?.id;

    return Container(
      decoration: BoxDecoration(
        color: lu ? Colors.white : AppCouleurs.bleu.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: lu
              ? AppCouleurs.bordure
              : AppCouleurs.bleu.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: lu ? null : () => _marquerLue(app, id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!lu) ...[
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: const BoxDecoration(
                          color: AppCouleurs.bleu,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        titre,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: lu ? FontWeight.w600 : FontWeight.w800,
                          color: AppCouleurs.texte,
                        ),
                      ),
                    ),
                    if (estAuteur)
                      const Pastille(
                        'Envoyé par vous',
                        couleur: AppCouleurs.teal,
                      ),
                    if (!lu)
                      const Pastille('Nouveau', couleur: AppCouleurs.bleu),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (auteur.isNotEmpty) auteur,
                    if (date.isNotEmpty) date,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppCouleurs.texteDoux,
                  ),
                ),
                const SizedBox(height: 11),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppCouleurs.texte,
                  ),
                ),
                if (!lu || estAuteur) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Spacer(),
                      if (!lu)
                        TextButton.icon(
                          onPressed: () => _marquerLue(app, id),
                          icon: const Icon(Icons.done, size: 16),
                          label: const Text('Marquer comme lu'),
                        ),
                      if (estAuteur)
                        TextButton.icon(
                          onPressed: () => _supprimer(app, id, titre),
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: AppCouleurs.rouge,
                          ),
                          label: const Text(
                            'Supprimer',
                            style: TextStyle(color: AppCouleurs.rouge),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formaterDate(String iso) {
    if (iso.isEmpty) return '';
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return iso;
    return DateFormat('dd/MM/yyyy à HH:mm').format(date);
  }
}

class _DialogueNouveauMessage extends StatefulWidget {
  final AppState app;

  const _DialogueNouveauMessage({required this.app});

  @override
  State<_DialogueNouveauMessage> createState() =>
      _DialogueNouveauMessageState();
}

class _DialogueNouveauMessageState extends State<_DialogueNouveauMessage> {
  final _titre = TextEditingController();
  final _message = TextEditingController();
  bool _admins = false;
  bool _gestionnaires = false;
  bool _enseignants = false;
  bool _etudiants = false;
  bool _superviseurs = false;
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _message.dispose();
    super.dispose();
  }

  int _nombre(String role) {
    return widget.app.utilisateurs.where((utilisateur) {
      if ('${utilisateur['role'] ?? ''}' != role) return false;
      if (utilisateur['actif'] == false) return false;
      return true;
    }).length;
  }

  Future<void> _envoyer() async {
    final titre = _titre.text.trim();
    final message = _message.text.trim();
    final destinataires = <String>[
      if (_admins) 'admin',
      if (_gestionnaires) 'gestionnaire',
      if (_enseignants) 'enseignant',
      if (_etudiants) 'lecteur',
      if (_superviseurs) 'superviseur',
    ];
    if (titre.isEmpty) {
      setState(() => _erreur = 'Saisissez un titre.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _erreur = 'Saisissez le message à envoyer.');
      return;
    }
    if (destinataires.isEmpty) {
      setState(() => _erreur = 'Cochez au moins un groupe de destinataires.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final reponse = await widget.app.api.post('/notifications', {
        'titre': titre,
        'message': message,
        'destinataires': destinataires,
      });
      await widget.app.chargerNotifications();
      if (mounted) Navigator.of(context).pop(reponse);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.toString();
          _envoi = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Nouveau message',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titre,
                enabled: !_envoi,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  hintText: 'Ex. : Réunion pédagogique du 20 novembre',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _message,
                enabled: !_envoi,
                minLines: 5,
                maxLines: 9,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Destinataires',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Cochez les groupes qui doivent recevoir ce message. '
                'Une copie est toujours ajoutée à votre boîte.',
                style: TextStyle(fontSize: 11.5, color: AppCouleurs.texteDoux),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _admins,
                onChanged: _envoi
                    ? null
                    : (valeur) => setState(() => _admins = valeur ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Administrateurs'),
                subtitle: Text(
                  '${_nombre('admin')} administrateur(s)',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              CheckboxListTile(
                value: _gestionnaires,
                onChanged: _envoi
                    ? null
                    : (valeur) =>
                          setState(() => _gestionnaires = valeur ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Gestionnaires'),
                subtitle: Text(
                  '${_nombre('gestionnaire')} gestionnaire(s)',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              CheckboxListTile(
                value: _enseignants,
                onChanged: _envoi
                    ? null
                    : (valeur) =>
                          setState(() => _enseignants = valeur ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Enseignants'),
                subtitle: Text(
                  '${_nombre('enseignant')} enseignant(s)',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              CheckboxListTile(
                value: _etudiants,
                onChanged: _envoi
                    ? null
                    : (valeur) => setState(() => _etudiants = valeur ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Étudiants'),
                subtitle: Text(
                  '${_nombre('lecteur')} étudiant(s)',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              CheckboxListTile(
                value: _superviseurs,
                onChanged: _envoi
                    ? null
                    : (valeur) => setState(() => _superviseurs = valeur ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Superviseurs surveillances'),
                subtitle: Text(
                  '${_nombre('superviseur')} superviseur(s)',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erreur!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppCouleurs.rouge,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _envoi ? null : _envoyer,
          icon: _envoi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_outlined, size: 17),
          label: const Text('Envoyer'),
        ),
      ],
    );
  }
}
