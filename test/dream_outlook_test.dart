import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/services/dream_outlook_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

FinancialGoal _goal({
  required double target,
  required double current,
  DateTime? deadline,
  String name = 'Viagem',
}) =>
    FinancialGoal(
      familyId: 'f1',
      name: name,
      targetAmount: target,
      currentAmount: current,
      deadline: deadline,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  final now = DateTime(2026, 6, 15);

  group('pickMainGoal', () {
    test('retorna null quando não há objetivos ativos', () {
      expect(pickMainGoal([]), isNull);
      expect(
        pickMainGoal([_goal(target: 100, current: 100)]), // concluído
        isNull,
      );
    });

    test('prioriza o de prazo mais próximo', () {
      final soon = _goal(
          target: 100, current: 10, name: 'Perto', deadline: DateTime(2026, 3));
      final far = _goal(
          target: 100, current: 90, name: 'Longe', deadline: DateTime(2027, 3));
      expect(pickMainGoal([far, soon])!.name, 'Perto');
    });

    test('sem prazo, escolhe o de maior progresso', () {
      final low = _goal(target: 100, current: 10, name: 'Baixo');
      final high = _goal(target: 100, current: 80, name: 'Alto');
      expect(pickMainGoal([low, high])!.name, 'Alto');
    });
  });

  group('buildDreamOutlook', () {
    test('sem objetivo → estado none (sem número)', () {
      final o = buildDreamOutlook(goal: null, monthlyNet: 1000, now: now);
      expect(o.hasGoal, isFalse);
      expect(o, same(DreamOutlook.none));
    });

    test('objetivo já conquistado', () {
      final o = buildDreamOutlook(
          goal: _goal(target: 100, current: 100), monthlyNet: 500, now: now);
      expect(o.headline, contains('conquistaram'));
    });

    test('sem sobra → esperança, sem terrorismo nem projeção', () {
      final o = buildDreamOutlook(
          goal: _goal(target: 1000, current: 200),
          monthlyNet: 0,
          now: now);
      expect(o.headline, contains('aproxima'));
      expect(o.headline, isNot(contains('antes')));
      expect(o.subline, contains('20%'));
    });

    test('no ritmo, chega antes do prazo', () {
      // faltam 5000; sobra 1000/mês → 5 meses; prazo em ~12 meses.
      final o = buildDreamOutlook(
        goal: _goal(
            target: 10000, current: 5000, deadline: DateTime(2027, 6, 15)),
        monthlyNet: 1000,
        now: now,
      );
      expect(o.headline, contains('antes do previsto'));
    });

    test('sem prazo, mostra ETA (chega em ...)', () {
      final o = buildDreamOutlook(
        goal: _goal(target: 10000, current: 5000),
        monthlyNet: 1000,
        now: now,
      );
      expect(o.headline, contains('chega em'));
    });

    test('sem prazo e muito perto → menos de 2 meses', () {
      final o = buildDreamOutlook(
        goal: _goal(target: 10000, current: 9500),
        monthlyNet: 1000,
        now: now,
      );
      expect(o.headline, contains('pouquíssimo'));
    });
  });
}
