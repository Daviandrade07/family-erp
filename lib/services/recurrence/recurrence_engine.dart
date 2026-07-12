/// Motor de recorrência — PURO (sem Supabase, sem Flutter), 100% testável.
///
/// Toda a agenda é determinada por `startedAt` + `frequency` + `intervalCount`
/// (a cada N frequências). Ocorrências são ancoradas em `startedAt`:
/// - semanal: startedAt, +7·N dias, +14·N dias…
/// - mensal: mesmo dia do mês, com **clamp de fim de mês** (dia 31 → 28/29 em
///   fevereiro, 30 em abril…);
/// - anual: mesmo dia/mês, com clamp de 29/02 em ano não-bissexto.
enum RecurrenceFrequency { weekly, monthly, yearly }

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A k-ésima ocorrência (k=0 é a primeira, em [startedAt]).
DateTime _occurrence(
    DateTime startedAt, RecurrenceFrequency f, int step, int k) {
  final s = _dateOnly(startedAt);
  switch (f) {
    case RecurrenceFrequency.weekly:
      // Via construtor (não Duration) para evitar drift de horário de verão.
      return DateTime(s.year, s.month, s.day + 7 * step * k);
    case RecurrenceFrequency.monthly:
      final m0 = s.month - 1 + step * k;
      final year = s.year + m0 ~/ 12;
      final month = m0 % 12 + 1;
      final lastDay = DateTime(year, month + 1, 0).day; // dia 0 = último do mês
      return DateTime(year, month, s.day <= lastDay ? s.day : lastDay);
    case RecurrenceFrequency.yearly:
      final year = s.year + step * k;
      final lastDay = DateTime(year, s.month + 1, 0).day;
      return DateTime(year, s.month, s.day <= lastDay ? s.day : lastDay);
  }
}

int _step(int intervalCount) => intervalCount < 1 ? 1 : intervalCount;

/// Próxima ocorrência ESTRITAMENTE após [after].
DateTime nextOccurrence({
  required DateTime startedAt,
  required RecurrenceFrequency frequency,
  required int intervalCount,
  required DateTime after,
}) {
  final step = _step(intervalCount);
  final a = _dateOnly(after);
  for (var k = 0; k <= 100000; k++) {
    final occ = _occurrence(startedAt, frequency, step, k);
    if (occ.isAfter(a)) return occ;
  }
  return _occurrence(startedAt, frequency, step, 100000); // trava de segurança
}

/// Ocorrências devidas em (after, through] — usado para "lançar o que ficou
/// pendente" quando a pessoa pulou meses (abriu o app depois).
List<DateTime> dueOccurrences({
  required DateTime startedAt,
  required RecurrenceFrequency frequency,
  required int intervalCount,
  required DateTime after,
  required DateTime through,
}) {
  final step = _step(intervalCount);
  final a = _dateOnly(after);
  final t = _dateOnly(through);
  final out = <DateTime>[];
  for (var k = 0; k <= 100000; k++) {
    final occ = _occurrence(startedAt, frequency, step, k);
    if (occ.isAfter(t)) break;
    if (occ.isAfter(a)) out.add(occ);
  }
  return out;
}

/// Quantas ocorrências já aconteceram de [startedAt] até [asOf] (inclusive) —
/// insumo do mordomo para "repete há N vezes/meses".
int occurrencesSoFar({
  required DateTime startedAt,
  required RecurrenceFrequency frequency,
  required int intervalCount,
  required DateTime asOf,
}) {
  final step = _step(intervalCount);
  final t = _dateOnly(asOf);
  var count = 0;
  for (var k = 0; k <= 100000; k++) {
    final occ = _occurrence(startedAt, frequency, step, k);
    if (occ.isAfter(t)) break;
    count++;
  }
  return count;
}
