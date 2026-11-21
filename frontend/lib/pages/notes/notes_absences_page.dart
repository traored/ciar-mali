import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'commun.dart';

/// Espace « Absences » : présences et absences par étudiant.
///
/// L'administration voit tous les étudiants, un enseignant les appels de ses
/// ECUE, un étudiant ses propres absences. Le détail liste les séances où
/// l'étudiant a été déclaré absent, avec l'ECUE et la date.
class NotesAbsencesPage extends StatefulWidget {
  const NotesAbsencesPage({super.key});

  @override
  State<NotesAbsencesPage> createState() => _NotesAbsencesPageState();
}

class _NotesAbsencesPageState extends State<NotesAbsencesPage> {
  int? _semestreId;
  int? _niveauId;
  bool _seulementAppeles = true;
  bool _chargement = false;
  String? _erreur;
  List<Map<String, dynamic>> _lignes = [];
  Map<String, dynamic> _totaux = {};

  /// Détails des absences déjà chargés, par identifiant d'inscription.
  final Map<int, Map<String, dynamic>> _details = {};
  final _recherche = TextEditingController();
  String _filtre = '';

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_semestreId != app.semestreId) {
      _semestreId = app.semestreId;
      _charger();
    }
  }

  Future<void> _charger() async {
    final app = context.read<AppState>();
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final donnees = await app.api.get('/notes/absences', {
        if (_semestreId != null) 'semestre_id': _semestreId,
        if (_niveauId != null) 'niveau_id': _niveauId,
        if (!app.estLecteur) 'seulement_appeles': _seulementAppeles,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      final lignes = ((donnees['lignes'] as List?) ?? [])
          .map((ligne) => Map<String, dynamic>.from(ligne as Map))
          .toList();
      setState(() {
        _lignes = lignes;
        _totaux = Map<String, dynamic>.from(donnees['totaux'] as Map? ?? {});
        _details.clear();
      });
      if (app.estLecteur) {
        await _chargerDetailsEtudiant(lignes);
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _chargerDetailsEtudiant(List<Map<String, dynamic>> lignes) async {
    final app = context.read<AppState>();
    final details = <int, Map<String, dynamic>>{};
    for (final ligne in lignes) {
      final inscriptionId = ligne['inscription_id'];
      if (inscriptionId is! int) continue;
      try {
        final detail = await app.api.get('/notes/absences/detail', {
          'inscription_id': inscriptionId,
          if (_semestreId != null) 'semestre_id': _semestreId,
        }) as Map<String, dynamic>;
        details[inscriptionId] = detail;
      } catch (_) {
        // Le résumé reste affiché même si le détail est indisponible.
      }
    }
    if (mounted) setState(() => _details.addAll(details));
  }

  Future<void> _ouvrirDetail(Map<String, dynamic> ligne) async {
    final app = context.read<AppState>();
    final inscriptionId = ligne['inscription_id'];
    if (inscriptionId is! int) return;
    var detail = _details[inscriptionId];
    if (detail == null) {
      try {
        detail = await app.api.get('/notes/absences/detail', {
          'inscription_id': inscriptionId,
          if (_semestreId != null) 'semestre_id': _semestreId,
        }) as Map<String, dynamic>;
        _details[inscriptionId] = detail;
      } catch (e) {
        if (mounted) afficherMessage(context, e.toString(), erreur: true);
        return;
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _DialogueAbsences(
        ligne: ligne,
        detail: detail!,
      ),
    );
  }

  List<Map<String, dynamic>> get _lignesFiltrees {
    final cible = _filtre.trim().toLowerCase();
    if (cible.isEmpty) return _lignes;
    return _lignes.where((ligne) {
      final texte = [
        '${ligne['matricule'] ?? ''}',
        '${ligne['etudiant_nom'] ?? ''}',
        '${ligne['niveau'] ?? ''}',
        '${ligne['filiere'] ?? ''}',
        '${ligne['groupe'] ?? ''}',
      ].join(' ').toLowerCase();
      return texte.contains(cible);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final etudiant = app.estLecteur;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EntetePage(
            titre: etudiant ? 'Mes absences' : 'Absences',
            sousTitre: etudiant
                ? 'Vos absences déclarées par les enseignants, séance par séance.'
                : app.estEnseignant
                ? 'Absences des étudiants dans les ECUE qui vous sont affectées.'
                : 'Présences et absences déclarées par les enseignants, par étudiant.',
            actions: [
              OutlinedButton.icon(
                onPressed: _chargement ? null : _charger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          CarteSection(
            child: Wrap(
              spacing: 18,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                selecteurSemestre(
                  app,
                  _semestreId,
                  (valeur) => app.selectionnerSemestre(valeur),
                ),
                if (!etudiant)
                  selecteurNiveau(app, _niveauId, (valeur) {
                    setState(() => _niveauId = valeur);
                    _charger();
                  }),
                if (!etudiant)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _seulementAppeles,
                        onChanged: (valeur) {
                          setState(() => _seulementAppeles = valeur);
                          _charger();
                        },
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Masquer les étudiants sans appel',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                if (etudiant)
                  Pastille(
                    '${_totaux['seances'] ?? 0} séance(s) suivie(s)',
                    couleur: AppCouleurs.bleu,
                  ),
              ],
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 14),
            Text(_erreur!, style: const TextStyle(color: AppCouleurs.rouge)),
          ],
          const SizedBox(height: 16),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _cartes(etudiant),
            const SizedBox(height: 16),
            if (etudiant)
              _vueEtudiant(app)
            else
              _vueListe(app),
          ],
        ],
      ),
    );
  }

  Widget _cartes(bool etudiant) {
    final cartes = [
      CarteIndicateur(
        libelle: etudiant ? 'Séances suivies' : 'Étudiants',
        valeur: '${_totaux['seances'] ?? 0}',
        icone: Icons.event_available_outlined,
        couleur: AppCouleurs.bleu,
        detail: etudiant
            ? null
            : '${_totaux['etudiants'] ?? 0} étudiant(s) avec appel',
      ),
      CarteIndicateur(
        libelle: 'Présences',
        valeur: '${_totaux['presents'] ?? 0}',
        icone: Icons.check_circle_outline,
        couleur: AppCouleurs.vert,
      ),
      CarteIndicateur(
        libelle: 'Absences',
        valeur: '${_totaux['absents'] ?? 0}',
        icone: Icons.cancel_outlined,
        couleur: AppCouleurs.rouge,
      ),
      CarteIndicateur(
        libelle: 'Taux de présence',
        valeur: '${noteTexte(_totaux['taux_presence'], decimales: 1)} %',
        icone: Icons.insights_outlined,
        couleur: AppCouleurs.ambre,
      ),
    ];
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < 900) {
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final carte in cartes)
                SizedBox(
                  width: (contraintes.maxWidth - 14) / 2,
                  child: carte,
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cartes.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: cartes[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _vueEtudiant(AppState app) {
    if (_lignes.isEmpty) {
      return const CarteTableau(
        child: EtatVide(
          message:
              'Aucune séance avec appel enregistré pour ce semestre. Vos absences apparaîtront ici dès qu’un enseignant aura rempli la feuille de présence.',
          icone: Icons.fact_check_outlined,
        ),
      );
    }
    return Column(
      children: [
        for (final ligne in _lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _carteEtudiant(ligne),
          ),
      ],
    );
  }

  Widget _carteEtudiant(Map<String, dynamic> ligne) {
    final inscriptionId = ligne['inscription_id'];
    final detail = inscriptionId is int ? _details[inscriptionId] : null;
    final absences = (detail?['absences'] as List?) ?? [];
    return CarteSection(
      titre: '${ligne['niveau'] ?? 'Mon parcours'} · ${ligne['annee'] ?? ''}',
      sousTitre:
          '${ligne['presents'] ?? 0} présence(s) · ${ligne['absents'] ?? 0} absence(s) · '
          '${noteTexte(ligne['taux_presence'], decimales: 1)} % de présence',
      child: absences.isEmpty
          ? const EtatVide(
              message: 'Aucune absence déclarée pour cette inscription.',
              icone: Icons.check_circle_outline,
            )
          : Column(
              children: [
                for (final absence in absences)
                  _tuileAbsence(
                    Map<String, dynamic>.from(absence as Map),
                    dense: false,
                  ),
              ],
            ),
    );
  }

  Widget _vueListe(AppState app) {
    final lignes = _lignesFiltrees;
    return CarteTableau(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                ChampRecherche(
                  controleur: _recherche,
                  hint: 'Rechercher un étudiant…',
                  onChanged: (valeur) => setState(() => _filtre = valeur),
                ),
                const Spacer(),
                Pastille('${lignes.length} étudiant(s)'),
              ],
            ),
          ),
          const Divider(height: 1),
          if (lignes.isEmpty)
            EtatVide(
              message: app.estEnseignant
                  ? 'Aucun appel enregistré dans vos ECUE pour ce filtre.'
                  : 'Aucun étudiant ne correspond à cette recherche.',
              icone: Icons.search_off_outlined,
            )
          else
            Scrollbar(
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 18,
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('MATRICULE')),
                    DataColumn(label: Text('ÉTUDIANT')),
                    DataColumn(label: Text('NIVEAU')),
                    DataColumn(label: Text('GROUPE')),
                    DataColumn(label: Text('PRÉSENCES'), numeric: true),
                    DataColumn(label: Text('ABSENCES'), numeric: true),
                    DataColumn(label: Text('TAUX')),
                    DataColumn(label: Text('DERNIÈRE ABSENCE')),
                    DataColumn(label: Text('DÉTAIL')),
                  ],
                  rows: [
                    for (final ligne in lignes)
                      DataRow(
                        cells: [
                          DataCell(Text('${ligne['matricule'] ?? '—'}')),
                          DataCell(
                            SizedBox(
                              width: 210,
                              child: Text(
                                '${ligne['etudiant_nom'] ?? '—'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${ligne['niveau'] ?? '—'} · ${ligne['filiere'] ?? ''}',
                            ),
                          ),
                          DataCell(Text('${ligne['groupe'] ?? '—'}')),
                          DataCell(Text('${ligne['presents'] ?? 0}')),
                          DataCell(
                            Text(
                              '${ligne['absents'] ?? 0}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ((ligne['absents'] as num?) ?? 0) > 0
                                    ? AppCouleurs.rouge
                                    : AppCouleurs.texteDoux,
                              ),
                            ),
                          ),
                          DataCell(
                            Pastille(
                              '${noteTexte(ligne['taux_presence'], decimales: 1)} %',
                              couleur: _couleurTaux(
                                ((ligne['taux_presence'] as num?) ?? 0)
                                    .toDouble(),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              _dateTexte(
                                ligne['derniere_absence'] as String?,
                              ),
                            ),
                          ),
                          DataCell(
                            TextButton.icon(
                              onPressed: () => _ouvrirDetail(ligne),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 16,
                              ),
                              label: const Text('Voir le détail'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tuileAbsence(Map<String, dynamic> absence, {required bool dense}) {
    final date = _dateTexte(absence['date'] as String?);
    final jour = '${absence['jour'] ?? ''}';
    final debut = '${absence['debut'] ?? ''}';
    final fin = '${absence['fin'] ?? ''}';
    final ecue = '${absence['ecue_code'] ?? ''}';
    final nom = '${absence['ecue_nom'] ?? ''}';
    final type = '${absence['type_seance'] ?? ''}';
    final enseignant = '${absence['enseignant'] ?? ''}';
    final commentaire = '${absence['commentaire'] ?? ''}';
    return Container(
      margin: EdgeInsets.only(bottom: dense ? 8 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.fond,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppCouleurs.rouge.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.event_busy_outlined,
              color: AppCouleurs.rouge,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$date${jour.isEmpty ? '' : ' · $jour'}'
                  '${debut.isEmpty ? '' : ' · $debut${fin.isEmpty ? '' : '–$fin'}'}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ecue.isEmpty ? 'ECUE non renseignée' : '$ecue — $nom',
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (type.isNotEmpty || enseignant.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [
                        if (type.isNotEmpty) type,
                        if (enseignant.isNotEmpty) enseignant,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ),
                if (commentaire.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      commentaire,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _couleurTaux(double taux) {
    if (taux >= 80) return AppCouleurs.vert;
    if (taux >= 50) return AppCouleurs.ambre;
    return AppCouleurs.rouge;
  }
}

String _dateTexte(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  final jour = date.day.toString().padLeft(2, '0');
  final mois = date.month.toString().padLeft(2, '0');
  return '$jour/$mois/${date.year}';
}

class _DialogueAbsences extends StatefulWidget {
  final Map<String, dynamic> ligne;
  final Map<String, dynamic> detail;

  const _DialogueAbsences({required this.ligne, required this.detail});

  @override
  State<_DialogueAbsences> createState() => _DialogueAbsencesState();
}

class _DialogueAbsencesState extends State<_DialogueAbsences> {
  /// Contrôleur partagé par la barre et la liste : sans lui, la barre reste
  /// immobile lorsque plusieurs zones défilantes coexistent (page + dialogue).
  final ScrollController _defilement = ScrollController();

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ligne = widget.ligne;
    final detail = widget.detail;
    final etudiant = Map<String, dynamic>.from(
      detail['etudiant'] as Map? ?? {},
    );
    final absences = ((detail['absences'] as List?) ?? [])
        .map((absence) => Map<String, dynamic>.from(absence as Map))
        .toList();
    final nom = '${etudiant['nom_complet'] ?? ligne['etudiant_nom'] ?? 'Étudiant'}';
    final matricule = '${etudiant['matricule'] ?? ligne['matricule'] ?? ''}';
    final niveau = '${etudiant['niveau'] ?? ligne['niveau'] ?? ''}';
    final groupe = '${etudiant['groupe'] ?? ligne['groupe'] ?? ''}';
    final presents = ligne['presents'] ?? 0;
    final absents = ligne['absents'] ?? 0;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nom,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (matricule.isNotEmpty) matricule,
              if (niveau.isNotEmpty) '$niveau · $groupe',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppCouleurs.texteDoux),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Pastille('$presents présence(s)', couleur: AppCouleurs.vert),
              Pastille('$absents absence(s)', couleur: AppCouleurs.rouge),
              Pastille(
                '${noteTexte(ligne['taux_presence'], decimales: 1)} % de présence',
                couleur: AppCouleurs.bleu,
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: absences.isEmpty
              ? const EtatVide(
                  message: 'Aucune absence déclarée pour cet étudiant.',
                  icone: Icons.check_circle_outline,
                )
              : Scrollbar(
                  controller: _defilement,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  child: ListView(
                    controller: _defilement,
                    padding: const EdgeInsets.only(right: 10),
                    children: [
                      for (final absence in absences)
                        _tuileAbsenceDialogue(absence),
                    ],
                  ),
                ),
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

  Widget _tuileAbsenceDialogue(Map<String, dynamic> absence) {
    final date = _dateTexte(absence['date'] as String?);
    final jour = '${absence['jour'] ?? ''}';
    final debut = '${absence['debut'] ?? ''}';
    final fin = '${absence['fin'] ?? ''}';
    final ecue = '${absence['ecue_code'] ?? ''}';
    final nom = '${absence['ecue_nom'] ?? ''}';
    final type = '${absence['type_seance'] ?? ''}';
    final enseignant = '${absence['enseignant'] ?? ''}';
    final salle = '${absence['salle'] ?? ''}';
    final commentaire = '${absence['commentaire'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.fond,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppCouleurs.bordure),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppCouleurs.rouge.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.event_busy_outlined,
              color: AppCouleurs.rouge,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$date${jour.isEmpty ? '' : ' · $jour'}'
                  '${debut.isEmpty ? '' : ' · $debut${fin.isEmpty ? '' : '–$fin'}'}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ecue.isEmpty ? 'ECUE non renseignée' : '$ecue — $nom',
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (type.isNotEmpty || enseignant.isNotEmpty || salle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [
                        if (type.isNotEmpty) type,
                        if (enseignant.isNotEmpty) enseignant,
                        if (salle.isNotEmpty) salle,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ),
                if (commentaire.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      commentaire,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: AppCouleurs.texteDoux,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
