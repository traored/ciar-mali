import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/utilisateur.dart';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  bool demarrage = true;
  bool chargementDonnees = false;
  String? erreurChargement;
  Utilisateur? utilisateur;

  List<Map<String, dynamic>> departements = [];
  List<Map<String, dynamic>> filieres = [];
  List<Map<String, dynamic>> niveaux = [];
  List<Map<String, dynamic>> groupes = [];
  List<Map<String, dynamic>> enseignants = [];
  List<Map<String, dynamic>> salles = [];
  List<Map<String, dynamic>> creneaux = [];
  List<Map<String, dynamic>> semestres = [];

  /// Tous les semestres, avant restriction au périmètre de l'utilisateur.
  /// Sert notamment à retrouver le semestre courant de l'année courante.
  List<Map<String, dynamic>> semestresTous = [];
  List<Map<String, dynamic>> ues = [];
  List<Map<String, dynamic>> ecues = [];
  List<Map<String, dynamic>> affectations = [];
  List<Map<String, dynamic>> utilisateurs = [];
  List<Map<String, dynamic>> etudiantsNotes = [];
  List<Map<String, dynamic>> inscriptionsNotes = [];
  List<Map<String, dynamic>> evaluationsNotes = [];

  int? semestreId;
  int semaine = 1;

  /// Semaines du semestre courant qui contiennent au moins une séance.
  /// Sert à ouvrir l'application sur une semaine réellement remplie.
  Set<int> semainesAvecSeances = <int>{};

  /// Semestres où l'utilisateur a des séances. Un enseignant peut enseigner
  /// dans un semestre absent de ses affectations (séance créée par un
  /// administrateur) : on le rend tout de même sélectionnable.
  Set<int> semestresAvecSeances = <int>{};

  bool get connecte => utilisateur != null;
  bool get estAdmin => utilisateur?.role == 'admin';
  bool get peutModifier =>
      utilisateur?.role == 'admin' || utilisateur?.role == 'gestionnaire';
  bool get estEnseignant => utilisateur?.role == 'enseignant';
  bool get estLecteur => utilisateur?.role == 'lecteur';

  /// Numéro de la semaine du semestre [id] qui contient [date].
  int semainePourDate(DateTime date, [dynamic id]) {
    final debut = debutSemestre(id);
    if (debut == null) return 1;
    final lundi = DateTime(debut.year, debut.month, debut.day);
    final jour = DateTime(date.year, date.month, date.day);
    final decalage = jour.difference(lundi).inDays;
    return (decalage ~/ 7 + 1).clamp(1, nombreSemainesDe(id));
  }

  /// Sélectionne la semaine à afficher : la semaine courante si elle contient
  /// des séances, sinon la semaine la plus proche qui en contient.
  void selectionnerSemaineCourante() {
    semaine = semaineParDefaut();
    notifyListeners();
  }

  /// Semaine affichée par défaut pour un semestre.
  ///
  /// La semaine qui contient la date du jour est privilégiée. Si elle est
  /// vide (vacances, semestre décalé), on retient la semaine la plus proche
  /// disposant de séances, à défaut la semaine de la date du jour.
  int semaineParDefaut([dynamic id]) {
    final semestre = id ?? semestreId;
    final reference = semainePourDate(DateTime.now(), semestre);
    if (semainesAvecSeances.isEmpty) return reference;
    if (semainesAvecSeances.contains(reference)) return reference;
    int? meilleure;
    var distance = 1 << 30;
    for (final candidate in semainesAvecSeances) {
      final ecart = (candidate - reference).abs();
      if (ecart < distance ||
          (ecart == distance && candidate > (meilleure ?? 0))) {
        distance = ecart;
        meilleure = candidate;
      }
    }
    return (meilleure ?? reference).clamp(1, nombreSemainesDe(semestre));
  }

  /// Charge les semaines du semestre courant qui contiennent des séances.
  Future<void> _chargerSemaines() async {
    semainesAvecSeances = <int>{};
    final id = semestreId;
    if (id == null) return;
    try {
      final donnees = await api.get('/seances/semaines', {'semestre_id': id});
      final brut = donnees is Map ? donnees['semaines'] : donnees;
      if (brut is List) {
        semainesAvecSeances = brut
            .map((valeur) => valeur is int ? valeur : int.tryParse('$valeur'))
            .whereType<int>()
            .toSet();
      }
    } catch (_) {
      // Sans cette information, on retombe sur la semaine de la date du jour.
    }
  }

  Map<String, dynamic>? get semestreSelectionne {
    if (semestres.isEmpty) return null;
    return semestres.firstWhere(
      (s) => s['id'] == semestreId,
      orElse: () => semestres.firstWhere(
        (s) => s['actif'] == true,
        orElse: () => semestres.first,
      ),
    );
  }

  int get nombreSemaines => (semestreSelectionne?['semaines'] as int?) ?? 12;

  static const _moisLongs = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  static const _moisCourts = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  /// Date de début du semestre (ou du semestre courant si [id] est omis).
  DateTime? debutSemestre([dynamic id]) {
    final semestre =
        _trouver(semestres, id ?? semestreId) ?? semestreSelectionne;
    final brut = semestre?['date_debut'];
    if (brut == null) return null;
    return DateTime.tryParse('$brut');
  }

  DateTime? _borneSemaine(dynamic id, int semaine, int decalage) {
    final debut = debutSemestre(id);
    if (debut == null) return null;
    return DateTime(
      debut.year,
      debut.month,
      debut.day + (semaine - 1) * 7 + decalage,
    );
  }

  /// Nombre de semaines du semestre [id] (ou du semestre courant).
  int nombreSemainesDe([dynamic id]) {
    final semestre = _trouver(semestres, id) ?? semestreSelectionne;
    return (semestre?['semaines'] as int?) ?? nombreSemaines;
  }

  /// Période du lundi au samedi d'une semaine, par exemple
  /// « du 12 au 17 octobre 2026 » ou « 12–17 oct. 2026 » en format court.
  String periodeSemaine(int semaine, {bool court = false, dynamic semestreId}) {
    final debut = _borneSemaine(semestreId, semaine, 0);
    final fin = _borneSemaine(semestreId, semaine, 5);
    if (debut == null || fin == null) return '';
    final moisDebut = court
        ? _moisCourts[debut.month - 1]
        : _moisLongs[debut.month - 1];
    final moisFin = court
        ? _moisCourts[fin.month - 1]
        : _moisLongs[fin.month - 1];
    if (debut.year == fin.year && debut.month == fin.month) {
      return court
          ? '${debut.day}–${fin.day} $moisFin ${fin.year}'
          : 'du ${debut.day} au ${fin.day} $moisFin ${fin.year}';
    }
    if (debut.year == fin.year) {
      return court
          ? '${debut.day} $moisDebut – ${fin.day} $moisFin ${fin.year}'
          : 'du ${debut.day} $moisDebut au ${fin.day} $moisFin ${fin.year}';
    }
    return court
        ? '${debut.day} $moisDebut ${debut.year} – ${fin.day} $moisFin ${fin.year}'
        : 'du ${debut.day} $moisDebut ${debut.year} au ${fin.day} $moisFin ${fin.year}';
  }

  /// Libellé prêt à afficher : « Semaine 1 · du 12 au 17 octobre 2026 ».
  String libelleSemaine(int semaine, {bool court = false, dynamic semestreId}) {
    final periode = periodeSemaine(
      semaine,
      court: court,
      semestreId: semestreId,
    );
    return periode.isEmpty ? 'Semaine $semaine' : 'Semaine $semaine · $periode';
  }

  Future<void> demarrer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('edt.token');
      final utilisateurJson = prefs.getString('edt.utilisateur');
      if (token == null || token.isEmpty) {
        demarrage = false;
        notifyListeners();
        return;
      }
      api.token = token;
      final profil = await api.get('/auth/moi') as Map<String, dynamic>;
      utilisateur = Utilisateur.depuisJson(profil);
      if (utilisateurJson != null) {
        // Le profil serveur fait foi, la copie locale sert de secours hors ligne.
      }
      await chargerTout(initial: true);
    } on ApiException catch (e) {
      if (e.code == 401 || e.code == 403) {
        await _effacerSession();
      } else {
        // Panne réseau ou serveur indisponible : on conserve la session et
        // le profil local pour ne pas renvoyer l'utilisateur à la connexion.
        erreurChargement = e.message;
        await _restaurerProfilLocal();
      }
    } catch (e) {
      erreurChargement = e.toString();
      await _restaurerProfilLocal();
    } finally {
      demarrage = false;
      notifyListeners();
    }
  }

  Future<void> _effacerSession() async {
    api.token = null;
    utilisateur = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('edt.token');
    await prefs.remove('edt.utilisateur');
  }

  /// Recharge le profil enregistré quand le serveur est momentanément
  /// injoignable, afin de laisser l'application utilisable.
  Future<void> _restaurerProfilLocal() async {
    if (utilisateur != null) return;
    final prefs = await SharedPreferences.getInstance();
    final utilisateurJson = prefs.getString('edt.utilisateur');
    if (utilisateurJson == null || utilisateurJson.isEmpty) return;
    try {
      utilisateur = Utilisateur.depuisJson(
        jsonDecode(utilisateurJson) as Map<String, dynamic>,
      );
    } catch (_) {
      // Profil local illisible : la page de connexion prendra le relais.
    }
  }

  Future<void> connexion(String identifiant, String motDePasse) async {
    final donnees = await api.post('/auth/connexion', {
      'identifiant': identifiant,
      'mot_de_passe': motDePasse,
    });
    api.token = donnees['access_token'] as String;
    utilisateur = Utilisateur.depuisJson(
      donnees['utilisateur'] as Map<String, dynamic>,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('edt.token', api.token!);
    await prefs.setString(
      'edt.utilisateur',
      jsonEncode(utilisateur!.versJson()),
    );
    await chargerTout(initial: true);
    notifyListeners();
  }

  Future<void> deconnexion() async {
    api.token = null;
    utilisateur = null;
    semestreId = null;
    semaine = 1;
    _vider();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('edt.token');
    await prefs.remove('edt.utilisateur');
    notifyListeners();
  }

  /// Récupère les semestres où l'utilisateur a des séances. Un échec de cet
  /// appel secondaire ne doit pas empêcher le reste de l'application de
  /// démarrer.
  Future<dynamic> _semestresAvecSeancesBrut() async {
    try {
      return await api.get('/seances/semestres');
    } catch (_) {
      return null;
    }
  }

  Future<void> chargerTout({bool initial = false}) async {
    chargementDonnees = true;
    erreurChargement = null;
    notifyListeners();
    try {
      final resultats = await Future.wait([
        api.liste('/departements'),
        api.liste('/filieres'),
        api.liste('/niveaux'),
        api.liste('/groupes'),
        api.liste('/enseignants'),
        api.liste('/salles'),
        api.liste('/creneaux'),
        api.liste('/semestres'),
        api.liste('/ues'),
        api.liste('/ecues'),
        api.liste('/affectations'),
        if (estAdmin)
          api.liste('/utilisateurs')
        else
          Future.value(<Map<String, dynamic>>[]),
        api.liste('/notes/etudiants'),
        api.liste('/notes/inscriptions'),
        api.liste('/notes/evaluations'),
        _semestresAvecSeancesBrut(),
      ]);
      departements = resultats[0];
      filieres = resultats[1];
      niveaux = resultats[2];
      groupes = resultats[3];
      enseignants = resultats[4];
      salles = resultats[5];
      creneaux = resultats[6];
      semestres = resultats[7];
      ues = resultats[8];
      ecues = resultats[9];
      affectations = resultats[10];
      utilisateurs = resultats[11];
      etudiantsNotes = resultats[12];
      inscriptionsNotes = resultats[13];
      evaluationsNotes = resultats[14];
      final brutSemestres = resultats[15];
      semestresAvecSeances = <int>{};
      if (brutSemestres is Map && brutSemestres['semestres'] is List) {
        semestresAvecSeances = (brutSemestres['semestres'] as List)
            .map((valeur) => valeur is int ? valeur : int.tryParse('$valeur'))
            .whereType<int>()
            .toSet();
      }
      _trierReferences();
      semestresTous = List<Map<String, dynamic>>.from(semestres);
      _restreindreEnseignant();
      _restreindrePerimetre();

      if (semestres.isNotEmpty) {
        final precedent = semestreId;
        if (initial) {
          // À la connexion, on ouvre sur le semestre qui contient la date du
          // jour : l'emploi du temps de la semaine courante s'affiche donc
          // immédiatement, quel que soit le rôle.
          semestreId = semestreCourant() ?? _semestreParDefaut();
        } else {
          if (semestreId == null) {
            final prefs = await SharedPreferences.getInstance();
            final memorise = prefs.getInt('edt.semestre');
            if (memorise != null && semestres.any((s) => s['id'] == memorise)) {
              semestreId = memorise;
            }
          }
          final existe = semestres.any((s) => s['id'] == semestreId);
          if (!existe) {
            semestreId = _semestreParDefaut();
          } else if ((estEnseignant || estLecteur) &&
              semestresAvecSeances.isNotEmpty &&
              !semestresAvecSeances.contains(semestreId)) {
            // Le semestre mémorisé (parfois choisi par un autre compte sur le
            // même navigateur) ne contient aucune séance accessible : on ouvre
            // sur celui où l'utilisateur a réellement cours.
            semestreId = _semestreParDefaut();
          }
        }
        await _chargerSemaines();
        if (initial || semestreId != precedent) {
          // Semaine courante à l'ouverture ; un simple rafraîchissement
          // conserve la semaine déjà choisie par l'utilisateur.
          semaine = semaineParDefaut();
        } else {
          semaine = semaine.clamp(1, nombreSemaines);
        }
      }
      if (semaine > nombreSemaines) semaine = 1;
    } catch (e) {
      erreurChargement = e.toString();
      rethrow;
    } finally {
      chargementDonnees = false;
      notifyListeners();
    }
  }

  Future<void> rafraichir() => chargerTout();

  Future<void> selectionnerSemestre(int? id) async {
    if (id == null) return;
    semestreId = id;
    semaine = semainePourDate(DateTime.now(), id);
    notifyListeners();
    await _chargerSemaines();
    semaine = semaineParDefaut(id);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('edt.semestre', id);
    });
    notifyListeners();
  }

  /// Semestre dont la période contient la date du jour.
  ///
  /// C'est lui qui doit s'ouvrir à la connexion pour que la semaine courante
  /// soit visible immédiatement. Pour un enseignant ou un étudiant, un semestre
  /// sans séance accessible est écarté afin de ne pas ouvrir un emploi du temps
  /// vide ; on retombe alors sur [_semestreParDefaut].
  int? semestreCourant() {
    final maintenant = DateTime.now();
    var candidats = semestres.where((semestre) {
      final debut = DateTime.tryParse('${semestre['date_debut'] ?? ''}');
      final fin = DateTime.tryParse('${semestre['date_fin'] ?? ''}');
      if (debut == null || fin == null) return false;
      return !maintenant.isBefore(debut) && !maintenant.isAfter(fin);
    }).toList();
    if (candidats.isEmpty) return null;
    if ((estEnseignant || estLecteur) && semestresAvecSeances.isNotEmpty) {
      final avecSeances = candidats
          .where((semestre) => semestresAvecSeances.contains(semestre['id']))
          .toList();
      // Aucune séance générée dans un semestre de l'année courante ne doit pas
      // faire retomber sur une année passée : un enseignant affecté à l'année
      // courante ouvre bien le semestre en cours (quitte à le compléter).
      if (avecSeances.isNotEmpty) candidats = avecSeances;
    }
    candidats.sort((a, b) {
      final actif = (b['actif'] == true ? 1 : 0) - (a['actif'] == true ? 1 : 0);
      if (actif != 0) return actif;
      final annee = '${b['annee']}'.compareTo('${a['annee']}');
      if (annee != 0) return annee;
      return '${a['nom']}'.compareTo('${b['nom']}');
    });
    return candidats.first['id'] as int;
  }

  /// Choisit le semestre à afficher quand aucun n'a encore été sélectionné.
  ///
  /// Le semestre qui contient le plus d'évaluations est privilégié : c'est
  /// celui où se trouvent réellement les notes. À défaut, on prend l'année
  /// qui compte le plus d'inscriptions, puis le premier semestre actif.
  /// Sans cela, l'application ouvrait l'année la plus récente (par exemple
  /// 2026-2027), souvent vide, et les tableaux paraissaient vides.
  int _semestreParDefaut() {
    final actifs = semestres.where((s) => s['actif'] == true).toList();
    final candidats = actifs.isNotEmpty ? actifs : semestres;

    // Un enseignant ou un étudiant ouvre son emploi du temps : on privilégie
    // un semestre où il a réellement des séances, même sans affectation
    // enregistrée, et même si ce semestre n'est pas marqué actif.
    if ((estEnseignant || estLecteur) && semestresAvecSeances.isNotEmpty) {
      final avecSeances = semestres
          .where((s) => semestresAvecSeances.contains(s['id']))
          .toList();
      if (avecSeances.isNotEmpty) {
        // Pour un étudiant, on retient le semestre le plus récent de son
        // parcours ; pour un enseignant, le premier semestre actif.
        if (estLecteur) {
          avecSeances.sort((a, b) {
            final annee = '${b['annee']}'.compareTo('${a['annee']}');
            if (annee != 0) return annee;
            return '${a['nom']}'.compareTo('${b['nom']}');
          });
        }
        return avecSeances.first['id'] as int;
      }
    }

    final evaluationsParSemestre = <int, int>{};
    for (final evaluation in evaluationsNotes) {
      final id = evaluation['semestre_id'];
      if (id is int) {
        evaluationsParSemestre[id] = (evaluationsParSemestre[id] ?? 0) + 1;
      }
    }
    if (evaluationsParSemestre.isNotEmpty) {
      int? meilleur;
      var maximum = 0;
      for (final semestre in candidats) {
        final id = semestre['id'] as int;
        final nombre = evaluationsParSemestre[id] ?? 0;
        if (nombre > maximum) {
          maximum = nombre;
          meilleur = id;
        }
      }
      if (meilleur != null) return meilleur;
    }

    final inscriptionsParAnnee = <String, int>{};
    for (final inscription in inscriptionsNotes) {
      final annee = '${inscription['annee'] ?? ''}';
      if (annee.isEmpty) continue;
      inscriptionsParAnnee[annee] = (inscriptionsParAnnee[annee] ?? 0) + 1;
    }
    if (inscriptionsParAnnee.isNotEmpty) {
      final meilleure = inscriptionsParAnnee.entries.reduce(
        (a, b) => b.value > a.value ? b : a,
      );
      final correspondants = candidats
          .where((s) => '${s['annee'] ?? ''}' == meilleure.key)
          .toList();
      if (correspondants.isNotEmpty) return correspondants.first['id'] as int;
    }

    return candidats.first['id'] as int;
  }

  void selectionnerSemaine(int valeur) {
    semaine = valeur.clamp(1, nombreSemaines);
    notifyListeners();
  }

  void _vider() {
    departements = [];
    filieres = [];
    niveaux = [];
    groupes = [];
    enseignants = [];
    salles = [];
    creneaux = [];
    semestres = [];
    semestresTous = [];
    ues = [];
    ecues = [];
    affectations = [];
    utilisateurs = [];
    etudiantsNotes = [];
    inscriptionsNotes = [];
    evaluationsNotes = [];
    semainesAvecSeances = <int>{};
    semestresAvecSeances = <int>{};
  }

  /// Un enseignant ne conserve que les UE/ECUE qui lui sont affectés.
  void _restreindreEnseignant() {
    final enseignantId = utilisateur?.enseignantId;
    if (!estEnseignant || enseignantId == null) return;
    final mesAffectations = affectations
        .where((a) => a['enseignant_id'] == enseignantId)
        .toList();
    final idsEcues = mesAffectations.map((a) => a['ecue_id']).toSet();
    final mesEcues = ecues.where((e) => idsEcues.contains(e['id'])).toList();
    final idsUes = mesEcues.map((e) => e['ue_id']).toSet();
    affectations = mesAffectations;
    ecues = mesEcues;
    ues = ues.where((u) => idsUes.contains(u['id'])).toList();
  }

  /// Limite les référentiels (semestres, filières, niveaux, groupes) au
  /// périmètre de l'utilisateur connecté.
  ///
  /// Un étudiant ne voit que les années, filières et niveaux de ses
  /// inscriptions ; un enseignant, que les semestres et niveaux de ses
  /// affectations. Les administrateurs et gestionnaires gardent tout.
  void _restreindrePerimetre() {
    if (estLecteur) {
      final idsNiveaux = inscriptionsNotes
          .map((i) => i['niveau_id'])
          .whereType<int>()
          .toSet();
      final anneeParSemestre = <int, String>{
        for (final semestre in semestres)
          if (semestre['id'] is int)
            semestre['id'] as int: '${semestre['annee'] ?? ''}',
      };
      // Un étudiant ne voit que les semestres de son parcours : ceux qui
      // portent une UE de son niveau pour l'année de son inscription.
      // Les niveaux sans UE (Master, cycle ingénieur) gardent les semestres
      // de leur année d'inscription.
      final idsSemestres = <int>{};
      for (final inscription in inscriptionsNotes) {
        final niveauId = inscription['niveau_id'];
        final annee = '${inscription['annee'] ?? ''}';
        if (niveauId is! int || annee.isEmpty) continue;
        var trouve = false;
        for (final ue in ues) {
          final ids = ue['niveau_ids'];
          final niveauxUe = ids is List && ids.isNotEmpty
              ? ids.whereType<int>().toList()
              : (ue['niveau_id'] is int
                    ? <int>[ue['niveau_id'] as int]
                    : const <int>[]);
          if (!niveauxUe.contains(niveauId)) continue;
          final semestreId = ue['semestre_id'];
          if (semestreId is int && anneeParSemestre[semestreId] == annee) {
            idsSemestres.add(semestreId);
            trouve = true;
          }
        }
        if (!trouve) {
          for (final entree in anneeParSemestre.entries) {
            if (entree.value == annee) idsSemestres.add(entree.key);
          }
        }
      }
      // Les semestres où l'étudiant a des séances restent accessibles.
      idsSemestres.addAll(semestresAvecSeances);
      _filtrerReferences(idsNiveaux, idsSemestres: idsSemestres);
    } else if (estEnseignant) {
      final idsNiveaux = <int>{};
      for (final ue in ues) {
        final ids = ue['niveau_ids'];
        if (ids is List && ids.isNotEmpty) {
          idsNiveaux.addAll(ids.whereType<int>());
        } else if (ue['niveau_id'] is int) {
          idsNiveaux.add(ue['niveau_id'] as int);
        }
      }
      final idsSemestres = <int>{};
      for (final affectation in affectations) {
        if (affectation['semestre_id'] is int) {
          idsSemestres.add(affectation['semestre_id'] as int);
        }
      }
      for (final ue in ues) {
        if (ue['semestre_id'] is int)
          idsSemestres.add(ue['semestre_id'] as int);
      }
      // Certaines séances peuvent exister dans un semestre sans affectation :
      // on garde ces semestres accessibles pour que l'espace ne soit pas vide.
      idsSemestres.addAll(semestresAvecSeances);
      _filtrerReferences(idsNiveaux, idsSemestres: idsSemestres);
    }
  }

  void _filtrerReferences(
    Set<int> idsNiveaux, {
    Set<int>? idsSemestres,
    Set<String>? annees,
  }) {
    niveaux = niveaux
        .where((niveau) => idsNiveaux.contains(niveau['id']))
        .toList();
    final idsFilieres = niveaux
        .map((niveau) => niveau['filiere_id'])
        .whereType<int>()
        .toSet();
    filieres = filieres
        .where((filiere) => idsFilieres.contains(filiere['id']))
        .toList();
    groupes = groupes
        .where((groupe) => idsNiveaux.contains(groupe['niveau_id']))
        .toList();
    if (idsSemestres != null) {
      semestres = semestres
          .where((semestre) => idsSemestres.contains(semestre['id']))
          .toList();
    } else if (annees != null) {
      semestres = semestres
          .where((semestre) => annees.contains('${semestre['annee'] ?? ''}'))
          .toList();
    }
  }

  void _trierReferences() {
    departements.sort((a, b) => '${a['nom']}'.compareTo('${b['nom']}'));
    filieres.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
    niveaux.sort((a, b) {
      final fa = '${a['filiere_code']}';
      final fb = '${b['filiere_code']}';
      final cmp = fa.compareTo(fb);
      if (cmp != 0) return cmp;
      return ((a['ordre'] as int?) ?? 0).compareTo((b['ordre'] as int?) ?? 0);
    });
    groupes.sort((a, b) {
      final cmp = '${a['filiere_code']}'.compareTo('${b['filiere_code']}');
      if (cmp != 0) return cmp;
      return '${a['nom']}'.compareTo('${b['nom']}');
    });
    enseignants.sort(
      (a, b) => '${a['nom_complet']}'.compareTo('${b['nom_complet']}'),
    );
    salles.sort((a, b) => '${a['nom']}'.compareTo('${b['nom']}'));
    creneaux.sort((a, b) {
      final jour = ((a['jour'] as int?) ?? 0).compareTo(
        (b['jour'] as int?) ?? 0,
      );
      if (jour != 0) return jour;
      return '${a['debut']}'.compareTo('${b['debut']}');
    });
    semestres.sort((a, b) {
      final annee = '${b['annee']}'.compareTo('${a['annee']}');
      if (annee != 0) return annee;
      return '${a['nom']}'.compareTo('${b['nom']}');
    });
    ues.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
    ecues.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
    etudiantsNotes.sort(
      (a, b) => '${a['nom_complet']}'.compareTo('${b['nom_complet']}'),
    );
    inscriptionsNotes.sort((a, b) {
      final cmp = '${b['annee']}'.compareTo('${a['annee']}');
      if (cmp != 0) return cmp;
      return '${a['etudiant_nom']}'.compareTo('${b['etudiant_nom']}');
    });
    evaluationsNotes.sort((a, b) {
      final cmp = '${a['ecue_code']}'.compareTo('${b['ecue_code']}');
      if (cmp != 0) return cmp;
      return '${a['nom']}'.compareTo('${b['nom']}');
    });
  }

  // ---------------------------------------------------------------- Recherches
  Map<String, dynamic>? _trouver(List<Map<String, dynamic>> liste, dynamic id) {
    if (id == null) return null;
    for (final element in liste) {
      if (element['id'] == id) return element;
    }
    return null;
  }

  String nomDepartement(dynamic id) =>
      '${_trouver(departements, id)?['nom'] ?? '—'}';

  String nomFiliere(dynamic id) => '${_trouver(filieres, id)?['nom'] ?? '—'}';

  String libelleFiliere(dynamic id) {
    final f = _trouver(filieres, id);
    return f == null ? '—' : '${f['code']} — ${f['nom']}';
  }

  String libelleNiveau(dynamic id) {
    final n = _trouver(niveaux, id);
    if (n == null) return '—';
    return '${n['nom']} · ${n['filiere_code']}';
  }

  String libelleGroupe(dynamic id) {
    final g = _trouver(groupes, id);
    if (g == null) return '—';
    return '${g['nom']} (${g['filiere_code']})';
  }

  String nomEnseignant(dynamic id) {
    final enseignant = _trouver(enseignants, id);
    return '${enseignant?['nom_affichage'] ?? enseignant?['nom_complet'] ?? '—'}';
  }

  String nomSalle(dynamic id) => '${_trouver(salles, id)?['nom'] ?? '—'}';

  String libelleCreneau(dynamic id) {
    final c = _trouver(creneaux, id);
    if (c == null) return '—';
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
    final jour = jours[(c['jour'] as int?) ?? 0];
    return '$jour ${c['debut']} – ${c['fin']}';
  }

  String libelleSemestre(dynamic id) {
    final s = _trouver(semestres, id);
    if (s == null) return '—';
    return '${s['nom']} · ${s['annee']}';
  }

  /// Année académique du semestre [id] (ex. « 2025-2026 »).
  String anneeSemestre(dynamic id) {
    final s = _trouver(semestres, id);
    return '${s?['annee'] ?? ''}';
  }

  /// Niveaux rattachés à l'UE d'un ECUE (un ECUE peut être mutualisé).
  List<int> niveauxECUE(dynamic ecueId) {
    final e = _trouver(ecues, ecueId);
    if (e == null) return const [];
    final ue = _trouver(ues, e['ue_id']);
    if (ue == null) return const [];
    final ids = ue['niveau_ids'];
    if (ids is List && ids.isNotEmpty) return ids.whereType<int>().toList();
    final id = ue['niveau_id'];
    return id is int ? [id] : const [];
  }

  String libelleUE(dynamic id) {
    final u = _trouver(ues, id);
    return u == null ? '—' : '${u['code']} — ${u['nom']}';
  }

  String libelleECUE(dynamic id) {
    final e = _trouver(ecues, id);
    if (e == null) return '—';
    // Un même code peut exister dans plusieurs semestres : on précise alors
    // le semestre pour éviter toute confusion dans les sélecteurs.
    final occurrences = ecues.where((x) => x['code'] == e['code']).length;
    final semestre = e['semestre_id'];
    final suffixe = occurrences > 1 && semestre != null
        ? ' · ${libelleSemestre(semestre)}'
        : '';
    return '${e['code']} — ${e['nom']}$suffixe';
  }

  List<Map<String, dynamic>> niveauxDeFiliere(dynamic filiereId) =>
      niveaux.where((n) => n['filiere_id'] == filiereId).toList();

  List<Map<String, dynamic>> groupesDeNiveau(dynamic niveauId) =>
      groupes.where((g) => g['niveau_id'] == niveauId).toList();

  /// Premier niveau (dans l'ordre des filtres) ayant au moins une séance
  /// parmi [seances]. Sert à ouvrir l'emploi du temps sur un niveau rempli.
  int? niveauAvecSeances(List<Map<String, dynamic>> seances) {
    final idsGroupes = <int>{};
    for (final seance in seances) {
      final liste = (seance['groupe_ids'] as List?) ?? const [];
      idsGroupes.addAll(liste.whereType<int>());
    }
    if (idsGroupes.isEmpty) return null;
    final idsNiveaux = groupes
        .where((g) => idsGroupes.contains(g['id']))
        .map((g) => g['niveau_id'])
        .whereType<int>()
        .toSet();
    for (final niveau in niveaux) {
      final id = niveau['id'];
      if (id is int && idsNiveaux.contains(id)) return id;
    }
    return null;
  }

  List<Map<String, dynamic>> ecuesDeSemestre(dynamic semestre) {
    final idsUe = ues
        .where((u) => u['semestre_id'] == semestre)
        .map((u) => u['id'])
        .toSet();
    return ecues.where((e) => idsUe.contains(e['ue_id'])).toList();
  }

  List<Map<String, dynamic>> groupesDeNiveauECUE(dynamic ecueId) {
    final e = _trouver(ecues, ecueId);
    if (e == null) return groupes;
    final ue = _trouver(ues, e['ue_id']);
    if (ue == null) return groupes;
    return groupes.where((g) => g['niveau_id'] == ue['niveau_id']).toList();
  }

  /// Enseignants affectés à un ECUE (via le module Programme).
  List<Map<String, dynamic>> enseignantsDeECUE(dynamic ecueId) {
    final ids = affectations
        .where((a) => a['ecue_id'] == ecueId && a['enseignant_id'] != null)
        .map((a) => a['enseignant_id'])
        .toSet();
    return enseignants.where((e) => ids.contains(e['id'])).toList();
  }

  /// Groupes confiés à un enseignant pour un ECUE donné.
  List<Map<String, dynamic>> groupesDeECUEEnseignant(
    dynamic ecueId,
    dynamic enseignantId,
  ) {
    if (ecueId == null || enseignantId == null) return const [];
    final ids = affectations
        .where(
          (a) =>
              a['ecue_id'] == ecueId &&
              a['enseignant_id'] == enseignantId &&
              a['groupe_id'] != null,
        )
        .map((a) => a['groupe_id'])
        .toSet();
    return groupes.where((g) => ids.contains(g['id'])).toList();
  }

  /// Affectations « CM commun » d'un ECUE, éventuellement d'un enseignant.
  List<Map<String, dynamic>> affectationsMutualisees(
    dynamic ecueId, [
    dynamic enseignantId,
  ]) {
    if (ecueId == null) return const [];
    return affectations
        .where(
          (a) =>
              a['ecue_id'] == ecueId &&
              a['cm_commun'] == true &&
              (enseignantId == null || a['enseignant_id'] == enseignantId),
        )
        .toList();
  }

  /// Vrai lorsque le CM de cet ECUE est mutualisé (CM commun) : le cours est
  /// alors dispensé à tous les groupes du niveau, pas seulement au groupe
  /// affecté.
  bool cmMutualise(dynamic ecueId, [dynamic enseignantId]) =>
      affectationsMutualisees(ecueId, enseignantId).isNotEmpty;

  /// Tous les groupes des niveaux concernés par un CM mutualisé.
  List<Map<String, dynamic>> groupesMutualises(
    dynamic ecueId, [
    dynamic enseignantId,
  ]) {
    final idsNiveaux = <int>{};
    for (final affectation in affectationsMutualisees(ecueId, enseignantId)) {
      final groupe = _trouver(groupes, affectation['groupe_id']);
      final niveauId = groupe?['niveau_id'];
      if (niveauId is int) idsNiveaux.add(niveauId);
    }
    if (idsNiveaux.isEmpty) idsNiveaux.addAll(niveauxECUE(ecueId));
    return groupes.where((g) => idsNiveaux.contains(g['niveau_id'])).toList();
  }
}
