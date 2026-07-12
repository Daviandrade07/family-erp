import 'package:flutter_test/flutter_test.dart';
import 'package:family_erp/services/recurrence/recurrence_engine.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  group('nextOccurrence — mensal', () {
    test('avança um mês a partir do dia âncora', () {
      final next = nextOccurrence(
        startedAt: d(2025, 1, 15),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2025, 1, 20),
      );
      expect(next, d(2025, 2, 15));
    });

    test('estritamente após: no próprio dia âncora, vai pro mês seguinte', () {
      final next = nextOccurrence(
        startedAt: d(2025, 1, 15),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2025, 1, 15),
      );
      expect(next, d(2025, 2, 15));
    });

    test('fim de mês: dia 31 vira 28 em fevereiro (não-bissexto)', () {
      final next = nextOccurrence(
        startedAt: d(2025, 1, 31),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2025, 1, 31),
      );
      expect(next, d(2025, 2, 28));
    });

    test('fim de mês: dia 31 vira 29 em fevereiro bissexto (2024)', () {
      final next = nextOccurrence(
        startedAt: d(2024, 1, 31),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2024, 1, 31),
      );
      expect(next, d(2024, 2, 29));
    });

    test('intervalo 2 pula um mês', () {
      final next = nextOccurrence(
        startedAt: d(2025, 1, 10),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 2,
        after: d(2025, 1, 10),
      );
      expect(next, d(2025, 3, 10));
    });
  });

  group('dueOccurrences — pulei meses (catch-up)', () {
    test('gera as 3 ocorrências perdidas entre last_run e hoje', () {
      final due = dueOccurrences(
        startedAt: d(2025, 1, 10),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2025, 1, 10), // last_run
        through: d(2025, 4, 12), // hoje
      );
      expect(due, [d(2025, 2, 10), d(2025, 3, 10), d(2025, 4, 10)]);
    });

    test('fim de mês no catch-up mantém o clamp', () {
      final due = dueOccurrences(
        startedAt: d(2025, 1, 31),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2024, 12, 31),
        through: d(2025, 4, 30),
      );
      expect(due, [d(2025, 1, 31), d(2025, 2, 28), d(2025, 3, 31), d(2025, 4, 30)]);
    });

    test('nada devido quando o período não contém ocorrência', () {
      final due = dueOccurrences(
        startedAt: d(2025, 1, 10),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2025, 1, 11),
        through: d(2025, 2, 5),
      );
      expect(due, isEmpty);
    });
  });

  group('semanal vs mensal', () {
    test('semanal avança 7 dias', () {
      final next = nextOccurrence(
        startedAt: d(2025, 1, 6), // segunda-feira
        frequency: RecurrenceFrequency.weekly,
        intervalCount: 1,
        after: d(2025, 1, 6),
      );
      expect(next, d(2025, 1, 13));
    });

    test('semanal intervalo 2 avança 14 dias', () {
      final next = nextOccurrence(
        startedAt: d(2025, 1, 6),
        frequency: RecurrenceFrequency.weekly,
        intervalCount: 2,
        after: d(2025, 1, 6),
      );
      expect(next, d(2025, 1, 20));
    });

    test('semanal catch-up de 3 semanas', () {
      final due = dueOccurrences(
        startedAt: d(2025, 1, 6),
        frequency: RecurrenceFrequency.weekly,
        intervalCount: 1,
        after: d(2025, 1, 6),
        through: d(2025, 1, 28),
      );
      expect(due, [d(2025, 1, 13), d(2025, 1, 20), d(2025, 1, 27)]);
    });

    test('mesma âncora e intervalo: semanal (+7d) difere de mensal (+1 mês)', () {
      final semanal = nextOccurrence(
        startedAt: d(2025, 1, 6),
        frequency: RecurrenceFrequency.weekly,
        intervalCount: 1,
        after: d(2025, 1, 6),
      );
      final mensal = nextOccurrence(
        startedAt: d(2025, 1, 6),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        after: d(2025, 1, 6),
      );
      expect(semanal, d(2025, 1, 13));
      expect(mensal, d(2025, 2, 6));
      expect(semanal == mensal, isFalse);
    });
  });

  group('anual', () {
    test('29/02 vira 28/02 em ano não-bissexto', () {
      final next = nextOccurrence(
        startedAt: d(2024, 2, 29),
        frequency: RecurrenceFrequency.yearly,
        intervalCount: 1,
        after: d(2024, 2, 29),
      );
      expect(next, d(2025, 2, 28));
    });
  });

  group('occurrencesSoFar — insumo do mordomo', () {
    test('conta as ocorrências de started até hoje (repete há N meses)', () {
      final n = occurrencesSoFar(
        startedAt: d(2025, 1, 15),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        asOf: d(2025, 4, 15),
      );
      expect(n, 4); // jan, fev, mar, abr
    });

    test('não conta ocorrência futura', () {
      final n = occurrencesSoFar(
        startedAt: d(2025, 1, 15),
        frequency: RecurrenceFrequency.monthly,
        intervalCount: 1,
        asOf: d(2025, 4, 14), // um dia antes de abr/15
      );
      expect(n, 3);
    });
  });
}
