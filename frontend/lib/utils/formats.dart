import 'package:intl/intl.dart';

/// Fonctions de formatage pures (sans dépendance au Web) partagées par l'UI.
String formaterDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

String formaterDateLongue(DateTime date) => DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);

String formaterHeures(num valeur) {
  if (valeur == valeur.roundToDouble()) return '${valeur.toInt()} h';
  return '${valeur.toStringAsFixed(1).replaceAll('.', ',')} h';
}
