import 'package:flutter/material.dart';

import '../theme.dart';

export '../utils/formats.dart';
export 'telechargement.dart';

void afficherMessage(BuildContext context, String message, {bool erreur = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? AppCouleurs.rouge : AppCouleurs.bleuNuit,
        duration: Duration(seconds: erreur ? 6 : 3),
      ),
    );
}

Future<bool> confirmer(
  BuildContext context, {
  required String titre,
  required String message,
  String action = 'Supprimer',
  bool danger = true,
}) async {
  final resultat = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppCouleurs.rouge : AppCouleurs.bleu,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return resultat ?? false;
}

class EntetePage extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final List<Widget> actions;

  const EntetePage({
    super.key,
    required this.titre,
    this.sousTitre,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final texte = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titre,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
            if (sousTitre != null) ...[
              const SizedBox(height: 4),
              Text(sousTitre!, style: const TextStyle(color: AppCouleurs.texteDoux, fontSize: 13.5)),
            ],
          ],
        );
        if (contraintes.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              texte,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: texte),
            if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        );
      },
    );
  }
}

class CarteSection extends StatelessWidget {
  final String? titre;
  final String? sousTitre;
  final Widget child;
  final Widget? action;
  final EdgeInsets padding;

  const CarteSection({
    super.key,
    this.titre,
    this.sousTitre,
    required this.child,
    this.action,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titre != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titre!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        if (sousTitre != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              sousTitre!,
                              style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class CarteIndicateur extends StatelessWidget {
  final String libelle;
  final String valeur;
  final String? detail;
  final IconData icone;
  final Color couleur;

  const CarteIndicateur({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.icone,
    this.detail,
    this.couleur = AppCouleurs.bleu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: couleur, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(valeur, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(libelle, style: const TextStyle(fontSize: 12.5, color: AppCouleurs.texteDoux)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, style: TextStyle(fontSize: 11, color: couleur, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class Pastille extends StatelessWidget {
  final String texte;
  final Color couleur;

  const Pastille(this.texte, {super.key, this.couleur = AppCouleurs.bleu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: couleur),
      ),
    );
  }
}

class EtatVide extends StatelessWidget {
  final String message;
  final IconData icone;
  final Widget? action;

  const EtatVide({
    super.key,
    required this.message,
    this.icone = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 42, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppCouleurs.texteDoux),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class ChampRecherche extends StatelessWidget {
  final TextEditingController controleur;
  final String hint;
  final ValueChanged<String> onChanged;

  const ChampRecherche({
    super.key,
    required this.controleur,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: TextField(
        controller: controleur,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          suffixIcon: controleur.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    controleur.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class BarreProgression extends StatelessWidget {
  final double valeur;
  final Color couleur;
  final double hauteur;

  const BarreProgression({
    super.key,
    required this.valeur,
    this.couleur = AppCouleurs.teal,
    this.hauteur = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: LinearProgressIndicator(
        value: valeur.clamp(0, 1),
        minHeight: hauteur,
        backgroundColor: const Color(0xFFE2E8F0),
        valueColor: AlwaysStoppedAnimation(couleur),
      ),
    );
  }
}
