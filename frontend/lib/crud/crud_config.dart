import 'package:flutter/material.dart';

import '../state/app_state.dart';

enum TypeChamp { texte, nombre, decimal, booleen, liste, listeMultiple, date, motDePasse }

class OptionChamp {
  final dynamic valeur;
  final String libelle;

  const OptionChamp(this.valeur, this.libelle);
}

class ChampFormulaire {
  final String cle;
  final String libelle;
  final TypeChamp type;
  final bool obligatoire;
  final String? aide;
  final List<OptionChamp> Function(AppState)? options;
  final bool autoriserVide;
  final dynamic valeurInitiale;
  final DateTime? dateMin;
  final DateTime? dateMax;

  const ChampFormulaire({
    required this.cle,
    required this.libelle,
    this.type = TypeChamp.texte,
    this.obligatoire = true,
    this.aide,
    this.options,
    this.autoriserVide = false,
    this.valeurInitiale,
    this.dateMin,
    this.dateMax,
  });
}

class ColonneTableau {
  final String libelle;
  final String Function(Map<String, dynamic>, AppState) valeur;
  final double? largeur;
  final bool badge;
  final bool numerique;

  const ColonneTableau({
    required this.libelle,
    required this.valeur,
    this.largeur,
    this.badge = false,
    this.numerique = false,
  });
}

/// Filtre à choix unique affiché au-dessus d'un tableau générique.
///
/// La valeur `null` correspond à « Tous » : le filtre est alors inactif.
class FiltreCrud {
  final String libelle;

  /// Valeurs proposées dans le menu (sans valeur `null`).
  final List<OptionChamp> Function(AppState app) options;

  /// Indique si [ligne] correspond à la valeur choisie.
  final bool Function(Map<String, dynamic> ligne, AppState app, dynamic valeur)
  correspond;

  const FiltreCrud({
    required this.libelle,
    required this.options,
    required this.correspond,
  });

  /// Filtre d'égalité simple : [valeur] extrait la valeur de la ligne.
  FiltreCrud.egal({
    required this.libelle,
    required this.options,
    required dynamic Function(Map<String, dynamic> ligne, AppState app) valeur,
  }) : correspond = ((ligne, app, choix) => valeur(ligne, app) == choix);
}

/// Boutons « Modèle Excel » et « Importer » affichés dans un CRUD générique.
class ImportationCrud {
  final String modeleEndpoint;
  final String importEndpoint;
  final String nomModele;
  final String libelleImport;

  const ImportationCrud({
    required this.modeleEndpoint,
    required this.importEndpoint,
    required this.nomModele,
    this.libelleImport = 'Importer',
  });
}

class ConfigCrud {
  final String titre;
  final String sousTitre;
  final String endpoint;
  final String nomSingulier;
  final List<ColonneTableau> colonnes;
  final List<ChampFormulaire> champs;
  final List<Map<String, dynamic>> Function(AppState) source;
  final String? triCle;
  final bool utilisateurs;

  /// Place la colonne d'actions (modifier/supprimer) en tête du tableau.
  /// Utile pour les tables larges, où les actions seraient hors écran.
  final bool actionsEnPremier;

  /// Indique que [nomSingulier] est féminin, pour accorder les libellés et
  /// messages (« Nouvelle inscription », « créée avec succès », …).
  final bool feminin;

  /// Libellé du bouton de création, si « Nouveau/Nouvelle `nomSingulier` »
  /// ne convient pas (ex. « Nouvel ECUE »).
  final String? libelleCreation;

  /// Import Excel facultatif (modèle + envoi d'un classeur).
  final ImportationCrud? importation;

  /// Filtres à choix unique affichés au-dessus du tableau (année, filière…).
  final List<FiltreCrud> filtres;

  /// Action supplémentaire affichée dans l'en-tête (ex. copie d'UE).
  final String? libelleAction;
  final IconData? iconeAction;
  final Future<void> Function(BuildContext context, AppState app)? action;

  const ConfigCrud({
    required this.titre,
    required this.sousTitre,
    required this.endpoint,
    required this.nomSingulier,
    required this.colonnes,
    required this.champs,
    required this.source,
    this.triCle,
    this.utilisateurs = false,
    this.actionsEnPremier = false,
    this.feminin = false,
    this.libelleCreation,
    this.importation,
    this.filtres = const [],
    this.libelleAction,
    this.iconeAction,
    this.action,
  });

  String get articleIndefini => feminin ? 'une' : 'un';

  String get libelleAjout =>
      libelleCreation ?? '${feminin ? 'Nouvelle' : 'Nouveau'} $nomSingulier';

  /// Suffixe d'accord pour les participes passés (créé/créée, supprimé/supprimée).
  String get accord => feminin ? 'e' : '';
}
