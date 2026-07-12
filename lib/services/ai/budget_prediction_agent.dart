import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// Prediction produced by the agent for one budget category.
class BudgetPrediction {
  const BudgetPrediction({
    required this.budgetId,
    required this.category,
    required this.limitAmount,
    required this.spent,
    required this.projectedTotal,
    required this.overflowProbability,
  });

  final String budgetId;
  final String category;
  final double limitAmount;
  final double spent;

  /// Expected total spend at month end (current pace + historical baseline).
  final double projectedTotal;

  /// 0..1 probability the category exceeds its limit before month end.
  final double overflowProbability;

  double get usedRatio => limitAmount == 0 ? 0 : spent / limitAmount;
  double get projectedRatio =>
      limitAmount == 0 ? 0 : projectedTotal / limitAmount;

  bool get isAtRisk => overflowProbability >= 0.5;

  String get riskLabel => overflowProbability >= 0.8
      ? 'Estouro quase certo'
      : overflowProbability >= 0.5
          ? 'Risco alto de estouro'
          : overflowProbability >= 0.25
              ? 'Atenção ao ritmo'
              : 'Dentro do previsto';
}

/// Background analytical agent: projects month-end spend per category and
/// converts the projection into an overflow probability.
///
/// Model: blends the current month's daily pace with the 90-day historical
/// daily average (weighted by how far into the month we are), then measures
/// the daily-spend volatility of the category and maps
/// (projected - limit) / sigma through a logistic curve.
class BudgetPredictionAgent {
  BudgetPredictionAgent(this._analytics, this._transactions);

  final AnalyticsRepository _analytics;
  final TransactionRepository _transactions;

  Future<List<BudgetPrediction>> run() async {
    final usage = await _analytics.budgetUsage();
    if (usage.isEmpty) return const [];

    final history = await _transactions.recentExpenses(days: 120);
    final byCategory = groupBy(history, (Transaction t) => t.category);

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day;
    final daysLeft = daysInMonth - dayOfMonth;

    return usage.map((u) {
      final currentPace = dayOfMonth == 0 ? 0.0 : u.spent / dayOfMonth;

      // Confidence in current pace grows through the month.
      final w = dayOfMonth / daysInMonth;
      final blendedDaily =
          w * currentPace + (1 - w) * u.avgDailyHistory;

      final projected = u.spent + blendedDaily * daysLeft;

      // Daily volatility from history → uncertainty of the projection.
      final txs = byCategory[u.category] ?? const <Transaction>[];
      final dailyTotals = groupBy(txs, (Transaction t) => t.date.day)
          .values
          .map((list) => list.fold<double>(0, (s, t) => s + t.amount))
          .toList();
      final mean = dailyTotals.isEmpty
          ? blendedDaily
          : dailyTotals.average;
      final variance = dailyTotals.length < 2
          ? math.pow(mean * 0.5, 2).toDouble()
          : dailyTotals
                  .map((v) => math.pow(v - mean, 2))
                  .sum /
              (dailyTotals.length - 1);
      // Projection sigma scales with sqrt of remaining days.
      final sigma = math.sqrt(variance * math.max(daysLeft, 1)) + 1e-6;

      final z = (projected - u.limitAmount) / sigma;
      final probability = u.limitAmount <= 0
          ? 0.0
          : u.spent >= u.limitAmount
              ? 1.0
              : 1 / (1 + math.exp(-1.7 * z)); // logistic CDF approximation

      return BudgetPrediction(
        budgetId: u.budgetId,
        category: u.category,
        limitAmount: u.limitAmount,
        spent: u.spent,
        projectedTotal: projected,
        overflowProbability: probability.clamp(0, 1),
      );
    }).toList()
      ..sort((a, b) =>
          b.overflowProbability.compareTo(a.overflowProbability));
  }
}

final budgetPredictionAgentProvider = Provider(
  (ref) => BudgetPredictionAgent(
    ref.watch(analyticsRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
  ),
);

final budgetPredictionsProvider =
    FutureProvider.autoDispose<List<BudgetPrediction>>(
  (ref) => ref.watch(budgetPredictionAgentProvider).run(),
);
