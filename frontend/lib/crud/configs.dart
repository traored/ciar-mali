import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'crud_config.dart';
const _jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

List<OptionChamp> _joursOptions() => [
  for (var i = 0; i < _jours.length; i++) OptionChamp(i, _jours[i]),
];

String _jour(int? valeur) =>
    (valeur != null && valeur >= 0 && valeur < 7) ? _jours[valeur] : '—';

/// Années académiques disponibles, de la plus récente à la plus ancienne.
List<OptionChamp> _optionsAnnees(AppState app) {
  final annees = <String>{};
  for (final semestre in app.semestres) {
    final annee = '${semestre['annee'] ?? ''}';
    if (annee.isNotEmpty) annees.add(annee);
  }
  final liste = annees.toList()..sort((a, b) => b.compareTo(a));
  return [for (final annee in liste) OptionChamp(annee, annee)];
}

ConfigCrud configDepartements(AppState app) => ConfigCrud(
  titre: 'Départements',
  sousTitre: 'Organisation administrative et scientifique de l’université.',
  endpoint: '/departements',
  nomSingulier: 'département',
  source: (app) => app.departements,
  triCle: 'nom',
  colonnes: [
    ColonneTableau(libelle: 'Code', valeur: _code, largeur: 90),
    ColonneTableau(libelle: 'Nom', valeur: _nom, largeur: 230),
    ColonneTableau(libelle: 'Responsable', valeur: _chef, largeur: 200),
    ColonneTableau(libelle: 'Email', valeur: _email, largeur: 220),
  ],
  champs: [
    ChampFormulaire(cle: 'code', libelle: 'Code', aide: 'Ex. INFO'),
    ChampFormulaire(cle: 'nom', libelle: 'Nom du département'),
    ChampFormulaire(cle: 'chef', libelle: 'Responsable', obligatoire: false),
    ChampFormulaire(cle: 'email', libelle: 'Email', obligatoire: false),
  ],
);

ConfigCrud configFilieres(AppState app) => ConfigCrud(
  titre: 'Filières',
  sousTitre: 'Parcours de formation rattachés aux départements.',
  endpoint: '/filieres',
  nomSingulier: 'filière',
  feminin: true,
  source: (app) => app.filieres,
  triCle: 'code',
  colonnes: [
    ColonneTableau(libelle: 'Code', valeur: _code, largeur: 100),
    ColonneTableau(libelle: 'Filière', valeur: _nom, largeur: 260),
    ColonneTableau(
      libelle: 'Département',
      valeur: (l, app) => app.nomDepartement(l['departement_id']),
      largeur: 220,
    ),
  ],
  champs: [
    ChampFormulaire(cle: 'code', libelle: 'Code', aide: 'Ex. GL'),
    ChampFormulaire(cle: 'nom', libelle: 'Nom de la filière'),
    ChampFormulaire(
      cle: 'departement_id',
      libelle: 'Département',
      type: TypeChamp.liste,
      options: (app) => [
        for (final d in app.departements)
          OptionChamp(d['id'], '${d['code']} — ${d['nom']}'),
      ],
    ),
  ],
);

ConfigCrud configNiveaux(AppState app) => ConfigCrud(
  titre: 'Niveaux',
  sousTitre: 'Niveaux d’études (Licence 1, Licence 2, Master…).',
  endpoint: '/niveaux',
  nomSingulier: 'niveau',
  source: (app) => app.niveaux,
  triCle: 'ordre',
  colonnes: [
    ColonneTableau(libelle: 'Niveau', valeur: _nom, largeur: 160),
    ColonneTableau(
      libelle: 'Ordre',
      valeur: (l, app) => '${l['ordre'] ?? ''}',
      largeur: 80,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Filière',
      valeur: (l, app) => app.libelleFiliere(l['filiere_id']),
      largeur: 260,
    ),
    ColonneTableau(
      libelle: 'Département',
      valeur: (l, app) {
        final filiere = app.filieres.where((f) => f['id'] == l['filiere_id']);
        return filiere.isEmpty
            ? '—'
            : app.nomDepartement(filiere.first['departement_id']);
      },
      largeur: 220,
    ),
  ],
  champs: [
    ChampFormulaire(
      cle: 'nom',
      libelle: 'Nom du niveau',
      aide: 'Ex. Licence 1',
    ),
    ChampFormulaire(cle: 'ordre', libelle: 'Ordre', type: TypeChamp.nombre),
    ChampFormulaire(
      cle: 'filiere_id',
      libelle: 'Filière',
      type: TypeChamp.liste,
      options: (app) => [
        for (final f in app.filieres)
          OptionChamp(f['id'], '${f['code']} — ${f['nom']}'),
      ],
    ),
  ],
);

ConfigCrud configGroupes(AppState app) => ConfigCrud(
  titre: 'Groupes',
  sousTitre: 'Groupes d’étudiants utilisés pour la planification des séances.',
  endpoint: '/groupes',
  nomSingulier: 'groupe',
  source: (app) => app.groupes,
  triCle: 'nom',
  colonnes: [
    ColonneTableau(libelle: 'Groupe', valeur: _nom, largeur: 150),
    ColonneTableau(
      libelle: 'Niveau',
      valeur: (l, app) => app.libelleNiveau(l['niveau_id']),
      largeur: 220,
    ),
    ColonneTableau(
      libelle: 'Filière',
      valeur: (l, app) =>
          '${l['filiere_nom'] ?? app.nomFiliere(l['filiere_id'])}',
      largeur: 220,
    ),
    ColonneTableau(
      libelle: 'Effectif',
      valeur: (l, app) => '${l['effectif'] ?? ''}',
      largeur: 90,
      numerique: true,
    ),
  ],
  champs: [
    ChampFormulaire(cle: 'nom', libelle: 'Nom du groupe', aide: 'Ex. GL-L1-A'),
    ChampFormulaire(
      cle: 'effectif',
      libelle: 'Effectif',
      type: TypeChamp.nombre,
    ),
    ChampFormulaire(
      cle: 'niveau_id',
      libelle: 'Niveau',
      type: TypeChamp.liste,
      options: (app) => [
        for (final n in app.niveaux)
          OptionChamp(n['id'], app.libelleNiveau(n['id'])),
      ],
    ),
  ],
);

ConfigCrud configEnseignants(AppState app) => ConfigCrud(
  titre: 'Enseignants',
  sousTitre:
      'Corps enseignant, volumes horaires et départements de rattachement.',
  endpoint: '/enseignants',
  nomSingulier: 'enseignant',
  source: (app) => app.enseignants,
  triCle: 'nom_complet',
  actionsEnPremier: true,
  colonnes: [
    ColonneTableau(
      libelle: 'Enseignant',
      valeur: (l, app) =>
          '${l['nom_affichage'] ?? l['nom_complet'] ?? '${l['prenom']} ${l['nom']}'}',
      largeur: 230,
    ),
    ColonneTableau(
      libelle: 'Matricule',
      valeur: (l, app) => '${l['matricule'] ?? '—'}',
      largeur: 120,
    ),
    ColonneTableau(
      libelle: 'Grade',
      valeur: (l, app) => '${l['grade'] ?? 'Master'}',
      largeur: 190,
    ),
    ColonneTableau(
      libelle: 'Statut',
      valeur: (l, app) => '${l['statut'] ?? 'Permanent'}',
      largeur: 110,
      badge: true,
    ),
    ColonneTableau(
      libelle: 'Naissance',
      valeur: (l, app) {
        final date = _dateCourte(l['date_naissance']);
        final lieu = '${l['lieu_naissance'] ?? ''}'.trim();
        if (date.isEmpty && lieu.isEmpty) return '—';
        return lieu.isEmpty ? date : '$date · $lieu';
      },
      largeur: 220,
    ),
    ColonneTableau(libelle: 'Email', valeur: _email, largeur: 230),
    ColonneTableau(
      libelle: 'Département',
      valeur: (l, app) =>
          '${l['departement_nom'] ?? app.nomDepartement(l['departement_id'])}',
      largeur: 200,
    ),
    ColonneTableau(
      libelle: 'Heures max',
      valeur: (l, app) => '${l['heures_max']} h',
      largeur: 100,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Compte',
      valeur: (l, app) => l['actif'] == true ? 'Actif' : 'Inactif',
      largeur: 90,
      badge: true,
    ),
  ],
  champs: [
    ChampFormulaire(cle: 'prenom', libelle: 'Prénom'),
    ChampFormulaire(cle: 'nom', libelle: 'Nom'),
    ChampFormulaire(cle: 'email', libelle: 'Email'),
    ChampFormulaire(cle: 'telephone', libelle: 'Téléphone', obligatoire: false),
    ChampFormulaire(
      cle: 'matricule',
      libelle: 'Matricule',
      obligatoire: false,
      aide: 'Facultatif — numéro matricule de l’enseignant.',
    ),
    ChampFormulaire(
      cle: 'date_naissance',
      libelle: 'Date de naissance',
      type: TypeChamp.date,
      obligatoire: false,
      dateMin: DateTime(1940),
      dateMax: DateTime(2010),
    ),
    ChampFormulaire(
      cle: 'lieu_naissance',
      libelle: 'Lieu de naissance',
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'statut',
      libelle: 'Statut',
      type: TypeChamp.liste,
      valeurInitiale: 'Permanent',
      options: (app) => const [
        OptionChamp('Permanent', 'Permanent'),
        OptionChamp('Vacataire', 'Vacataire'),
      ],
    ),
    ChampFormulaire(
      cle: 'grade',
      libelle: 'Grade / Diplôme',
      type: TypeChamp.liste,
      valeurInitiale: 'Master',
      options: (app) => const [
        OptionChamp('Professeur', 'Professeur (Pr)'),
        OptionChamp('Maître de Conférences', 'Maître de Conférences (Dr)'),
        OptionChamp('Maître Assistant', 'Maître Assistant (Dr)'),
        OptionChamp('Assistant', 'Assistant (M.)'),
        OptionChamp('Ingénieur', 'Ingénieur (Ing.)'),
        OptionChamp('Master', 'Master (M.)'),
      ],
    ),
    ChampFormulaire(
      cle: 'departement_id',
      libelle: 'Département',
      type: TypeChamp.liste,
      obligatoire: false,
      autoriserVide: true,
      options: (app) => [
        const OptionChamp(null, '— Aucun —'),
        for (final d in app.departements)
          OptionChamp(d['id'], '${d['code']} — ${d['nom']}'),
      ],
    ),
    ChampFormulaire(
      cle: 'heures_max',
      libelle: 'Heures maximum',
      type: TypeChamp.nombre,
    ),
    ChampFormulaire(
      cle: 'actif',
      libelle: 'Enseignant actif',
      type: TypeChamp.booleen,
      obligatoire: false,
    ),
  ],
);

ConfigCrud configSalles(AppState app) => ConfigCrud(
  titre: 'Salles',
  sousTitre: 'Salles, amphithéâtres et laboratoires disponibles.',
  endpoint: '/salles',
  nomSingulier: 'salle',
  feminin: true,
  source: (app) => app.salles,
  triCle: 'nom',
  colonnes: [
    ColonneTableau(libelle: 'Salle', valeur: _nom, largeur: 160),
    ColonneTableau(libelle: 'Bâtiment', valeur: _batiment, largeur: 190),
    ColonneTableau(
      libelle: 'Capacité',
      valeur: (l, app) => '${l['capacite']} places',
      largeur: 110,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Type',
      valeur: (l, app) => '${l['type_salle'] ?? ''}',
      largeur: 130,
      badge: true,
    ),
  ],
  champs: [
    ChampFormulaire(cle: 'nom', libelle: 'Nom de la salle'),
    ChampFormulaire(cle: 'batiment', libelle: 'Bâtiment', obligatoire: false),
    ChampFormulaire(
      cle: 'capacite',
      libelle: 'Capacité',
      type: TypeChamp.nombre,
    ),
    ChampFormulaire(
      cle: 'type_salle',
      libelle: 'Type de salle',
      type: TypeChamp.liste,
      options: (app) => _optionsTypeSalle(),
    ),
  ],
);

ConfigCrud configCreneaux(AppState app) => ConfigCrud(
  titre: 'Créneaux',
  sousTitre:
      'Plages horaires utilisées par le générateur et les séances manuelles.',
  endpoint: '/creneaux',
  nomSingulier: 'créneau',
  source: (app) => app.creneaux,
  triCle: 'ordre',
  colonnes: [
    ColonneTableau(
      libelle: 'Jour',
      valeur: (l, app) => _jour(l['jour'] as int?),
      largeur: 110,
    ),
    ColonneTableau(
      libelle: 'Horaire',
      valeur: (l, app) => '${l['debut']} – ${l['fin']}',
      largeur: 160,
    ),
    ColonneTableau(
      libelle: 'Durée',
      valeur: (l, app) => '${l['duree'] ?? 2} h',
      largeur: 90,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Libellé',
      valeur: (l, app) => '${l['libelle'] ?? ''}',
      largeur: 200,
    ),
  ],
  champs: [
    ChampFormulaire(
      cle: 'jour',
      libelle: 'Jour',
      type: TypeChamp.liste,
      options: (app) => _optionsJour(),
    ),
    ChampFormulaire(
      cle: 'debut',
      libelle: 'Heure de début',
      aide: 'Format 08:00',
    ),
    ChampFormulaire(cle: 'fin', libelle: 'Heure de fin', aide: 'Format 10:00'),
    ChampFormulaire(cle: 'libelle', libelle: 'Libellé', obligatoire: false),
  ],
);

ConfigCrud configSemestres(AppState app) => ConfigCrud(
  titre: 'Semestres',
  sousTitre: 'Périodes académiques, semaines de cours et semestre actif.',
  endpoint: '/semestres',
  nomSingulier: 'semestre',
  source: (app) => app.semestres,
  triCle: 'nom',
  filtres: [
    FiltreCrud.egal(
      libelle: 'Année',
      options: _optionsAnnees,
      valeur: (ligne, app) => '${ligne['annee'] ?? ''}',
    ),
  ],
  colonnes: [
    ColonneTableau(libelle: 'Semestre', valeur: _nom, largeur: 160),
    ColonneTableau(
      libelle: 'Année',
      valeur: (l, app) => '${l['annee'] ?? ''}',
      largeur: 110,
    ),
    ColonneTableau(
      libelle: 'Période',
      valeur: (l, app) =>
          '${_dateCourte(l['date_debut'])} → ${_dateCourte(l['date_fin'])}',
      largeur: 210,
    ),
    ColonneTableau(
      libelle: 'Semaines',
      valeur: (l, app) => '${l['semaines']}',
      largeur: 90,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Statut',
      valeur: (l, app) => l['actif'] == true ? 'Actif' : 'Inactif',
      largeur: 90,
      badge: true,
    ),
  ],
  champs: [
    ChampFormulaire(
      cle: 'nom',
      libelle: 'Nom du semestre',
      aide: 'Ex. Semestre 1',
    ),
    ChampFormulaire(
      cle: 'annee',
      libelle: 'Année académique',
      aide: 'Ex. 2025-2026',
    ),
    ChampFormulaire(
      cle: 'date_debut',
      libelle: 'Date de début',
      type: TypeChamp.date,
    ),
    ChampFormulaire(
      cle: 'date_fin',
      libelle: 'Date de fin',
      type: TypeChamp.date,
    ),
    ChampFormulaire(
      cle: 'semaines',
      libelle: 'Nombre de semaines',
      type: TypeChamp.nombre,
    ),
    ChampFormulaire(
      cle: 'actif',
      libelle: 'Semestre actif',
      type: TypeChamp.booleen,
      obligatoire: false,
    ),
  ],
);

Future<void> _ouvrirCopieUE(BuildContext context, AppState app) async {
  if (app.semestres.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aucun semestre disponible pour la copie.')),
    );
    return;
  }
  int? source = app.semestres.first['id'] as int?;
  int? cible = app.semestres.length > 1
      ? app.semestres[1]['id'] as int?
      : app.semestres.first['id'] as int?;
  final valide = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialogue) => AlertDialog(
        title: const Text('Copier les UE et ECUE'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reprenez la structure pédagogique d’un semestre vers un autre. '
                'Les UE et ECUE conservent leurs codes, intitulés, crédits et volumes. '
                'Les UE déjà présentes (même code) dans le semestre cible sont ignorées. '
                'Les affectations ne sont pas copiées : définissez-les pour le semestre cible.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: source,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Semestre source'),
                items: [
                  for (final s in app.semestres)
                    DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(
                        app.libelleSemestre(s['id']),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (valeur) => setStateDialogue(() => source = valeur),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: cible,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Semestre cible'),
                items: [
                  for (final s in app.semestres)
                    DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(
                        app.libelleSemestre(s['id']),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (valeur) => setStateDialogue(() => cible = valeur),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: source == null || cible == null || source == cible
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Copier'),
          ),
        ],
      ),
    ),
  );
  if (valide != true || source == null || cible == null) return;
  try {
    final reponse = await app.api.post('/ues/copier', {
      'semestre_source_id': source,
      'semestre_cible_id': cible,
    });
    await app.rafraichir();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${reponse['message'] ?? 'Copie effectuée.'}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copie impossible : $e')),
      );
    }
  }
}

ConfigCrud configUE(AppState app) => ConfigCrud(
  titre: 'Unités d’enseignement',
  sousTitre: 'UE rattachées à un semestre, un niveau et un département. Le crédit est la somme des crédits de ses ECUE.',
  endpoint: '/ues',
  nomSingulier: 'UE',
  feminin: true,
  source: (app) => app.ues,
  triCle: 'code',
  filtres: [
    FiltreCrud.egal(
      libelle: 'Année',
      options: _optionsAnnees,
      valeur: (ligne, app) => app.anneeSemestre(ligne['semestre_id']),
    ),
  ],
  libelleAction: 'Copier les UE',
  iconeAction: Icons.copy_all_outlined,
  action: _ouvrirCopieUE,
  actionsEnPremier: true,
  colonnes: [
    ColonneTableau(libelle: 'Code', valeur: _code, largeur: 120),
    ColonneTableau(libelle: 'Intitulé', valeur: _nom, largeur: 290),
    ColonneTableau(
      libelle: 'Crédits',
      valeur: (l, app) => '${l['credits']}',
      largeur: 80,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Niveaux',
      valeur: (l, app) {
        final noms = (l['niveaux_noms'] as List?)?.cast<String>() ?? const [];
        if (noms.isNotEmpty) return noms.join(' · ');
        return app.libelleNiveau(l['niveau_id']);
      },
      largeur: 260,
    ),
    ColonneTableau(
      libelle: 'Semestre',
      valeur: (l, app) => app.libelleSemestre(l['semestre_id']),
      largeur: 190,
    ),
  ],
  champs: [
    ChampFormulaire(
      cle: 'code',
      libelle: 'Code de l’UE',
      aide: 'Ex. UE-INF101',
    ),
    ChampFormulaire(cle: 'nom', libelle: 'Intitulé de l’UE'),
    ChampFormulaire(
      cle: 'credits',
      libelle: 'Crédits',
      type: TypeChamp.nombre,
      aide: 'Calculé automatiquement : somme des crédits des ECUE rattachés.',
    ),
    ChampFormulaire(
      cle: 'semestre_id',
      libelle: 'Semestre',
      type: TypeChamp.liste,
      options: (app) => [
        for (final s in app.semestres)
          OptionChamp(s['id'], app.libelleSemestre(s['id'])),
      ],
    ),
    ChampFormulaire(
      cle: 'niveau_ids',
      libelle: 'Niveaux (filières)',
      type: TypeChamp.listeMultiple,
      aide:
          'Sélectionnez une ou plusieurs filières du même niveau d’études pour mutualiser l’UE.',
      options: (app) => [
        for (final n in app.niveaux)
          OptionChamp(n['id'], app.libelleNiveau(n['id'])),
      ],
    ),
    ChampFormulaire(
      cle: 'departement_id',
      libelle: 'Département',
      type: TypeChamp.liste,
      obligatoire: false,
      autoriserVide: true,
      options: (app) => [
        const OptionChamp(null, '— Aucun —'),
        for (final d in app.departements)
          OptionChamp(d['id'], '${d['code']} — ${d['nom']}'),
      ],
    ),
  ],
);

ConfigCrud configECUE(AppState app) => ConfigCrud(
  titre: 'ECUE',
  sousTitre: 'Éléments constitutifs d’UE, crédits (= coefficient) et volumes horaires CM / TD / TP.',
  endpoint: '/ecues',
  nomSingulier: 'ECUE',
  libelleCreation: 'Nouvel ECUE',
  source: (app) => app.ecues,
  triCle: 'code',
  filtres: [
    FiltreCrud(
      libelle: 'Année',
      options: _optionsAnnees,
      correspond: (ligne, app, choix) {
        final annee = '${ligne['annee'] ?? ''}';
        final effective = annee.isNotEmpty
            ? annee
            : app.anneeSemestre(ligne['semestre_id']);
        return effective == choix;
      },
    ),
  ],
  actionsEnPremier: true,
  colonnes: [
    ColonneTableau(libelle: 'Code', valeur: _code, largeur: 110),
    ColonneTableau(libelle: 'Intitulé', valeur: _nom, largeur: 280),
    ColonneTableau(
      libelle: 'Crédits',
      valeur: (l, app) => '${l['credits'] ?? 1}',
      largeur: 80,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'UE',
      valeur: (l, app) {
        final ue = app.ues.where((u) => u['id'] == l['ue_id']);
        if (ue.isEmpty) return app.libelleUE(l['ue_id']);
        final u = ue.first;
        return '${u['code']} — ${u['nom']} — ${app.libelleSemestre(u['semestre_id'])}';
      },
      largeur: 360,
    ),
    ColonneTableau(
      libelle: 'CM',
      valeur: (l, app) => '${l['heures_cm']} h',
      largeur: 70,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'TD',
      valeur: (l, app) => '${l['heures_td']} h',
      largeur: 70,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'TP',
      valeur: (l, app) => '${l['heures_tp']} h',
      largeur: 70,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'Total',
      valeur: (l, app) => '${l['total_heures']} h',
      largeur: 80,
      numerique: true,
    ),
  ],
  champs: [
    ChampFormulaire(
      cle: 'code',
      libelle: 'Code de l’ECUE',
      aide: 'Ex. INF1011',
    ),
    ChampFormulaire(cle: 'nom', libelle: 'Intitulé de l’ECUE'),
    ChampFormulaire(
      cle: 'credits',
      libelle: 'Crédits (coefficient)',
      type: TypeChamp.nombre,
      valeurInitiale: 1,
      aide: 'Le coefficient de l’ECUE est égal à ses crédits. La somme des crédits des ECUE met à jour le crédit de l’UE.',
    ),
    ChampFormulaire(
      cle: 'ue_id',
      libelle: 'UE de rattachement',
      type: TypeChamp.liste,
      options: (app) => [
        for (final u in app.ues)
          OptionChamp(
            u['id'],
            '${u['code']} — ${u['nom']} — ${app.libelleSemestre(u['semestre_id'])}',
          ),
      ],
    ),
    ChampFormulaire(
      cle: 'heures_cm',
      libelle: 'Heures CM',
      type: TypeChamp.nombre,
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'heures_td',
      libelle: 'Heures TD',
      type: TypeChamp.nombre,
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'heures_tp',
      libelle: 'Heures TP',
      type: TypeChamp.nombre,
      obligatoire: false,
    ),
  ],
);

ConfigCrud configAffectations(AppState app) => ConfigCrud(
  titre: 'Affectations',
  sousTitre: 'Qui enseigne quoi, à quel groupe, et pour combien d’heures.',
  endpoint: '/affectations',
  nomSingulier: 'affectation',
  feminin: true,
  source: (app) => app.affectations,
  triCle: 'enseignant_id',
  filtres: [
    FiltreCrud.egal(
      libelle: 'Année',
      options: _optionsAnnees,
      valeur: (ligne, app) => app.anneeSemestre(ligne['semestre_id']),
    ),
  ],
  actionsEnPremier: true,
  colonnes: [
    ColonneTableau(
      libelle: 'Enseignant',
      valeur: (l, app) => app.nomEnseignant(l['enseignant_id']),
      largeur: 190,
    ),
    ColonneTableau(
      libelle: 'Semestre',
      valeur: (l, app) => app.libelleSemestre(l['semestre_id']),
      largeur: 160,
    ),
    ColonneTableau(
      libelle: 'ECUE',
      valeur: (l, app) => app.libelleECUE(l['ecue_id']),
      largeur: 260,
    ),
    ColonneTableau(
      libelle: 'Groupe',
      valeur: (l, app) => app.libelleGroupe(l['groupe_id']),
      largeur: 150,
    ),
    ColonneTableau(
      libelle: 'CM',
      valeur: (l, app) => '${l['heures_cm']} h',
      largeur: 65,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'TD',
      valeur: (l, app) => '${l['heures_td']} h',
      largeur: 65,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'TP',
      valeur: (l, app) => '${l['heures_tp']} h',
      largeur: 65,
      numerique: true,
    ),
    ColonneTableau(
      libelle: 'CM commun',
      valeur: (l, app) => l['cm_commun'] == true ? 'Oui' : 'Non',
      largeur: 100,
      badge: true,
    ),
  ],
  champs: [
    ChampFormulaire(
      cle: 'enseignant_id',
      libelle: 'Enseignant',
      type: TypeChamp.liste,
      options: (app) => [
        for (final e in app.enseignants)
          OptionChamp(e['id'], '${e['nom_affichage'] ?? e['nom_complet']}'),
      ],
    ),
    ChampFormulaire(
      cle: 'ecue_id',
      libelle: 'ECUE',
      aide: 'Le semestre de l’affectation est celui de l’ECUE sélectionné.',
      type: TypeChamp.liste,
      options: (app) => [
        for (final e in app.ecues)
          OptionChamp(e['id'], app.libelleECUE(e['id'])),
      ],
    ),
    ChampFormulaire(
      cle: 'groupe_id',
      libelle: 'Groupe',
      type: TypeChamp.liste,
      options: (app) => [
        for (final g in app.groupes)
          OptionChamp(g['id'], app.libelleGroupe(g['id'])),
      ],
    ),
    ChampFormulaire(
      cle: 'heures_cm',
      libelle: 'Heures CM',
      type: TypeChamp.nombre,
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'heures_td',
      libelle: 'Heures TD',
      type: TypeChamp.nombre,
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'heures_tp',
      libelle: 'Heures TP',
      type: TypeChamp.nombre,
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'cm_commun',
      libelle: 'Mutualiser le CM entre les groupes du niveau',
      type: TypeChamp.booleen,
      obligatoire: false,
    ),
  ],
);

ConfigCrud configUtilisateurs(AppState app) => ConfigCrud(
  titre: 'Utilisateurs',
  sousTitre: 'Comptes, rôles et permissions d’accès à l’application.',
  endpoint: '/utilisateurs',
  nomSingulier: 'utilisateur',
  source: (app) => app.utilisateurs,
  triCle: 'identifiant',
  utilisateurs: true,
  colonnes: [
    ColonneTableau(
      libelle: 'Identifiant',
      valeur: (l, app) => '${l['identifiant']}',
      largeur: 140,
    ),
    ColonneTableau(
      libelle: 'Nom',
      valeur: (l, app) => '${l['nom_complet'] ?? ''}',
      largeur: 200,
    ),
    ColonneTableau(
      libelle: 'Rôle',
      valeur: (l, app) => '${l['role']}',
      largeur: 130,
      badge: true,
    ),
    ColonneTableau(
      libelle: 'Statut',
      valeur: (l, app) => l['actif'] == true ? 'Actif' : 'Inactif',
      largeur: 90,
      badge: true,
    ),
  ],
  champs: [
    ChampFormulaire(cle: 'identifiant', libelle: 'Identifiant'),
    ChampFormulaire(
      cle: 'mot_de_passe',
      libelle: 'Mot de passe',
      type: TypeChamp.motDePasse,
      aide: 'Laisser vide pour conserver le mot de passe actuel',
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'nom_complet',
      libelle: 'Nom complet',
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'role',
      libelle: 'Rôle',
      type: TypeChamp.liste,
      options: (app) => _optionsRole(),
    ),
    ChampFormulaire(
      cle: 'actif',
      libelle: 'Compte actif',
      type: TypeChamp.booleen,
      obligatoire: false,
    ),
    ChampFormulaire(
      cle: 'enseignant_id',
      libelle: 'Fiche enseignant liée',
      type: TypeChamp.liste,
      obligatoire: false,
      autoriserVide: true,
      options: (app) => [
        const OptionChamp(null, '— Aucune —'),
        for (final e in app.enseignants)
          OptionChamp(e['id'], '${e['nom_affichage'] ?? e['nom_complet']}'),
      ],
    ),
  ],
);

List<OptionChamp> _optionsTypeSalle() => [
  OptionChamp('Amphi', 'Amphithéâtre'),
  OptionChamp('Salle TD', 'Salle de TD'),
  OptionChamp('Labo', 'Laboratoire'),
  OptionChamp('Salle informatique', 'Salle informatique'),
];

List<OptionChamp> _optionsJour() => _joursOptions();

List<OptionChamp> _optionsRole() => [
  OptionChamp('admin', 'Administrateur'),
  OptionChamp('gestionnaire', 'Gestionnaire'),
  OptionChamp('enseignant', 'Enseignant'),
  OptionChamp('lecteur', 'Lecteur'),
];

String _code(Map<String, dynamic> l, AppState app) => '${l['code'] ?? ''}';
String _nom(Map<String, dynamic> l, AppState app) => '${l['nom'] ?? ''}';

String _chef(Map<String, dynamic> l, AppState app) => '${l['chef'] ?? ''}';
String _email(Map<String, dynamic> l, AppState app) => '${l['email'] ?? ''}';
String _batiment(Map<String, dynamic> l, AppState app) =>
    '${l['batiment'] ?? ''}';

String _dateCourte(dynamic valeur) {
  final texte = '${valeur ?? ''}';
  if (texte.length >= 10) {
    final morceaux = texte.substring(0, 10).split('-');
    if (morceaux.length == 3)
      return '${morceaux[2]}/${morceaux[1]}/${morceaux[0]}';
  }
  return texte;
}
