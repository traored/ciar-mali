import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/utils/formats.dart';

void main() {
  group('Formater les heures', () {
    test('affiche un entier sans décimale', () {
      expect(formaterHeures(4), '4 h');
      expect(formaterHeures(0), '0 h');
    });

    test('affiche une demi-heure avec une virgule', () {
      expect(formaterHeures(2.5), '2,5 h');
      expect(formaterHeures(1.25), '1,3 h');
    });
  });
}
