import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../data/repositories/repositories.dart';
import 'ai/ai_write_tick.dart';
import 'dream_outlook_service.dart';

/// Motor de insights do Kinfin — transforma os números do mês numa
/// HISTÓRIA em 5 respostas, sempre nesta ordem:
///   1. O que aconteceu?  2. Por quê?  3. Preciso me preocupar?
///   4. Próximo passo     5. Como isso afeta meu sonho?
///
/// Puro e determinístico (sem LLM): barato, offline, testável e sempre
/// honesto. É o mesmo cérebro que alimenta o Analytics narrativo e, no
/// futuro, os cards contextuais. Tom inviolável: calmo, sem terrorismo —
/// até o pior mês é contado com um caminho para frente.

enum StoryMood { tranquilo, atencao, cuidado }

class MonthStory {
  const MonthStory({
    required this.mood,
    required this.whatHappened,
    required this.why,
    required this.shouldIWorry,
    required this.nextStep,
    required this.dreamImpact,
  });

  final StoryMood mood;
  final String whatHappened;
  final String why;
  final String shouldIWorry;
  final String nextStep;
  final String dreamImpact;

  bool get isEmpty => whatHappened.isEmpty;
}

/// Constrói a história do mês. `avgMonthlyExpenses90d <= 0` significa "sem
/// histórico suficiente" (o motor admite que ainda está aprendendo o ritmo).
MonthStory buildMonthStory({
  required double monthExpenses,
  required double monthRevenue,
  required double avgMonthlyExpenses90d,
  String? topCategory,
  double topCategoryTotal = 0,
  DreamOutlook? dream,
}) {
  // ---- Mês ainda sem movimentações: convite, não vazio. ----
  if (monthExpenses <= 0 && monthRevenue <= 0) {
    return MonthStory(
      mood: StoryMood.tranquilo,
      whatHappened: 'O mês ainda não tem movimentações registradas.',
      why: 'Sem registros, não consigo contar a história de vocês.',
      shouldIWorry: 'Não — é só começar.',
      nextStep: 'Registre o primeiro gasto ou receita (pode ser por voz, '
          'na conversa comigo).',
      dreamImpact: dream?.hasGoal == true
          ? 'Seu sonho "${dream!.goal!.name}" está esperando os primeiros passos do mês.'
          : 'Defina um sonho em Metas e eu mostro como cada mês te aproxima dele.',
    );
  }

  final saved = monthRevenue - monthExpenses;
  final hasBaseline = avgMonthlyExpenses90d > 0;
  final vsAvg =
      hasBaseline ? (monthExpenses - avgMonthlyExpenses90d) / avgMonthlyExpenses90d : 0.0;

  // ---- 1 · O que aconteceu ----
  final whatHappened = monthRevenue > 0
      ? 'Vocês gastaram ${monthExpenses.brl} este mês, com ${monthRevenue.brl} de entradas '
          '(${saved >= 0 ? 'sobraram ${saved.brl}' : 'faltaram ${(-saved).brl}'}).'
      : 'Vocês gastaram ${monthExpenses.brl} este mês — as entradas ainda não foram registradas.';

  // ---- 2 · Por quê ----
  final parts = <String>[];
  if (topCategory != null && topCategoryTotal > 0 && monthExpenses > 0) {
    final share = (topCategoryTotal / monthExpenses * 100).round();
    parts.add('O maior peso foi $topCategory (${topCategoryTotal.brl}, '
        '$share% dos gastos)');
  }
  if (hasBaseline) {
    if (vsAvg > 0.10) {
      parts.add('o mês está ${(vsAvg * 100).round()}% acima do ritmo normal de vocês');
    } else if (vsAvg < -0.10) {
      parts.add('o mês está ${(-vsAvg * 100).round()}% abaixo do ritmo normal — bom sinal');
    } else {
      parts.add('o ritmo está dentro do normal de vocês');
    }
  } else {
    parts.add('ainda estou aprendendo o ritmo da casa — as comparações melhoram '
        'com mais meses de registro');
  }
  final why = '${parts.join(' e ')}.';

  // ---- 3 · Preciso me preocupar? (veredito calmo) ----
  final StoryMood mood;
  final String shouldIWorry;
  if (monthRevenue > 0 && saved < 0) {
    mood = StoryMood.cuidado;
    shouldIWorry = 'Vale atenção: este mês saiu mais do que entrou. Acontece — '
        'o importante é ajustar o ritmo agora, sem pânico.';
  } else if (hasBaseline && vsAvg > 0.15) {
    mood = StoryMood.atencao;
    shouldIWorry = 'Um ponto de atenção: o mês está mais caro que o costume, '
        'mas ainda sob controle.';
  } else if (monthRevenue <= 0) {
    mood = StoryMood.atencao;
    shouldIWorry = 'Ainda não dá para avaliar — registre as entradas do mês '
        'para eu comparar com os gastos.';
  } else {
    mood = StoryMood.tranquilo;
    shouldIWorry = 'Não. Os gastos cabem nas entradas e o ritmo está saudável.';
  }

  // ---- 4 · Próximo passo (sempre acionável) ----
  final String nextStep;
  switch (mood) {
    case StoryMood.cuidado:
      nextStep = topCategory != null
          ? 'Reveja $topCategory e adie o que puder esta semana — pequenos '
              'cortes já viram o jogo.'
          : 'Adie os gastos que puderem esperar esta semana — pequenos cortes '
              'já viram o jogo.';
    case StoryMood.atencao:
      nextStep = topCategory != null
          ? 'Segure $topCategory nesta semana que o mês volta ao ritmo.'
          : 'Segure os gastos maiores nesta semana que o mês volta ao ritmo.';
    case StoryMood.tranquilo:
      nextStep = saved > 0
          ? 'Continue assim — e, se quiser, guarde parte dos ${saved.brl} que '
              'sobraram para o sonho de vocês.'
          : 'Continue nesse ritmo e registre tudo para a história ficar completa.';
  }

  // ---- 5 · Como isso afeta meu sonho? (sempre com esperança) ----
  final String dreamImpact;
  if (dream == null || !dream.hasGoal) {
    dreamImpact = 'Defina um sonho em Metas e eu mostro, todo mês, o quanto '
        'vocês chegaram mais perto.';
  } else {
    // Reusa a frase de ritmo do DreamOutlook (já calibrada para esperança).
    dreamImpact = dream.headline;
  }

  return MonthStory(
    mood: mood,
    whatHappened: whatHappened,
    why: why,
    shouldIWorry: shouldIWorry,
    nextStep: nextStep,
    dreamImpact: dreamImpact,
  );
}

/// Provider vivo da história do mês: recompõe quando a IA grava algo.
final monthStoryProvider = FutureProvider.autoDispose<MonthStory>((ref) async {
  ref.watch(aiWriteTickProvider); // dados vivos

  final analytics = ref.watch(analyticsRepositoryProvider);
  final kpis = await analytics.kpis();
  final byCategory = await analytics.monthSpendByCategory();

  // Ritmo dos últimos ~90 dias (mesma suavização do DreamOutlook).
  final history =
      await ref.watch(transactionRepositoryProvider).recentExpenses(days: 90);
  final avg90 = history.isEmpty
      ? 0.0
      : history.fold<double>(0, (s, t) => s + t.amount) / 3.0;

  final top = byCategory.isEmpty
      ? null
      : byCategory.reduce((a, b) => a.total >= b.total ? a : b);

  final dream = await ref.watch(dreamOutlookProvider.future);

  return buildMonthStory(
    monthExpenses: kpis.monthExpenses,
    monthRevenue: kpis.monthRevenue,
    avgMonthlyExpenses90d: avg90,
    topCategory: top?.category,
    topCategoryTotal: top?.total ?? 0,
    dream: dream,
  );
});
