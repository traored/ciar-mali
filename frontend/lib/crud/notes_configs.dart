import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'crud_config.dart';

const _sexes = ['M', 'F'];
const _statutsInscription = ['Inscrit', 'Redoublant', 'Rattrapage', 'Diplômé', 'Abandon'];
const _typesEvaluation = ['Devoir', 'TP', 'CC', 'Examen'];
const _sessions = [1, 2];
const _decisions = ['ADMIS', 'AJOURNE', 'RATTRAPAGE'];

String _texte(dynamic valeur) => valeur == null ? '—' : '$valeur';

List<OptionChamp> _optionsFilieres(AppState app) => [
      const OptionChamp(null, '— Aucune —'),
      for (final filiere in app.filieres)
        OptionChamp(filiere['id'], '${filiere['code']} — ${filiere['nom']}'),
    ];

List<OptionChamp> _optionsNiveaux(AppState app) => [
      for (final niveau in app.niveaux)
        OptionChamp(niveau['id'], '${niveau['nom']} · ${niveau['filiere_code']}'),
    ];

List<OptionChamp> _optionsGroupes(AppState app) => [
      const OptionChamp(null, '— Aucun —'),
      for (final groupe in app.groupes)
        OptionChamp(groupe['id'], '${groupe['nom']} (${groupe['filiere_code']})'),
    ];

List<OptionChamp> _optionsEtudiants(AppState app) => [
      for (final etudiant in app.etudiantsNotes)
        OptionChamp(
          etudiant['id'],
          '${etudiant['matricule']} — ${etudiant['nom_complet']}',
        ),
    ];

List<OptionChamp> _optionsECUE(AppState app) => [
      for (final ecue in app.ecues)
        OptionChamp(
          ecue['id'],
          '${ecue['code']} — ${ecue['nom']}'
          '${ecue['niveau_nom'] != null && '${ecue['niveau_nom']}'.isNotEmpty ? ' · ${ecue['niveau_nom']}' : ''}',
        ),
    ];

List<OptionChamp> _optionsTexte(List<String> valeurs) =>
    [for (final valeur in valeurs) OptionChamp(valeur, valeur)];

/// Années académiques présentes dans les inscriptions, récentes d'abord.
List<OptionChamp> _optionsAnneesInscriptions(AppState app) {
  final annees = <String>{};
  for (final inscription in app.inscriptionsNotes) {
    final annee = '${inscription['annee'] ?? ''}';
    if (annee.isNotEmpty) annees.add(annee);
  }
  final liste = annees.toList()..sort((a, b) => b.compareTo(a));
  return [for (final annee in liste) OptionChamp(annee, annee)];
}

/// Filières proposées par leur code : les inscriptions n'exposent que celui-ci.
List<OptionChamp> _optionsFilieresCode(AppState app) => [
      for (final filiere in app.filieres)
        OptionChamp(filiere['code'], '${filiere['code']} — ${filiere['nom']}'),
    ];

/// Vrai si l'étudiant [etudiantId] possède une inscription correspondant à
/// [predicat].
bool _inscriptionEtudiant(
  AppState app,
  dynamic etudiantId,
  bool Function(Map<String, dynamic> inscription) predicat,
) {
  return app.inscriptionsNotes.any(
    (inscription) =>
        inscription['etudiant_id'] == etudiantId && predicat(inscription),
  );
}

ConfigCrud configNotesEtudiants(AppState app) => ConfigCrud(
      titre: 'Étudiants',
      sousTitre:
          'Inscriptions administratives, matricules, parcours et historique des étudiants.',
      endpoint: '/notes/etudiants',
      nomSingulier: 'étudiant',
      actionsEnPremier: true,
      importation: const ImportationCrud(
        modeleEndpoint: '/notes/etudiants/modele',
        importEndpoint: '/notes/etudiants/importer',
        nomModele: 'modele_import_etudiants.xlsx',
        libelleImport: 'Importer des étudiants',
      ),
      source: (app) => app.etudiantsNotes,
      triCle: 'nom',
      filtres: [
        FiltreCrud(
          libelle: 'Année',
          options: _optionsAnneesInscriptions,
          correspond: (ligne, app, choix) => _inscriptionEtudiant(
            app,
            ligne['id'],
            (inscription) => '${inscription['annee'] ?? ''}' == choix,
          ),
        ),
        FiltreCrud(
          libelle: 'Filière',
          options: _optionsFilieresCode,
          correspond: (ligne, app, choix) =>
              '${ligne['filiere_code'] ?? ''}' == choix ||
              _inscriptionEtudiant(
                app,
                ligne['id'],
                (inscription) =>
                    '${inscription['filiere_code'] ?? ''}' == choix,
              ),
        ),
        FiltreCrud(
          libelle: 'Niveau',
          options: _optionsNiveaux,
          correspond: (ligne, app, choix) => _inscriptionEtudiant(
            app,
            ligne['id'],
            (inscription) => inscription['niveau_id'] == choix,
          ),
        ),
      ],
      colonnes: [
        ColonneTableau(libelle: 'Matricule', valeur: (l, a) => _texte(l['matricule']), largeur: 135),
        ColonneTableau(libelle: 'Nom complet', valeur: (l, a) => _texte(l['nom_complet']), largeur: 200),
        ColonneTableau(libelle: 'Sexe', valeur: (l, a) => _texte(l['sexe']), largeur: 60),
        ColonneTableau(libelle: 'Filière', valeur: (l, a) => _texte(l['filiere_nom']), largeur: 190),
        ColonneTableau(libelle: 'Téléphone', valeur: (l, a) => _texte(l['telephone']), largeur: 130),
        ColonneTableau(
          libelle: 'Inscriptions',
          valeur: (l, a) => '${l['nb_inscriptions'] ?? 0}',
          numerique: true,
          largeur: 95,
        ),
      ],
      champs: [
        ChampFormulaire(
          cle: 'matricule',
          libelle: 'Matricule',
          obligatoire: false,
          autoriserVide: true,
          aide: 'Laisser vide pour générer automatiquement (ETU-AAAA-0001).',
        ),
        const ChampFormulaire(cle: 'prenom', libelle: 'Prénom'),
        const ChampFormulaire(cle: 'nom', libelle: 'Nom'),
        ChampFormulaire(
          cle: 'sexe',
          libelle: 'Sexe',
          type: TypeChamp.liste,
          options: (app) => _optionsTexte(_sexes),
        ),
        ChampFormulaire(
          cle: 'date_naissance',
          libelle: 'Date de naissance',
          type: TypeChamp.date,
          obligatoire: false,
          dateMin: DateTime(1980),
          dateMax: DateTime(2015),
        ),
        const ChampFormulaire(
          cle: 'lieu_naissance',
          libelle: 'Lieu de naissance',
          obligatoire: false,
        ),
        const ChampFormulaire(cle: 'telephone', libelle: 'Téléphone', obligatoire: false),
        const ChampFormulaire(cle: 'email', libelle: 'Email', obligatoire: false),
        ChampFormulaire(
          cle: 'filiere_id',
          libelle: 'Filière',
          type: TypeChamp.liste,
          obligatoire: false,
          autoriserVide: true,
          options: _optionsFilieres,
        ),
      ],
    );

ConfigCrud configNotesInscriptions(AppState app) => ConfigCrud(
      titre: 'Inscriptions',
      sousTitre: 'Parcours annuel des étudiants par niveau, groupe et statut.',
      endpoint: '/notes/inscriptions',
      nomSingulier: 'inscription',
      feminin: true,
      actionsEnPremier: true,
      importation: const ImportationCrud(
        modeleEndpoint: '/notes/inscriptions/modele',
        importEndpoint: '/notes/inscriptions/importer',
        nomModele: 'modele_import_inscriptions.xlsx',
        libelleImport: 'Importer des inscriptions',
      ),
      source: (app) => app.inscriptionsNotes,
      filtres: [
        FiltreCrud.egal(
          libelle: 'Année',
          options: _optionsAnneesInscriptions,
          valeur: (ligne, app) => '${ligne['annee'] ?? ''}',
        ),
        FiltreCrud.egal(
          libelle: 'Filière',
          options: _optionsFilieresCode,
          valeur: (ligne, app) => '${ligne['filiere_code'] ?? ''}',
        ),
        FiltreCrud.egal(
          libelle: 'Niveau',
          options: _optionsNiveaux,
          valeur: (ligne, app) => ligne['niveau_id'],
        ),
      ],
      colonnes: [
        ColonneTableau(libelle: 'Matricule', valeur: (l, a) => _texte(l['matricule']), largeur: 130),
        ColonneTableau(libelle: 'Étudiant', valeur: (l, a) => _texte(l['etudiant_nom']), largeur: 190),
        ColonneTableau(libelle: 'Niveau', valeur: (l, a) => _texte(l['niveau_nom']), largeur: 110),
        ColonneTableau(libelle: 'Filière', valeur: (l, a) => _texte(l['filiere_nom']), largeur: 170),
        ColonneTableau(libelle: 'Groupe', valeur: (l, a) => _texte(l['groupe_nom']), largeur: 90),
        ColonneTableau(libelle: 'Année', valeur: (l, a) => _texte(l['annee']), largeur: 95),
        ColonneTableau(libelle: 'Statut', valeur: (l, a) => _texte(l['statut']), badge: true),
      ],
      champs: [
        ChampFormulaire(
          cle: 'etudiant_id',
          libelle: 'Étudiant',
          type: TypeChamp.liste,
          options: _optionsEtudiants,
        ),
        ChampFormulaire(cle: 'annee', libelle: 'Année académique'),
        ChampFormulaire(
          cle: 'niveau_id',
          libelle: 'Niveau',
          type: TypeChamp.liste,
          options: _optionsNiveaux,
        ),
        ChampFormulaire(
          cle: 'groupe_id',
          libelle: 'Groupe',
          type: TypeChamp.liste,
          obligatoire: false,
          autoriserVide: true,
          options: _optionsGroupes,
        ),
        ChampFormulaire(
          cle: 'statut',
          libelle: 'Statut',
          type: TypeChamp.liste,
          options: (app) => _optionsTexte(_statutsInscription),
        ),
        ChampFormulaire(
          cle: 'date_inscription',
          libelle: "Date d'inscription",
          type: TypeChamp.date,
          obligatoire: false,
        ),
      ],
    );

Future<void> _ouvrirGenerationEvaluations(
  BuildContext context,
  AppState app,
) async {
  if (app.semestres.isEmpty || app.niveaux.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Créez d’abord un semestre et un niveau (avec ses UE et ECUE).',
        ),
      ),
    );
    return;
  }
  int? semestre = app.semestreId ?? app.semestres.first['id'] as int?;
  int? niveau = app.niveaux.first['id'] as int?;
  final valide = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setStateDialogue) => AlertDialog(
        title: const Text('Générer les évaluations'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Crée automatiquement, pour chaque ECUE du niveau et du semestre '
                'sélectionnés : « Devoir 1 » (session 1), « Examen final » '
                '(session 1) et « Session 2 » (session 2). Les évaluations déjà '
                'présentes ne sont pas dupliquées.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: semestre,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Semestre'),
                items: [
                  for (final s in app.semestres)
                    DropdownMenuItem<int>(
                      value: s['id'] as int,
                      child: Text(
                        '${s['nom']} · ${s['annee']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (valeur) =>
                    setStateDialogue(() => semestre = valeur),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: niveau,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Niveau'),
                items: [
                  for (final n in app.niveaux)
                    DropdownMenuItem<int>(
                      value: n['id'] as int,
                      child: Text(
                        '${n['nom']} · ${n['filiere_code']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (valeur) =>
                    setStateDialogue(() => niveau = valeur),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: semestre == null || niveau == null
                ? null
                : () => Navigator.pop(context, true),
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Générer'),
          ),
        ],
      ),
    ),
  );
  if (valide != true || semestre == null || niveau == null) return;
  try {
    final reponse = await app.api.post('/notes/evaluations/generer', {
      'semestre_id': semestre,
      'niveau_id': niveau,
    });
    await app.rafraichir();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${reponse['message'] ?? 'Évaluations générées.'}',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Génération impossible : $e')),
      );
    }
  }
}

ConfigCrud configNotesEvaluations(AppState app) => ConfigCrud(
      titre: 'Évaluations',
      sousTitre: 'Devoirs, travaux pratiques, contrôles continus et examens par ECUE.',
      endpoint: '/notes/evaluations',
      nomSingulier: 'évaluation',
      feminin: true,
      actionsEnPremier: true,
      source: (app) => app.evaluationsNotes,
      filtres: [
        FiltreCrud(
          libelle: 'Niveau',
          options: _optionsNiveaux,
          correspond: (ligne, app, choix) =>
              app.niveauxECUE(ligne['ecue_id']).contains(choix),
        ),
      ],
      libelleAction: 'Générer les évaluations',
      iconeAction: Icons.auto_awesome_outlined,
      action: _ouvrirGenerationEvaluations,
      colonnes: [
        ColonneTableau(libelle: 'ECUE', valeur: (l, a) => _texte(l['ecue_code']), largeur: 95),
        ColonneTableau(libelle: 'Intitulé ECUE', valeur: (l, a) => _texte(l['ecue_nom']), largeur: 210),
        ColonneTableau(libelle: 'Évaluation', valeur: (l, a) => _texte(l['nom']), largeur: 150),
        ColonneTableau(libelle: 'Type', valeur: (l, a) => _texte(l['type_evaluation']), badge: true),
        ColonneTableau(libelle: 'Coef.', valeur: (l, a) => '${l['coefficient'] ?? 1}', numerique: true, largeur: 60),
        ColonneTableau(libelle: 'Barème', valeur: (l, a) => '${l['note_max'] ?? 20}', numerique: true, largeur: 70),
        ColonneTableau(libelle: 'Session', valeur: (l, a) => 'Session ${l['session'] ?? 1}', largeur: 80),
        ColonneTableau(libelle: 'Notes', valeur: (l, a) => '${l['nb_notes'] ?? 0}', numerique: true, largeur: 65),
      ],
      champs: [
        ChampFormulaire(
          cle: 'ecue_id',
          libelle: 'ECUE',
          type: TypeChamp.liste,
          options: _optionsECUE,
        ),
        const ChampFormulaire(cle: 'nom', libelle: "Nom de l'évaluation", aide: 'Ex. Devoir 1, Examen final'),
        ChampFormulaire(
          cle: 'type_evaluation',
          libelle: "Type d'évaluation",
          type: TypeChamp.liste,
          options: (app) => _optionsTexte(_typesEvaluation),
        ),
        const ChampFormulaire(
          cle: 'coefficient',
          libelle: 'Coefficient',
          type: TypeChamp.nombre,
          aide: 'Par défaut : 1 pour un devoir / CC / TP, 2 pour un examen.',
        ),
        const ChampFormulaire(
          cle: 'note_max',
          libelle: 'Barème (note maximale)',
          type: TypeChamp.nombre,
        ),
        ChampFormulaire(
          cle: 'date_evaluation',
          libelle: "Date de l'évaluation",
          type: TypeChamp.date,
          obligatoire: false,
        ),
        ChampFormulaire(
          cle: 'session',
          libelle: 'Session',
          type: TypeChamp.nombre,
          aide: '1 = session normale, 2 = rattrapage',
        ),
      ],
    );

/// Valeurs utilitaires partagées avec les pages du module notes.
const statutsInscription = _statutsInscription;
const typesEvaluation = _typesEvaluation;
const sessionsEvaluation = _sessions;
const decisionsDeliberation = _decisions;
