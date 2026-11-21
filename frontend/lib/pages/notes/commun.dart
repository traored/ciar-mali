import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Sélecteur de semestre commun aux pages du module « Gestion des notes ».
///
/// Avec [tous], le sélecteur propose l'ensemble des semestres, même ceux hors
/// du périmètre habituel de l'utilisateur. [liste] permet de fournir un
/// sous-ensemble explicite (par exemple les semestres d'affectation d'un
/// enseignant) ; il prime alors sur [tous].
Widget selecteurSemestre(
  AppState app,
  int? valeur,
  ValueChanged<int?> onChanged, {
  double largeur = 230,
  bool tous = false,
  List<Map<String, dynamic>>? liste,
}) {
  final semestres = liste ??
      (tous && app.semestresTous.isNotEmpty
          ? app.semestresTous
          : app.semestres);
  return SizedBox(
    width: largeur,
    child: DropdownButtonFormField<int>(
      key: ValueKey<int?>(valeur),
      initialValue: semestres.any((s) => s['id'] == valeur) ? valeur : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Semestre', isDense: true),
      items: [
        for (final semestre in semestres)
          DropdownMenuItem(
            value: semestre['id'] as int,
            child: Text(
              '${semestre['nom']} · ${semestre['annee']}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

Widget selecteurSession(
  int? valeur,
  ValueChanged<int?> onChanged, {
  double largeur = 150,
}) {
  return SizedBox(
    width: largeur,
    child: DropdownButtonFormField<int>(
      initialValue: valeur ?? 1,
      decoration: const InputDecoration(labelText: 'Session', isDense: true),
      items: const [
        DropdownMenuItem(value: 1, child: Text('Session 1')),
        DropdownMenuItem(value: 2, child: Text('Session 2')),
      ],
      onChanged: onChanged,
    ),
  );
}

Widget selecteurNiveau(
  AppState app,
  int? valeur,
  ValueChanged<int?> onChanged, {
  double largeur = 230,
  bool tous = false,
}) {
  final liste = tous && app.niveauxTous.isNotEmpty
      ? app.niveauxTous
      : app.niveaux;
  return SizedBox(
    width: largeur,
    child: DropdownButtonFormField<int?>(
      initialValue: valeur,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Niveau', isDense: true),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Tous les niveaux'),
        ),
        for (final niveau in liste)
          DropdownMenuItem<int?>(
            value: niveau['id'] as int,
            child: Text(
              '${niveau['nom']} · ${niveau['filiere_code']}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

Widget selecteurFiliere(
  AppState app,
  int? valeur,
  ValueChanged<int?> onChanged, {
  double largeur = 230,
}) {
  return SizedBox(
    width: largeur,
    child: DropdownButtonFormField<int?>(
      key: ValueKey<int?>(valeur),
      initialValue: app.filieres.any((filiere) => filiere['id'] == valeur)
          ? valeur
          : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Filière', isDense: true),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Toutes les filières'),
        ),
        for (final filiere in app.filieres)
          DropdownMenuItem<int?>(
            value: filiere['id'] as int,
            child: Text(
              '${filiere['code']} · ${filiere['nom']}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

String noteTexte(dynamic valeur, {int decimales = 2}) {
  if (valeur == null) return '—';
  final nombre = valeur is num ? valeur.toDouble() : double.tryParse('$valeur');
  if (nombre == null) return '$valeur';
  return nombre.toStringAsFixed(decimales).replaceAll('.', ',');
}

Color couleurStatut(String statut) {
  switch (statut.toLowerCase()) {
    case 'validé':
    case 'validée':
    case 'admis':
    case 'diplômé':
      return AppCouleurs.vert;
    case 'partiellement validé':
    case 'rattrapage':
      return AppCouleurs.ambre;
    case 'ajourné':
    case 'non validé':
    case 'non validée':
    case 'abandon':
      return AppCouleurs.rouge;
    case 'inscrit':
    case 'redoublant':
      return AppCouleurs.bleu;
    case 'en attente':
      return AppCouleurs.texteDoux;
    default:
      return AppCouleurs.violet;
  }
}

Future<void> telechargerDepuisApi(
  BuildContext context,
  AppState app,
  String chemin,
  String nomFichier,
  String mime, {
  Map<String, dynamic>? parametres,
}) async {
  try {
    final octets = await app.api.octets(chemin, parametres);
    telechargerOctets(octets, nomFichier, mime);
    if (context.mounted)
      afficherMessage(context, 'Téléchargement de $nomFichier lancé.');
  } on ApiException catch (e) {
    if (context.mounted) afficherMessage(context, e.message, erreur: true);
  } catch (e) {
    if (context.mounted) afficherMessage(context, e.toString(), erreur: true);
  }
}

/// Carte blanche utilisée pour les tableaux du module notes.
class CarteTableau extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const CarteTableau({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: child,
    );
  }
}
