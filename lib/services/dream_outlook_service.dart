import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import 'ai/ai_write_tick.dart';

/// "Seu sonho" — traduz o objetivo principal da família em uma frase de
/// esperança e proximidade, baseada no ritmo real de sobra (receitas −
/// despesas). Determinístico, sem IA: o texto é pré-computado para a Home ser
/// lida em 3 segundos. Não mostra só progresso — mostra como as decisões de
/// hoje aproximam o sonho.
class DreamOutlook {
  const DreamOutlook({
    required this.goal,
    required this.monthlyNet,
    required this.headline,
    required this.subline,
  });

  /// Objetivo principal escolhido; null quando a família ainda não definiu um.
  final FinancialGoal? goal;

  /// Sobra mensal suavizada (média de ~90 dias). Pode ser ≤ 0.
  final double monthlyNet;

  /// Frase emocional/projeção (o que importa ler).
  final String headline;

  /// Âncora concreta (faltam R$X • Y%).
  final String subline;

  bool get hasGoal => goal != null;
  double get progress => goal?.progress ?? 0;

  /// Estado sem objetivo: convida a família a sonhar, sem número nenhum.
  static const none = DreamOutlook(
    goal: null,
    monthlyNet: 0,
    headline: 'Qual é o sonho da família?',
    subline: 'Defina um objetivo e eu mostro, todo dia, o quanto você já chegou perto.',
  );
}

/// Escolhe o "sonho principal": entre os objetivos ainda não concluídos,
/// prioriza o de prazo mais próximo; sem prazo, o de maior progresso.
FinancialGoal? pickMainGoal(List<FinancialGoal> goals) {
  final active = goals
      .where((g) => g.targetAmount > 0 && g.currentAmount < g.targetAmount)
      .toList();
  if (active.isEmpty) return null;

  final withDeadline = active.where((g) => g.deadline != null).toList()
    ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
  if (withDeadline.isNotEmpty) return withDeadline.first;

  active.sort((a, b) => b.progress.compareTo(a.progress));
  return active.first;
}

/// Constrói a frase do card "Seu sonho" a partir do objetivo e da sobra mensal
/// suavizada. Puro e testável; `now` é injetável.
DreamOutlook buildDreamOutlook({
  required FinancialGoal? goal,
  required double monthlyNet,
  DateTime? now,
}) {
  if (goal == null) return DreamOutlook.none;
  final today = now ?? DateTime.now();

  final remaining = goal.targetAmount - goal.currentAmount;
  final pct = (goal.progress * 100).round();

  // Já conquistado (raro, mas honesto).
  if (remaining <= 0) {
    return DreamOutlook(
      goal: goal,
      monthlyNet: monthlyNet,
      headline: 'Vocês conquistaram: ${goal.name}! 🎉',
      subline: '100% concluído — hora de sonhar o próximo.',
    );
  }

  final subline = 'Faltam ${remaining.brl} • $pct% do caminho';

  // Sem ritmo de sobra: nada de projeção nem terrorismo — só esperança e
  // proximidade.
  if (monthlyNet <= 0) {
    return DreamOutlook(
      goal: goal,
      monthlyNet: monthlyNet,
      headline: 'Todo valor guardado aproxima ${goal.name}. Bora começar essa semana? 🌱',
      subline: subline,
    );
  }

  final monthsNeeded = remaining / monthlyNet; // > 0

  if (goal.deadline != null) {
    final monthsLeft = goal.deadline!.difference(today).inDays / 30.44;
    if (monthsLeft <= 0) {
      return DreamOutlook(
        goal: goal,
        monthlyNet: monthlyNet,
        headline: 'Falta um empurrãozinho para ${goal.name}. Guardando um pouco mais, você chega. 💪',
        subline: subline,
      );
    }
    final diff = monthsLeft - monthsNeeded; // > 0 => antes do prazo
    if (diff >= 1) {
      final n = diff.round();
      return DreamOutlook(
        goal: goal,
        monthlyNet: monthlyNet,
        headline: 'Nesse ritmo, ${goal.name} chega $n ${n == 1 ? 'mês' : 'meses'} antes do previsto! 🎉',
        subline: subline,
      );
    }
    if (diff <= -1) {
      return DreamOutlook(
        goal: goal,
        monthlyNet: monthlyNet,
        headline: 'Guardando um pouco mais por mês, ${goal.name} volta pro prazo. Você está quase lá. 💪',
        subline: subline,
      );
    }
    return DreamOutlook(
      goal: goal,
      monthlyNet: monthlyNet,
      headline: 'Você está bem no caminho de ${goal.name} — dentro do prazo. 👏',
      subline: subline,
    );
  }

  // Sem prazo: mostra quando chega no ritmo atual (ETA), sempre com esperança.
  if (monthsNeeded <= 1.5) {
    return DreamOutlook(
      goal: goal,
      monthlyNet: monthlyNet,
      headline: 'Falta pouquíssimo para ${goal.name} — menos de 2 meses no ritmo atual! 🎉',
      subline: subline,
    );
  }
  final eta = today.add(Duration(days: (monthsNeeded * 30.44).ceil()));
  return DreamOutlook(
    goal: goal,
    monthlyNet: monthlyNet,
    headline: 'Nesse ritmo, ${goal.name} chega em ${eta.monthYear}. Falta pouco! ✨',
    subline: subline,
  );
}

/// Provider da Home: escolhe o sonho principal e calcula a sobra mensal
/// suavizada (~90 dias) para montar a frase. Uma consulta leve de fluxo de
/// caixa + a lista de objetivos; sem IA, sem custo.
final dreamOutlookProvider = FutureProvider.autoDispose<DreamOutlook>((ref) async {
  ref.watch(aiWriteTickProvider); // dados vivos
  final goals = await ref.watch(goalRepositoryProvider).all();
  final goal = pickMainGoal(goals);
  if (goal == null) return DreamOutlook.none;

  final flow =
      await ref.watch(analyticsRepositoryProvider).dailyCashFlow(daysBack: 90);
  final totalNet = flow.fold<double>(0, (s, d) => s + d.revenue - d.expense);
  final monthlyNet = totalNet / 3.0; // ~90 dias ≈ 3 meses (suaviza volatilidade)

  return buildDreamOutlook(goal: goal, monthlyNet: monthlyNet);
});
