import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kinfin_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/kinfin_scope.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../../services/ai/budget_prediction_agent.dart';
import '../../services/alerts_service.dart';
import '../auth/auth_controller.dart';
import '../dashboard/simple_home_screen.dart';
import '../settings/simple_mode_controller.dart';
import '../settings/usage_mode_controller.dart';
import 'mode_scope.dart';
import 'mode_switch.dart';
import 'mordomo_feed.dart';

final _kpisProvider = FutureProvider.autoDispose<DashboardKpis>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(analyticsRepositoryProvider).kpis();
});
final _membersProvider = FutureProvider.autoDispose<List<AppUser>>((ref) {
  final profile = ref.watch(authControllerProvider).profile;
  if (profile?.familyId == null) return Future.value(const []);
  return ref.watch(authRepositoryProvider).familyMembers(profile!.familyId!);
});
final _expenseByUserProvider =
    FutureProvider.autoDispose<Map<String, double>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(transactionRepositoryProvider).monthExpenseByUser(DateTime.now());
});
final _billsProvider = FutureProvider.autoDispose<List<Bill>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(billRepositoryProvider).all();
});
final _soloRecentProvider = FutureProvider.autoDispose<List<Transaction>>((ref) {
  ref.watch(aiWriteTickProvider);
  final userId = ref.watch(scopeUserIdProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .fetchPage(page: 0, filter: TransactionFilter(userId: userId));
});

/// Metas PESSOAIS do usuário logado (userId = eu). Metas da família (userId
/// null) ficam de fora — essas vivem em `goalsProvider` (tela Metas).
final _personalGoalsProvider =
    FutureProvider.autoDispose<List<FinancialGoal>>((ref) async {
  final myId = ref.watch(authControllerProvider).profile?.id;
  if (myId == null) return const [];
  final all = await ref.watch(goalRepositoryProvider).all();
  return all.where((g) => g.userId == myId).toList();
});

/// Metas da FAMÍLIA (userId null) — usado no banner "Objetivos da família"
/// do Modo Compartilhado.
final _familyGoalsProvider =
    FutureProvider.autoDispose<List<FinancialGoal>>((ref) async {
  final all = await ref.watch(goalRepositoryProvider).all();
  return all.where((g) => !g.isPersonal).toList();
});

/// Home KinFin definitiva: saudação + chave Solo/Compartilhado, o protagonista
/// (dado grande e calmo, com sensação de rumo), o corpo específico do modo
/// (Solo = minhas movimentações; Compartilhado = equidade + contas) e o feed do
/// mordomo. Tela NOVA — as telas Casa Viva seguem intactas.
class KinFinHomeScreen extends ConsumerWidget {
  const KinFinHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Modo simples (opcional, das Configurações): mesma regra do Dashboard
    // Casa Viva — substitui a Home por poucos botões grandes.
    if (ref.watch(simpleModeProvider)) {
      return const SimpleHomeScreen();
    }
    final solo = ref.watch(usageModeProvider) == UsageMode.solo;
    return KinFinScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Início')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const _Greeting(),
              const SizedBox(height: 14),
              const ModeSwitch(),
              const SizedBox(height: 16),
              const _Protagonist(),
              const SizedBox(height: 18),
              if (solo) ...[
                const _PersonalGoals(),
                const SizedBox(height: 18),
                const _SoloRecent(),
                const SizedBox(height: 18),
                const _NextSteps(),
              ] else ...[
                const _Equity(),
                const SizedBox(height: 18),
                const _FamilyGoalBanner(),
                const SizedBox(height: 18),
                const _HouseholdBills(),
              ],
              const SizedBox(height: 18),
              const MordomoFeed(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solo = ref.watch(usageModeProvider) == UsageMode.solo;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(solo ? 'SEU ESPAÇO' : 'SUA FAMÍLIA',
            style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6)),
        const SizedBox(height: 6),
        Text('Olá, Família',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Protagonist extends ConsumerWidget {
  const _Protagonist();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solo = ref.watch(usageModeProvider) == UsageMode.solo;
    final kpis = ref.watch(_kpisProvider).valueOrNull;
    final preds = ref.watch(budgetPredictionsProvider).valueOrNull ?? const [];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    String label = solo ? 'Saldo disponível' : 'Orçamento do lar';
    String value = '—';
    String? sub;
    bool hasBar = false;
    double ratio = 0;
    int pct = 0;
    Color barColor = scheme.primary;
    String rumo = '';

    if (solo) {
      if (kpis != null) {
        value = kpis.totalBalance.brl;
        final renda = kpis.monthRevenue;
        sub = 'Renda do mês  ·  ${renda.brl}';
        if (renda > 0) {
          hasBar = true;
          final r = kpis.monthExpenses / renda;
          ratio = r.clamp(0, 1).toDouble();
          pct = (r * 100).round();
          barColor = r > 0.9 ? KinFinColors.danger : scheme.primary;
        }
        rumo = kpis.monthRevenue - kpis.monthExpenses >= 0
            ? 'No azul este mês — bom rumo.'
            : 'Mês mais puxado — dá pra ajustar o ritmo.';
      }
    } else {
      if (preds.isNotEmpty) {
        final orcado = preds.fold<double>(0, (s, p) => s + p.limitAmount);
        final gasto = preds.fold<double>(0, (s, p) => s + p.spent);
        value = gasto.brl;
        sub = 'de ${orcado.brl} orçados';
        if (orcado > 0) {
          hasBar = true;
          final r = gasto / orcado;
          ratio = r.clamp(0, 1).toDouble();
          pct = (r * 100).round();
          barColor = gasto > orcado ? KinFinColors.danger : scheme.primary;
        }
        rumo = gasto <= orcado
            ? 'O lar está dentro do combinado.'
            : 'Passou do combinado — dá pra reequilibrar.';
      } else {
        label = 'Saldo do lar';
        if (kpis != null) value = kpis.totalBalance.brl;
        rumo = 'Defina orçamentos pra acompanhar o ritmo do lar.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.20), KinFinColors.card],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KinFinColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: KinFinColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(value,
              style: text.headlineMedium
                  ?.copyWith(fontSize: 32, fontWeight: FontWeight.w800)),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub,
                style: text.bodySmall?.copyWith(color: KinFinColors.textMuted)),
          ],
          if (hasBar) ...[
            const SizedBox(height: 14),
            _ProgressLine(ratio: ratio, pct: pct, color: barColor),
          ],
          if (rumo.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(rumo,
                style: text.bodySmall?.copyWith(color: KinFinColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Barra de progresso fina, arredondada, com o % ao lado — o padrão visual
/// KinFin para "quanto do combinado já foi" (orçamento, renda, metas).
class _ProgressLine extends StatelessWidget {
  const _ProgressLine(
      {required this.ratio, required this.pct, required this.color});
  final double ratio;
  final int pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$pct%',
            style: text.labelMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

/// Envolve linhas numa superfície de card única, com divisores hairline —
/// em vez de N cards soltos. É o que dá a densidade de "produto".
class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Divider(
            height: 1, thickness: 1, color: KinFinColors.line));
      }
    }
    return Card(child: Column(children: rows));
  }
}

class _SoloRecent extends ConsumerWidget {
  const _SoloRecent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(_soloRecentProvider);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Minhas movimentações',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        recent.when(
          loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Text('Você ainda não registrou nada no seu espaço.',
                  style: text.bodyMedium
                      ?.copyWith(color: KinFinColors.textMuted))
              : _ListCard(children: [
                  for (final t in list.take(5)) _TxRow(tx: t),
                ]),
        ),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final Transaction tx;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          _CategoryDot(category: tx.category, isExpense: tx.isExpense),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.description ?? tx.category,
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(tx.category,
                    style: text.labelSmall
                        ?.copyWith(color: KinFinColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('${tx.isExpense ? '-' : '+'}${tx.amount.brl}',
              style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tx.isExpense
                      ? KinFinColors.textPrimary
                      : KinFinColors.positive)),
        ],
      ),
    );
  }
}

/// Bolinha de categoria — círculo com o acento/positivo em opacidade reduzida.
/// Dá o "ícone em círculo colorido" do protótipo sem depender de um mapa de
/// ícones por categoria (que ainda não temos).
class _CategoryDot extends StatelessWidget {
  const _CategoryDot({required this.category, required this.isExpense});
  final String category;
  final bool isExpense;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = isExpense ? scheme.primary : KinFinColors.positive;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
          isExpense
              ? Icons.south_west_rounded
              : Icons.north_east_rounded,
          size: 18,
          color: tint),
    );
  }
}

// TODO: criar fluxo de criação de meta pessoal (será preenchido quando o usuário tiver como criar suas próprias metas)
/// Metas pessoais (Modo Solo) — grade de 2 colunas, valor atual/alvo + barra.
class _PersonalGoals extends ConsumerWidget {
  const _PersonalGoals();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(_personalGoalsProvider).valueOrNull ?? const [];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (goals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Metas pessoais',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () => context.push('/goals'),
              child: const Text('Ver todas'),
            ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: goals.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
          ),
          itemBuilder: (context, i) {
            final g = goals[i];
            final pct = (g.progress * 100).round();
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KinFinColors.card,
                border: Border.all(color: KinFinColors.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: g.currentAmount.brl,
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    TextSpan(
                        text: ' de ${g.targetAmount.brl}',
                        style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                  ])),
                  const SizedBox(height: 8),
                  _ProgressLine(ratio: g.progress, pct: pct, color: scheme.primary),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Próximos passos (Modo Solo) — reaproveita o `alertsProvider` já existente
/// (contas vencendo, risco de orçamento etc.), em vez de duplicar lógica.
class _NextSteps extends ConsumerWidget {
  const _NextSteps();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const [];
    final text = Theme.of(context).textTheme;
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Próximos passos',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _ListCard(children: [
          for (final a in alerts.take(3)) _NextStepRow(alert: a),
        ]),
      ],
    );
  }
}

class _NextStepRow extends StatelessWidget {
  const _NextStepRow({required this.alert});
  final AppAlert alert;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: alert.route == null ? null : () => context.push(alert.route!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KinFinColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(alert.icon, size: 20, color: alert.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(alert.subtitle,
                      style: text.labelSmall?.copyWith(color: KinFinColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: KinFinColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Equity extends ConsumerWidget {
  const _Equity();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(_membersProvider).valueOrNull ?? const [];
    final byUser = ref.watch(_expenseByUserProvider).valueOrNull ?? const {};
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = byUser.values.fold<double>(0, (s, v) => s + v);

    final rows = members
        .map((m) => (m: m, spent: byUser[m.id] ?? 0.0))
        .toList()
      ..sort((a, b) => b.spent.compareTo(a.spent));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quem contribuiu no mês',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('A divisão dos gastos do lar — sem cobrança, só clareza.',
            style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
        const SizedBox(height: 12),
        if (total == 0)
          Text('Ainda sem gastos no mês pra calcular a divisão.',
              style: text.bodyMedium?.copyWith(color: KinFinColors.textMuted))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(r.m.name,
                                    style: text.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text('${((r.spent / total) * 100).round()}%',
                                  style: text.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : r.spent / total,
                              minHeight: 6,
                              backgroundColor:
                                  scheme.onSurface.withValues(alpha: 0.08),
                              valueColor:
                                  AlwaysStoppedAnimation(scheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Objetivos da família (Modo Compartilhado) — banner com a primeira meta
/// da família (mesma fonte da tela Metas: `_familyGoalsProvider`).
class _FamilyGoalBanner extends ConsumerWidget {
  const _FamilyGoalBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(_familyGoalsProvider).valueOrNull ?? const [];
    final text = Theme.of(context).textTheme;
    if (goals.isEmpty) return const SizedBox.shrink();
    final g = goals.first;
    final pct = (g.progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Objetivos da família',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () => context.push('/goals'),
              child: const Text('Ver todos'),
            ),
          ],
        ),
        InkWell(
          onTap: () => context.push('/goals'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KinFinColors.card,
              border: Border.all(color: KinFinColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: KinFinColors.shared.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.flag_rounded,
                      size: 20, color: KinFinColors.shared),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name,
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${g.currentAmount.brl} de ${g.targetAmount.brl}',
                          style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                      const SizedBox(height: 8),
                      _ProgressLine(ratio: g.progress, pct: pct, color: KinFinColors.shared),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HouseholdBills extends ConsumerWidget {
  const _HouseholdBills();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(_billsProvider);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contas da casa',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        bills.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) {
            final pending = list
                .where((b) => b.status == BillStatus.pending)
                .toList()
              ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
            if (pending.isEmpty) {
              return Text('Nenhuma conta pendente por aqui.',
                  style:
                      text.bodyMedium?.copyWith(color: KinFinColors.textMuted));
            }
            return _ListCard(children: [
              for (final b in pending.take(3))
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (b.isOverdue
                                  ? KinFinColors.danger
                                  : KinFinColors.textMuted)
                              .withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.receipt_long_rounded,
                            size: 18,
                            color: b.isOverdue
                                ? KinFinColors.danger
                                : KinFinColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.description,
                                style: text.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                                b.isOverdue
                                    ? 'vencida'
                                    : 'vence ${b.dueDate.dayMonth}',
                                style: text.labelSmall?.copyWith(
                                    color: b.isOverdue
                                        ? KinFinColors.danger
                                        : KinFinColors.textMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(b.amount.brl,
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
