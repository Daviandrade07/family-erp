import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/services/dream_outlook_service.dart';
import 'package:kinfin/services/insights_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Suíte permanente do motor de insights: trava os 5 pilares da história do
/// mês e o tom calmo (nunca terrorismo), incluindo o pilar do sonho.
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  DreamOutlook dream({double net = 1000}) => buildDreamOutlook(
        goal: const FinancialGoal(
          familyId: 'f1',
          name: 'Viagem',
          targetAmount: 10000,
          currentAmount: 5000,
        ),
        monthlyNet: net,
        now: DateTime(2026, 6, 15),
      );

  group('buildMonthStory — vereditos', () {
    test('mês saudável → tranquilo, sem alarme', () {
      final s = buildMonthStory(
        monthExpenses: 2000,
        monthRevenue: 3000,
        avgMonthlyExpenses90d: 2100,
        topCategory: 'Mercado',
        topCategoryTotal: 800,
        dream: dream(),
      );
      expect(s.mood, StoryMood.tranquilo);
      expect(s.shouldIWorry, contains('Não'));
      expect(s.whatHappened, contains('sobraram'));
      expect(s.why, contains('Mercado'));
      expect(s.why, contains('40%'));
    });

    test('mês acima do ritmo mas dentro das entradas → atenção', () {
      final s = buildMonthStory(
        monthExpenses: 2600,
        monthRevenue: 3000,
        avgMonthlyExpenses90d: 2000,
        topCategory: 'Lazer',
        topCategoryTotal: 900,
      );
      expect(s.mood, StoryMood.atencao);
      expect(s.nextStep, contains('Lazer'));
    });

    test('saiu mais do que entrou → cuidado, mas com caminho (sem pânico)', () {
      final s = buildMonthStory(
        monthExpenses: 3500,
        monthRevenue: 3000,
        avgMonthlyExpenses90d: 2800,
        topCategory: 'Mercado',
        topCategoryTotal: 1200,
      );
      expect(s.mood, StoryMood.cuidado);
      expect(s.shouldIWorry, contains('sem pânico'));
      expect(s.nextStep, contains('Mercado'));
    });

    test('sem histórico → admite que está aprendendo, não inventa comparação',
        () {
      final s = buildMonthStory(
        monthExpenses: 1000,
        monthRevenue: 2000,
        avgMonthlyExpenses90d: 0,
      );
      expect(s.why, contains('aprendendo'));
    });

    test('mês vazio → convite para começar, não tela morta', () {
      final s = buildMonthStory(
        monthExpenses: 0,
        monthRevenue: 0,
        avgMonthlyExpenses90d: 0,
      );
      expect(s.mood, StoryMood.tranquilo);
      expect(s.nextStep.toLowerCase(), contains('registre'));
    });
  });

  group('buildMonthStory — pilar do sonho', () {
    test('com sonho → usa a frase de ritmo (esperança)', () {
      final s = buildMonthStory(
        monthExpenses: 2000,
        monthRevenue: 3000,
        avgMonthlyExpenses90d: 2000,
        dream: dream(),
      );
      expect(s.dreamImpact, contains('Viagem'));
    });

    test('sem sonho → convida a sonhar, não cobra', () {
      final s = buildMonthStory(
        monthExpenses: 2000,
        monthRevenue: 3000,
        avgMonthlyExpenses90d: 2000,
      );
      expect(s.dreamImpact, contains('Defina um sonho'));
    });
  });

  group('buildMonthStory — tom calmo inviolável', () {
    test('nem o pior cenário usa vocabulário de terrorismo', () {
      final s = buildMonthStory(
        monthExpenses: 9000,
        monthRevenue: 1000,
        avgMonthlyExpenses90d: 2000,
        topCategory: 'Lazer',
        topCategoryTotal: 5000,
      );
      final blob =
          '${s.whatHappened} ${s.why} ${s.shouldIWorry} ${s.nextStep} ${s.dreamImpact}'
              .toLowerCase();
      for (final banned in [
        'urgente', 'grave', 'péssimo', 'desastre', 'nunca', 'perigo',
        'alarmante', 'crise',
      ]) {
        expect(blob, isNot(contains(banned)),
            reason: 'história não pode conter "$banned"');
      }
    });
  });
}
