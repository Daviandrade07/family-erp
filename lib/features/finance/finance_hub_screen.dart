import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/animated_money.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/assistant_button.dart';
import '../../core/widgets/contextual_ai_hint.dart';
import '../../core/widgets/hero_card.dart';
import '../../core/widgets/money_text.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../auth/auth_controller.dart';
import '../capture/quick_capture_sheet.dart';

final _kpisProvider = FutureProvider.autoDispose<DashboardKpis>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(analyticsRepositoryProvider).kpis();
});

final _billsProvider = FutureProvider.autoDispose<List<Bill>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(billRepositoryProvider).all();
});

final _debtsProvider = FutureProvider.autoDispose<List<Debt>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(debtRepositoryProvider).all();
});

final _installmentsProvider = FutureProvider.autoDispose<List<Transaction>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(transactionRepositoryProvider).upcomingInstallments();
});

final _recentProvider = FutureProvider.autoDispose<List<Transaction>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(transactionRepositoryProvider).recentExpenses(days: 30);
});

/// Finanças = o centro financeiro da pessoa: resumo, contas a pagar, fiado &
/// parcelas e movimentações num lugar só. Responde "como está meu dinheiro e o
/// que preciso fazer?" — não é mais só uma lista de transações.
class FinanceHubScreen extends ConsumerWidget {
  const FinanceHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(_kpisProvider);
    final bills = ref.watch(_billsProvider);
    final debts = ref.watch(_debtsProvider);
    final installments = ref.watch(_installmentsProvider);
    final recent = ref.watch(_recentProvider);
    final canWrite = ref.watch(authControllerProvider).canWrite;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanças'),
        actions: const [PrivacyToggle(), AssistantButton()],
      ),
      // Registro Rápido (P2): falar/digitar e pronto. O formulário completo
      // continua acessível por um link dentro do próprio sheet.
      floatingActionButton: canWrite
          ? FloatingActionButton(
              onPressed: () => showQuickCapture(context),
              backgroundColor: AppColors.brandCoral,
              foregroundColor: const Color(0xFF3A1611),
              tooltip: 'Registrar',
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_kpisProvider);
          ref.invalidate(_billsProvider);
          ref.invalidate(_debtsProvider);
          ref.invalidate(_installmentsProvider);
          ref.invalidate(_recentProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            // ---- Resumo ----
            kpis.when(
              loading: () => const SizedBox(
                  height: 96, child: LoadingSkeleton(itemCount: 1, itemHeight: 96)),
              error: (_, __) => const SizedBox.shrink(),
              data: (k) => HeroCard(
                eyebrow: 'Saldo',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedMoney(k.totalBalance,
                        style: text.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'A pagar ${k.billsPending.brl} · No mês '
                      '${(k.monthRevenue - k.monthExpenses) >= 0 ? '+' : ''}'
                      '${(k.monthRevenue - k.monthExpenses).brl}',
                      style: text.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---- IA contextual ----
            const ContextualAiHint(),

            // ---- Contas a pagar ----
            _SectionCard(
              title: 'Contas a pagar',
              onSeeAll: () => context.push('/bills'),
              child: bills.when(
                loading: () => const LoadingSkeleton(itemCount: 2, itemHeight: 44),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) {
                  final pending = list
                      .where((b) => b.status == BillStatus.pending)
                      .toList()
                    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
                  if (pending.isEmpty) {
                    return Text('Nenhuma conta pendente 👍',
                        style: text.labelMedium);
                  }
                  return Column(
                    children: [
                      for (final b in pending.take(3))
                        _MiniRow(
                          label: b.description,
                          sub: b.isOverdue
                              ? 'vencida'
                              : 'vence ${b.dueDate.dayMonth}',
                          amount: b.amount.brl,
                          danger: b.isOverdue,
                        ),
                    ],
                  );
                },
              ),
            ),

            // ---- Fiado & Parcelas ----
            _SectionCard(
              title: 'Fiado & Parcelas',
              onSeeAll: () => context.push('/debts'),
              child: Column(
                children: [
                  debts.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (list) {
                      final total =
                          list.fold<double>(0, (s, d) => s + d.remainingAmount);
                      if (list.isEmpty) {
                        return Text('Nenhuma dívida registrada.',
                            style: text.labelMedium);
                      }
                      return _MiniRow(
                        label: 'Dívidas em aberto',
                        sub: '${list.length} credor(es)',
                        amount: total.brl,
                      );
                    },
                  ),
                  installments.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (list) {
                      if (list.isEmpty) return const SizedBox.shrink();
                      final total =
                          list.fold<double>(0, (s, t) => s + t.amount);
                      return _MiniRow(
                        label: 'Parcelas a vencer',
                        sub: '${list.length} parcela(s)',
                        amount: total.brl,
                      );
                    },
                  ),
                ],
              ),
            ),

            // ---- Movimentações ----
            _SectionCard(
              title: 'Movimentações',
              onSeeAll: () => context.push('/transactions'),
              child: recent.when(
                loading: () => const LoadingSkeleton(itemCount: 3, itemHeight: 44),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) {
                  if (list.isEmpty) {
                    return Text('Nada registrado ainda.', style: text.labelMedium);
                  }
                  return Column(
                    children: [
                      for (final t in list.take(3))
                        _MiniRow(
                          label: t.description ?? t.category,
                          sub: '${t.category} · ${t.date.dayMonth}',
                          amount: '-${t.amount.brl}',
                          danger: false,
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(
                    child: _QuickLink(
                        label: 'Contas & Cartões',
                        icon: Icons.account_balance_outlined,
                        route: '/accounts')),
                SizedBox(width: 8),
                Expanded(
                    child: _QuickLink(
                        label: 'Recorrentes',
                        icon: Icons.autorenew_rounded,
                        route: '/recurring')),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                    child: _QuickLink(
                        label: 'Orçamentos',
                        icon: Icons.donut_small_outlined,
                        route: '/budgets')),
                SizedBox(width: 8),
                Expanded(
                    child: _QuickLink(
                        label: 'Análises',
                        icon: Icons.insights_outlined,
                        route: '/analytics')),
              ],
            ),
          ]
              .animate(interval: 55.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink(
      {required this.label, required this.icon, required this.route});

  final String label;
  final IconData icon;
  final String route;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      onTap: () => context.push(route),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.techBlue),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.child, required this.onSeeAll});

  final String title;
  final Widget child;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                InkWell(
                  onTap: onSeeAll,
                  child: Row(
                    children: [
                      Text('ver +', style: text.labelSmall),
                      const Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({
    required this.label,
    required this.sub,
    required this.amount,
    this.danger = false,
  });

  final String label;
  final String sub;
  final String amount;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(sub,
                    style: text.labelSmall?.copyWith(
                        color: danger ? AppColors.red : null)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(amount,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
