import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/economy_tips.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/budget_prediction_agent.dart';
import '../../services/alerts_service.dart';
import '../auth/auth_controller.dart';
import '../settings/simple_mode_controller.dart';
import 'simple_home_screen.dart';

final dashboardKpisProvider = FutureProvider.autoDispose<DashboardKpis>(
    (ref) => ref.watch(analyticsRepositoryProvider).kpis());

final weekSummaryProvider = FutureProvider.autoDispose<WeekSummary>(
    (ref) => ref.watch(analyticsRepositoryProvider).weekSummary());

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Pop-up com UMA dica de economia por abertura do app (ciclo de 100
    // dicas embaralhadas, sem repetição até esgotar).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => EconomyTipPopup.maybeShow(context));
  }

  @override
  Widget build(BuildContext context) {
    // Modo simples (opcional): substitui o início por poucos botões grandes.
    if (ref.watch(simpleModeProvider)) {
      return const SimpleHomeScreen();
    }

    final profile = ref.watch(authControllerProvider).profile;
    final kpis = ref.watch(dashboardKpisProvider);
    final predictions = ref.watch(budgetPredictionsProvider);

    final alerts = ref.watch(alertsProvider);

    Future<void> refresh() async {
      ref.invalidate(dashboardKpisProvider);
      ref.invalidate(weekSummaryProvider);
      ref.invalidate(budgetPredictionsProvider);
      ref.invalidate(alertsProvider);
      ref.invalidate(spendingAllowanceProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, ${profile?.name.split(' ').first ?? ''} 👋'),
            Text(
              DateTime.now().monthYear,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Lembretes',
            icon: Badge(
              isLabelVisible: alerts.valueOrNull?.isNotEmpty ?? false,
              label: Text('${alerts.valueOrNull?.length ?? ''}'),
              backgroundColor: AppColors.red,
              child: const Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () => _showAlertsSheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: (profile?.canWrite ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/transactions/new'),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              icon: const Icon(Icons.add),
              label: const Text('Lançar'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const _SpendingSemaphore(),
            const SizedBox(height: 12),
            kpis.when(
              loading: () =>
                  const SizedBox(height: 220, child: LoadingSkeleton(itemCount: 2)),
              error: (e, _) => ErrorRetry(
                  message: '$e', onRetry: () => ref.invalidate(dashboardKpisProvider)),
              data: (k) => _KpiGrid(kpis: k),
            ),
            const SizedBox(height: 12),
            const _WeekSummaryCard(),
            alerts.maybeWhen(
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader('Lembretes',
                            action: list.length > 3 ? 'Ver todos' : null,
                            onAction: () => _showAlertsSheet(context, ref)),
                        for (final a in list.take(3)) _AlertTile(alert: a),
                      ],
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SectionHeader('Alertas da IA'),
            predictions.when(
              loading: () => const SizedBox(
                  height: 120, child: LoadingSkeleton(itemCount: 1, itemHeight: 110)),
              error: (_, __) => const SizedBox.shrink(),
              data: (preds) => _AiAlerts(predictions: preds),
            ),
            const SizedBox(height: 20),
            AppCard(
              onTap: () => context.push('/analytics'),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.techBlue.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.insights_rounded,
                        color: AppColors.techBlue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Análises e gráficos',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          'Fluxo de caixa, pizza por categoria, evolução e heatmap',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlertsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (context, ref, __) {
          final alerts = ref.watch(alertsProvider);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (context, controller) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded,
                          color: AppColors.amber),
                      const SizedBox(width: 8),
                      Text('Lembretes',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: alerts.when(
                      loading: () => const Center(
                          child: CircularProgressIndicator()),
                      error: (e, _) => Text('$e'),
                      data: (list) => list.isEmpty
                          ? const EmptyState(
                              icon: Icons.check_circle_outline,
                              title: 'Tudo em dia!',
                              subtitle:
                                  'Nenhuma conta vencendo, comida estragando '
                                  'ou estoque baixo agora.')
                          : ListView(
                              controller: controller,
                              children: [
                                for (final a in list) _AlertTile(alert: a),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Semáforo "quanto posso gastar" — resposta de uma olhada só à dor
/// "posso gastar isso?".
class _SpendingSemaphore extends ConsumerWidget {
  const _SpendingSemaphore();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowance = ref.watch(spendingAllowanceProvider);
    final text = Theme.of(context).textTheme;

    return allowance.when(
      loading: () => const SizedBox(height: 96, child: LoadingSkeleton(itemCount: 1, itemHeight: 96)),
      error: (_, __) => const SizedBox.shrink(),
      data: (a) {
        final color = switch (a.status) {
          AllowanceStatus.verde => AppColors.neonGreen,
          AllowanceStatus.amarelo => AppColors.amber,
          AllowanceStatus.vermelho => AppColors.red,
        };
        return AppCard(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.16), color.withOpacity(0.03)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(
                  a.status == AllowanceStatus.verde
                      ? Icons.check_rounded
                      : a.status == AllowanceStatus.amarelo
                          ? Icons.priority_high_rounded
                          : Icons.warning_amber_rounded,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dá pra gastar hoje',
                        style: text.labelMedium?.copyWith(
                            color: text.bodySmall?.color?.withOpacity(0.7))),
                    const SizedBox(height: 2),
                    Text(
                      a.perDay <= 0 ? 'R\$ 0,00' : a.perDay.brl,
                      style: text.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hoje: ${a.todaySpent.brl} · livre no mês: ${a.freeThisMonth.brl}',
                      style: text.labelSmall,
                    ),
                    Text(a.message,
                        style: text.labelSmall?.copyWith(color: color)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Sua semana em números" — resumo dos últimos 7 dias com comparativo,
/// inspirado no recap semanal que os usuários mais elogiam no Monarch.
class _WeekSummaryCard extends ConsumerWidget {
  const _WeekSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(weekSummaryProvider);
    final text = Theme.of(context).textTheme;

    return summary.when(
      loading: () => const SizedBox(
          height: 130, child: LoadingSkeleton(itemCount: 1, itemHeight: 130)),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        if (s.isEmpty) return const SizedBox.shrink();
        final positive = s.balance >= 0;
        final change = s.expenseChange;
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_view_week_rounded,
                      size: 18, color: AppColors.violet),
                  const SizedBox(width: 8),
                  Text('Sua semana em números',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _WeekStat(
                      label: 'Gastos',
                      value: s.expenses.brl,
                      color: AppColors.red),
                  _WeekStat(
                      label: 'Receitas',
                      value: s.revenue.brl,
                      color: AppColors.neonGreen),
                  _WeekStat(
                    label: 'Saldo',
                    value: s.balance.brl,
                    color: positive ? AppColors.techBlue : AppColors.red,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _insight(s, change),
                style: text.labelSmall,
              ),
            ],
          ),
        );
      },
    );
  }

  String _insight(WeekSummary s, double? change) {
    final parts = <String>[];
    if (change != null) {
      if (change > 0.05) {
        parts.add('Gastou ${change.abs().pct} a mais que a semana passada');
      } else if (change < -0.05) {
        parts.add('Economizou ${change.abs().pct} vs. a semana passada 👏');
      } else {
        parts.add('Gastos estáveis vs. a semana passada');
      }
    }
    if (s.topCategory != null) {
      parts.add('${s.topCategory} pesou mais (${s.topCategoryTotal.brl})');
    }
    return parts.isEmpty ? 'Acompanhe seus 7 dias aqui.' : parts.join(' · ');
  }
}

class _WeekStat extends StatelessWidget {
  const _WeekStat(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: text.labelSmall
                  ?.copyWith(color: text.bodySmall?.color?.withOpacity(0.7))),
          const SizedBox(height: 2),
          Text(value,
              style: text.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final AppAlert alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: alert.route == null ? null : () => context.push(alert.route!),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: alert.color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(alert.icon, size: 18, color: alert.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(alert.subtitle,
                      style: text.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (alert.route != null)
              const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    final result = kpis.monthRevenue - kpis.monthExpenses;
    final cards = [
      KpiCard(
        label: 'Saldo geral',
        value: kpis.totalBalance.brl,
        icon: Icons.account_balance_wallet_outlined,
      ),
      KpiCard(
        label: 'Patrimônio líquido',
        value: kpis.netWorth.brl,
        icon: Icons.trending_up_rounded,
        accent: AppColors.techBlue,
      ),
      KpiCard(
        label: 'Contas a pagar',
        value: kpis.billsPending.brl,
        icon: Icons.receipt_long_outlined,
        accent: AppColors.amber,
        caption: kpis.billsOverdue > 0
            ? '${kpis.billsOverdue.brl} em atraso'
            : 'Nada em atraso',
      ),
      KpiCard(
        label: 'Resultado do mês',
        value: result.brl,
        icon: result >= 0
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded,
        accent: result >= 0 ? AppColors.neonGreen : AppColors.red,
        caption:
            '${kpis.monthRevenue.brlCompact} in / ${kpis.monthExpenses.brlCompact} out',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 4 ? 1.5 : 1.35,
          children: cards,
        );
      },
    );
  }
}

class _AiAlerts extends StatelessWidget {
  const _AiAlerts({required this.predictions});

  final List<BudgetPrediction> predictions;

  @override
  Widget build(BuildContext context) {
    final alerts = predictions.where((p) => p.overflowProbability >= 0.25);
    if (alerts.isEmpty) {
      return const AppCard(
        child: Row(
          children: [
            Icon(Icons.verified_rounded, color: AppColors.neonGreen),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                  'Nenhum risco de estouro de orçamento detectado este mês.'),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: alerts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = alerts.elementAt(i);
          final color = p.overflowProbability >= 0.5
              ? AppColors.red
              : AppColors.amber;
          return SizedBox(
            width: 260,
            child: AppCard(
              onTap: () => GoRouter.of(context).push('/budgets'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(p.category,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      StatusBadge(p.overflowProbability.pct, color: color),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${p.riskLabel}. Projeção: ${p.projectedTotal.brl} '
                    'de ${p.limitAmount.brl}.',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  DynamicProgressBar(
                      ratio: p.usedRatio, predictedRatio: p.projectedRatio),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
