import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/semestres_parite.dart';

/// Les semestres impairs sont 1, 3, 5, 7 et 9 ; les pairs 2, 4, 6, 8 et 10.
/// Le filtre par parité doit donc charger le semestre 7 (et le 9) de l'année
/// courante, pas seulement 1, 3 et 5.
void main() {
  Map<String, dynamic> semestre(
    int id,
    String nom, {
    String annee = '2026-2027',
  }) {
    return {
      'id': id,
      'nom': nom,
      'annee': annee,
      'actif': true,
      'semaines': 12,
    };
  }

  final liste = [
    semestre(5, 'Semestre 1'),
    semestre(27, 'Semestre 2'),
    semestre(26, 'Semestre 3'),
    semestre(28, 'Semestre 4'),
    semestre(10, 'Semestre 5'),
    semestre(11, 'Semestre 6'),
    semestre(29, 'Semestre 7'),
    semestre(30, 'Semestre 8'),
    semestre(31, 'Semestre 9'),
    semestre(32, 'Semestre 10'),
    semestre(1, 'Semestre 7', annee: '2025-2026'),
  ];

  List<int> ids(List<Map<String, dynamic>> semestres) =>
      semestres.map((s) => s['id'] as int).toList();

  test('les impairs incluent les semestres 7 et 9', () {
    final impairs = semestresDeParite(liste, periode: 1, annee: '2026-2027');
    expect(ids(impairs), [5, 26, 10, 29, 31]);
  });

  test('les pairs incluent les semestres 8 et 10', () {
    final pairs = semestresDeParite(liste, periode: 2, annee: '2026-2027');
    expect(ids(pairs), [27, 28, 11, 30, 32]);
  });

  test('seule l’année demandée est retenue', () {
    final impairs = semestresDeParite(liste, periode: 1, annee: '2025-2026');
    expect(ids(impairs), [1]);
  });

  test('un semestre inactif sans cours est écarté', () {
    final semestres = [
      semestre(29, 'Semestre 7')..['actif'] = false,
      semestre(31, 'Semestre 9')..['actif'] = false,
    ];
    expect(
      semestresDeParite(semestres, periode: 1, annee: '2026-2027'),
      isEmpty,
    );
    expect(
      ids(
        semestresDeParite(
          semestres,
          periode: 1,
          annee: '2026-2027',
          affectations: [
            {'semestre_id': 29},
          ],
        ),
      ),
      [29],
    );
  });

  test('le numéro est lu dans le nom du semestre', () {
    expect(numeroSemestre('Semestre 7'), 7);
    expect(numeroSemestre('Ingénieur 5 - Semestre 9'), 9);
    expect(numeroSemestre('Semestre'), isNull);
  });

  group('périodes des filtres partagés', () {
    test('les parités et les semestres 1 à 10 sont proposés', () {
      expect(periodesFiltre.take(2), ['impairs', 'pairs']);
      expect(periodesFiltre.skip(2), [
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
      ]);
    });

    test('les libellés reprennent les parités et les numéros', () {
      expect(libellePeriodeFiltre('impairs'), 'Impairs (1, 3, 5, 7, 9)');
      expect(libellePeriodeFiltre('pairs'), 'Pairs (2, 4, 6, 8, 10)');
      expect(libellePeriodeFiltre('5'), 'Semestre 5');
      expect(libelleCourtPeriode('pairs'), 'Pairs');
      expect(libelleCourtPeriode('9'), 'Semestre 9');
      expect(
        libellePeriodeComplete('impairs', '2026-2027'),
        'Semestres impairs 2026-2027',
      );
      expect(
        libellePeriodeComplete('5', '2026-2027'),
        'Semestre 5 · 2026-2027',
      );
    });

    test('une parité n’a pas de numéro, un numéro a sa parité', () {
      expect(numeroPeriode('impairs'), isNull);
      expect(numeroPeriode('pairs'), isNull);
      expect(numeroPeriode('5'), 5);
      expect(pariteDeNumero(5), 'impairs');
      expect(pariteDeNumero(6), 'pairs');
    });

    test('la période par défaut suit le numéro du semestre', () {
      expect(periodeDeSemestre({'nom': 'Master 1 - Semestre 3'}), 'impairs');
      expect(periodeDeSemestre({'nom': 'Semestre 8'}), 'pairs');
    });
  });

  group('semaine civile d’un semestre', () {
    final s1 = {
      'id': 5,
      'nom': 'Semestre 1',
      'annee': '2026-2027',
      'semaines': 16,
      'date_debut': '2026-10-12',
    };
    // Le semestre 7 démarre cinq semaines après le semestre 1.
    final s7 = {
      'id': 29,
      'nom': 'Semestre 7',
      'annee': '2026-2027',
      'semaines': 16,
      'date_debut': '2026-11-16',
    };

    test('le lundi de la semaine est calculé depuis le début', () {
      expect(lundiDeSemaine(s1, 1), DateTime(2026, 10, 12));
      expect(lundiDeSemaine(s1, 5), DateTime(2026, 11, 9));
      expect(lundiDeSemaine(s7, 1), DateTime(2026, 11, 16));
    });

    test('une même semaine civile donne des numéros différents', () {
      final lundi = DateTime(2026, 11, 9);
      expect(semaineDansSemestre(s1, lundi), 5);
      // Le semestre 7 n’a pas encore commencé : sa première semaine reste
      // affichée pour que ses séances soient visibles avec les autres.
      expect(semaineDansSemestre(s7, lundi), 1);
      expect(semaineDansSemestre(s7, DateTime(2026, 11, 16)), 1);
      expect(semaineDansSemestre(s7, DateTime(2026, 11, 23)), 2);
    });

    test('le numéro est borné aux semaines du semestre', () {
      // Bien après la fin du semestre 7 (16 semaines).
      expect(semaineDansSemestre(s7, DateTime(2027, 6, 1)), 16);
      // Bien avant son début.
      expect(semaineDansSemestre(s7, DateTime(2026, 1, 1)), 1);
    });

    test('un semestre sans date de début garde la semaine demandée', () {
      final sansDate = {'id': 40, 'nom': 'Semestre 9', 'semaines': 12};
      expect(
        semaineDansSemestre(sansDate, DateTime(2026, 11, 9), defaut: 4),
        4,
      );
      expect(lundiDeSemaine(sansDate, 3), isNull);
    });
  });
}
