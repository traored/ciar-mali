/// Fonctions pures partagées par l'espace « Surveillances ».
library;

const Map<String, String> _remplacementsAccents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};

/// Supprime les accents et la casse d'un texte.
String sansAccents(String texte) {
  final tampon = StringBuffer();
  for (final rune in texte.toLowerCase().runes) {
    final caractere = String.fromCharCode(rune);
    tampon.write(_remplacementsAccents[caractere] ?? caractere);
  }
  return tampon.toString();
}

/// Clé de comparaison d'un nom de surveillant.
///
/// Deux écritures du même nom (« M. DIARRA », « m. diarra ») doivent être
/// comptées ensemble dans les statistiques.
String cleSurveillant(String nom) =>
    sansAccents(nom).replaceAll('-', ' ').split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .join(' ');

/// Découpe une liste de surveillants saisie dans un champ ou un fichier Excel.
///
/// Les séparateurs acceptés sont le point-virgule, la barre verticale, la
/// barre oblique et le retour à la ligne.
List<String> decouperSurveillants(String texte) {
  final noms = <String>[];
  final vus = <String>{};
  for (final morceau in texte.split(RegExp(r'[;|/\r\n]+'))) {
    final nom = morceau.trim();
    if (nom.isEmpty) continue;
    final cle = cleSurveillant(nom);
    if (cle.isEmpty || !vus.add(cle)) continue;
    noms.add(nom);
  }
  return noms;
}

/// Durée lisible : 120 → « 2 h », 90 → « 1 h 30 », 45 → « 45 min ».
String formaterDuree(int? minutes) {
  if (minutes == null || minutes <= 0) return '—';
  final heures = minutes ~/ 60;
  final reste = minutes % 60;
  if (heures == 0) return '$reste min';
  if (reste == 0) return '$heures h';
  return '$heures h ${reste.toString().padLeft(2, '0')}';
}

/// Durée totale lisible pour les statistiques (ex. « 12 h 30 »).
String formaterDureeTotale(int? minutes) => formaterDuree(minutes);
