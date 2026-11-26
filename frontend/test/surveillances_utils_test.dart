import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/utils/surveillances.dart';

void main() {
  test('cleSurveillant ignore accents, casse et espaces', () {
    expect(cleSurveillant('  Mme  TRAORÉ '), cleSurveillant('mme traore'));
    expect(cleSurveillant('M. DIARRA'), 'm. diarra');
    expect(cleSurveillant('Jean-Pierre'), cleSurveillant('jean pierre'));
  });

  test('decouperSurveillants accepte les séparateurs prévus', () {
    expect(
      decouperSurveillants('M. DIARRA ; Mme TRAORÉ|M. KEITA/Mme COULIBALY'),
      ['M. DIARRA', 'Mme TRAORÉ', 'M. KEITA', 'Mme COULIBALY'],
    );
    expect(decouperSurveillants('  '), isEmpty);
    expect(decouperSurveillants('A ; a ; B'), ['A', 'B']);
    expect(decouperSurveillants('Ligne 1\nLigne 2'), ['Ligne 1', 'Ligne 2']);
  });

  test('formaterDuree', () {
    expect(formaterDuree(120), '2 h');
    expect(formaterDuree(90), '1 h 30');
    expect(formaterDuree(45), '45 min');
    expect(formaterDuree(null), '—');
    expect(formaterDuree(0), '—');
  });
}
