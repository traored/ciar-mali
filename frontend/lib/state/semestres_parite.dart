/// Semestres impairs et pairs d'une année universitaire.
///
/// Les semestres impairs sont 1, 3, 5, 7 et 9 ; les semestres pairs 2, 4, 6,
/// 8 et 10. Cette logique est partagée par « Mes cours » et l'emploi du temps
/// pour que le filtre par parité charge bien le semestre 7 (et les suivants).
library;

/// Numéro d'un semestre d'après son nom (« Semestre 3 » → 3).
int? numeroSemestre(String nom) {
  final correspondance = RegExp(
    r'semestre\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(nom);
  return correspondance == null ? null : int.tryParse(correspondance.group(1)!);
}

/// Périodes proposées par les filtres d'année et de semestre.
///
/// Les parités agrègent plusieurs semestres ; un numéro cible un semestre
/// précis (« 5 » pour « Semestre 5 »). Les filtres d'en-tête et de la page
/// « Heures enseignants » partagent cette liste.
const List<String> periodesFiltre = [
  'impairs',
  'pairs',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '10',
];

/// Libellé complet d'une période dans les menus déroulants.
String libellePeriodeFiltre(String periode) {
  if (periode == 'impairs') return 'Impairs (1, 3, 5, 7, 9)';
  if (periode == 'pairs') return 'Pairs (2, 4, 6, 8, 10)';
  return 'Semestre $periode';
}

/// Libellé court d'une période (bouton fermé sur petit écran).
String libelleCourtPeriode(String periode) {
  if (periode == 'impairs') return 'Impairs';
  if (periode == 'pairs') return 'Pairs';
  return 'Semestre $periode';
}

/// Libellé d'une période pour les sous-titres.
String libellePeriodeComplete(String periode, String annee) {
  if (periode == 'impairs') return 'Semestres impairs $annee';
  if (periode == 'pairs') return 'Semestres pairs $annee';
  return 'Semestre $periode · $annee';
}

/// Numéro de semestre d'une période précise, sinon `null` (parité).
int? numeroPeriode(String periode) =>
    periode == 'impairs' || periode == 'pairs' ? null : int.tryParse(periode);

/// Parité (« impairs » ou « pairs ») d'un numéro de semestre.
String pariteDeNumero(int numero) => numero.isOdd ? 'impairs' : 'pairs';

/// Période correspondant à un semestre : sa parité.
///
/// Un semestre sans numéro dans son nom retombe sur la parité de la période
/// de l'année (impairs de septembre à janvier, pairs ensuite).
String periodeDeSemestre(Map<String, dynamic>? semestre) {
  final numero = numeroSemestre('${semestre?['nom'] ?? ''}');
  if (numero == null) {
    final mois = DateTime.now().month;
    return (mois >= 9 || mois <= 1) ? 'impairs' : 'pairs';
  }
  return pariteDeNumero(numero);
}

/// Semestres d'une parité (`1` = impairs, `2` = pairs) pour [annee].
///
/// Les semestres désactivés et sans affectation ni séance sont écartés ; un
/// semestre où l'enseignant a réellement des cours reste affiché même s'il
/// n'est pas marqué actif.
List<Map<String, dynamic>> semestresDeParite(
  List<Map<String, dynamic>> semestres, {
  required int periode,
  required String annee,
  Iterable<Map<String, dynamic>> affectations = const [],
  Set<int> avecSeances = const {},
}) {
  final liste = <Map<String, dynamic>>[];
  for (final semestre in semestres) {
    if ('${semestre['annee'] ?? ''}' != annee) continue;
    final numero = numeroSemestre('${semestre['nom'] ?? ''}');
    if (numero == null || (numero.isOdd ? 1 : 2) != periode) continue;
    final id = semestre['id'];
    final affecte = affectations.any(
      (affectation) => affectation['semestre_id'] == id,
    );
    if (semestre['actif'] != true && !affecte && !avecSeances.contains(id)) {
      continue;
    }
    liste.add({...semestre, '_numero': numero});
  }
  liste.sort((a, b) => (a['_numero'] as int).compareTo(b['_numero'] as int));
  return liste;
}

/// Date de début d'un semestre, si elle est connue.
DateTime? dateDebutSemestre(Map<String, dynamic> semestre) {
  final brut = semestre['date_debut'];
  if (brut == null) return null;
  return DateTime.tryParse('$brut');
}

/// Lundi de la semaine [semaine] du [semestre].
DateTime? lundiDeSemaine(Map<String, dynamic> semestre, int semaine) {
  final debut = dateDebutSemestre(semestre);
  if (debut == null) return null;
  return DateTime(debut.year, debut.month, debut.day + (semaine - 1) * 7);
}

/// Semaine du [semestre] qui contient le lundi [lundi].
///
/// Les semestres d'une même parité ne commencent pas tous le même jour : le
/// semestre 7 démarre par exemple cinq semaines après le semestre 1. La grille
/// groupée affiche une même semaine civile ; chaque semestre doit donc être
/// interrogé sur la semaine qui la recouvre. Le numéro est borné aux semaines
/// réelles du semestre pour que ses séances restent visibles avant son
/// ouverture (première semaine) et après sa clôture (dernière semaine).
int semaineDansSemestre(
  Map<String, dynamic> semestre,
  DateTime lundi, {
  int defaut = 1,
}) {
  final debut = dateDebutSemestre(semestre);
  if (debut == null) return defaut;
  final lundiSemestre = DateTime(debut.year, debut.month, debut.day);
  final decalage = lundi.difference(lundiSemestre).inDays;
  final numero = (decalage / 7).floor() + 1;
  final brut = (semestre['semaines'] as int?) ?? 1;
  final semaines = brut < 1 ? 1 : brut;
  return numero.clamp(1, semaines);
}
