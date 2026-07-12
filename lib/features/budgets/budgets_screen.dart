import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hero_card.dart';
import '../../core/widgets/money_text.dart';
import '../categories/categories_screen.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/budget_prediction_agent.dart';
import '../auth/auth_controller.dart';

/// Budgets with dynamic progress (limit vs. spent) and the AI predictive
/// indicator (ghost bar + overflow probability chip).
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _addOrEdit(BuildContext context, WidgetRef ref,
      {BudgetPrediction? existing}) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final amount = TextEditingController(
        text: existing?.limitAmount.toStringAsFixed(0) ?? '');
    final famExpense = categoriesForType(
            ref.read(familyCategoriesProvider).valueOrNull ?? const [],
            TransactionType.expense)
        .map((c) => c.name)
        .toList();
    final expenseCats = famExpense.isEmpty ? Categories.expense : famExpense;
    String category = existing?.category ?? expenseCats.first;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? 'Novo orçamento' : 'Editar orçamento',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: category,
                items: [
                  for (final c in expenseCats)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: existing == null
                    ? (v) => setSheet(() => category = v!)
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    hintText: 'Limite mensal', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) return;

    final repo = ref.read(budgetRepositoryProvider);
    if (existing == null) {
      await repo.insertRow(Budget(
        familyId: profile!.familyId!,
        category: category,
        limitAmount: value,
      ).toInsert());
    } else {
      await repo.updateRow(existing.budgetId, {'limit_amount': value});
    }
    ref.invalidate(budgetPredictionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictions = ref.watch(budgetPredictionsProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamentos'),
        actions: const [PrivacyToggle()],
      ),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _addOrEdit(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: predictions.when(
        loading: () => const LoadingSkeleton(itemCount: 5, itemHeight: 120),
        error: (e, _) => ErrorRetry(
            message: '$e',
            onRetry: () => ref.invalidate(budgetPredictionsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.donut_small_rounded,
              title: 'Nenhum orçamento definido',
              subtitle:
                  'Defina limites mensais por categoria e a IA vai prever '
                  'estouros antes que aconteçam.',
            );
          }
          final orcado = list.fold<double>(0, (s, p) => s + p.limitAmount);
          final gasto = list.fold<double>(0, (s, p) => s + p.spent);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(budgetPredictionsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _BudgetSummary(orcado: orcado, gasto: gasto),
                const SizedBox(height: 18),
                for (final p in list) ...[
                  _BudgetCard(
                    prediction: p,
                    onEdit: auth.canWrite
                        ? () => _addOrEdit(context, ref, existing: p)
                        : null,
                    onDelete: auth.isAdmin
                        ? () async {
                            await ref
                                .read(budgetRepositoryProvider)
                                .deleteRow(p.budgetId);
                            ref.invalidate(budgetPredictionsProvider);
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Resumo do mês (padrão Pluma): quanto foi orçado, quanto já se gastou e
/// quanto ainda sobra no total. Verde quando sobra, vermelho quando estourou.
class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.orcado, required this.gasto});

  final double orcado;
  final double gasto;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sobra = orcado - gasto;
    final scheme = Theme.of(context).colorScheme;
    Widget col(String label, String value, Color? color) => Expanded(
          child: Column(
            children: [
              Text(label,
                  style: text.labelSmall?.copyWith(
                      color: text.bodySmall?.color?.withValues(alpha: 0.7))),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: MoneyText(value,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        );
    Widget divider() => Container(
          width: 1,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.outline.withValues(alpha: 0.6),
        );
    return HeroCard(
      eyebrow: 'Orçamento',
      child: Row(
        children: [
          col('Orçado', orcado.brl, null),
          divider(),
          col('Gasto', gasto.brl, null),
          divider(),
          col(
            sobra >= 0 ? 'Sobra' : 'Estourou',
            (sobra >= 0 ? sobra : -sobra).brl,
            sobra >= 0 ? AppColors.successSage : AppColors.red,
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.prediction, this.onEdit, this.onDelete});

  final BudgetPrediction prediction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final text = Theme.of(context).textTheme;
    final riskColor = p.overflowProbability >= 0.5
        ? AppColors.red
        : p.overflowProbability >= 0.25
            ? AppColors.amber
            : AppColors.neonGreen;

    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.categoryColor(p.category),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.category,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              StatusBadge(
                'Risco ${p.overflowProbability.pct}',
                color: riskColor,
                icon: Icons.query_stats_rounded,
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 12),
          DynamicProgressBar(
            ratio: p.usedRatio,
            predictedRatio: p.projectedRatio,
            height: 12,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${p.spent.brl} de ${p.limitAmount.brl}',
                  style: text.bodySmall),
              Text('Projeção: ${p.projectedTotal.brl}',
                  style: text.bodySmall?.copyWith(
                      color: riskColor, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Builder(builder: (context) {
            final restante = p.limitAmount - p.spent;
            final ok = restante >= 0;
            return Text(
              ok
                  ? 'Ainda pode gastar ${restante.brl}'
                  : 'Estourou ${(-restante).brl}',
              style: text.labelMedium?.copyWith(
                  color: ok ? AppColors.successSage : AppColors.red,
                  fontWeight: FontWeight.w700),
            );
          }),
          const SizedBox(height: 4),
          Text(p.riskLabel, style: text.labelSmall),
        ],
      ),
    );
  }
}
