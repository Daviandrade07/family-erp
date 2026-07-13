import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kinfin_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/assistant_button.dart';
import '../../core/widgets/kinfin_scope.dart';
import '../../core/widgets/money_text.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../../services/insights_engine.dart';
import '../auth/auth_controller.dart';
import '../capture/quick_capture_sheet.dart';
import '../mode/mode_switch.dart';

final _kpisProvider = FutureProvider.autoDispose<DashboardKpis>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(analyticsRepositoryProvider).kpis();
});

final _accountsProvider = FutureProvider.autoDispose<List<FinancialAccount>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(accountRepositoryProvider).all();
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

/// Finanças — identidade visual KinFin (dark-premium), estrutura do mockup
/// aprovado: Contas · Contas conectadas · Cartões e limites · Transações
/// recentes. Preserva funcionalidades reais já existentes (contas a pagar,
/// fiado & parcelas, atalhos, captura rápida, assistente) — só reorganizadas
/// visualmente para bater com o mockup.
///
/// "Contas conectadas" no mockup mostrava bancos externos (Itaú, Nubank) —
/// isso seria Open Finance, que os documentos do projeto (AUDITORIA-SOURCE)
/// marcam como NÃO implementado de verdade ainda. Em vez de inventar dados de
/// bancos externos, esta seção mostra as MESMAS contas reais já cadastradas
/// no KinFin (nada fictício é exibido).
class FinanceHubScreen extends ConsumerWidget {
  const FinanceHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(_kpisProvider).valueOrNull;
    final accounts = ref.watch(_accountsProvider).valueOrNull ?? const [];
    final bills = ref.watch(_billsProvider).valueOrNull ?? const [];
    final debts = ref.watch(_debtsProvider).valueOrNull ?? const [];
    final installments = ref.watch(_installmentsProvider).valueOrNull ?? const [];
    final recent = ref.watch(_recentProvider).valueOrNull ?? const [];
    final canWrite = ref.watch(authControllerProvider).canWrite;
    final scheme = Theme.of(context).colorScheme;

    final bankAccounts =
        accounts.where((a) => a.type == AccountType.bankAccount).toList();
    final cards =
        accounts.where((a) => a.type == AccountType.creditCard).toList();

    return KinFinScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Finanças'),
              SizedBox(width: 10),
              ModeChip(),
            ],
          ),
          actions: const [PrivacyToggle(), AssistantButton()],
        ),
        floatingActionButton: canWrite
            ? FloatingActionButton(
                onPressed: () => showQuickCapture(context),
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                tooltip: 'Registrar',
                child: const Icon(Icons.add),
              )
            : null,
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_kpisProvider);
              ref.invalidate(_accountsProvider);
              ref.invalidate(_billsProvider);
              ref.invalidate(_debtsProvider);
              ref.invalidate(_installmentsProvider);
              ref.invalidate(_recentProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (kpis != null) ...[
                  _SaldoHero(kpis: kpis),
                  const SizedBox(height: 22),
                ],
                _SectionHeader(title: 'Contas', onSeeAll: () => context.push('/accounts')),
                const SizedBox(height: 12),
                _AccountsGrid(accounts: bankAccounts),
                const SizedBox(height: 22),
                _SectionHeader(
                    title: 'Contas conectadas', onSeeAll: () => context.push('/accounts')),
                const SizedBox(height: 12),
                _AccountsList(accounts: bankAccounts),
                const SizedBox(height: 22),
                _SectionHeader(
                    title: 'Cartões e limites (${cards.length})',
                    onSeeAll: () => context.push('/cards')),
                const SizedBox(height: 12),
                _AccountsList(accounts: cards, isCard: true),
                const SizedBox(height: 22),
                _SectionHeader(
                    title: 'Transações recentes', onSeeAll: () => context.push('/transactions')),
                const SizedBox(height: 12),
                _RecentTransactions(list: recent),

                const SizedBox(height: 22),
                const _AvaliacaoCard(),

                // ---- Funcionalidades já existentes, preservadas ----
                if (bills.any((b) => b.status == BillStatus.pending)) ...[
                  const SizedBox(height: 22),
                  _SectionHeader(title: 'Contas a pagar', onSeeAll: () => context.push('/bills')),
                  const SizedBox(height: 12),
                  _BillsCard(bills: bills),
                ],
                if (debts.isNotEmpty || installments.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SectionHeader(
                      title: 'Fiado & Parcelas', onSeeAll: () => context.push('/debts')),
                  const SizedBox(height: 12),
                  _DebtsCard(debts: debts, installments: installments),
                ],

                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                        child: _QuickLink(
                            label: 'Recorrentes',
                            icon: Icons.autorenew_rounded,
                            route: '/recurring')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _QuickLink(
                            label: 'Orçamentos',
                            icon: Icons.donut_small_outlined,
                            route: '/budgets')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _QuickLink(
                            label: 'Análises',
                            icon: Icons.insights_outlined,
                            route: '/analytics')),
                  ],
                ),
              ]
                  .animate(interval: 45.ms)
                  .fadeIn(duration: 260.ms)
                  .slideY(begin: 0.05, curve: Curves.easeOutCubic),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaldoHero extends StatelessWidget {
  const _SaldoHero({required this.kpis});
  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
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
          Text('SALDO',
              style: const TextStyle(
                  color: KinFinColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          MoneyText(kpis.totalBalance.brl,
              style: text.headlineMedium?.copyWith(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'A pagar ${kpis.billsPending.brl} · No mês '
            '${(kpis.monthRevenue - kpis.monthExpenses) >= 0 ? '+' : ''}'
            '${(kpis.monthRevenue - kpis.monthExpenses).brl}',
            style: text.bodySmall?.copyWith(color: KinFinColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onSeeAll});
  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        TextButton(onPressed: onSeeAll, child: const Text('Ver todas')),
      ],
    );
  }
}

class _AccountsGrid extends StatelessWidget {
  const _AccountsGrid({required this.accounts});
  final List<FinancialAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (accounts.isEmpty) {
      return Text('Nenhuma conta cadastrada ainda.',
          style: text.bodyMedium?.copyWith(color: KinFinColors.textMuted));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: accounts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, i) {
        final a = accounts[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KinFinColors.card,
            border: Border.all(color: KinFinColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
              MoneyText(a.balance.brl,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        );
      },
    );
  }
}

class _AccountsList extends StatelessWidget {
  const _AccountsList({required this.accounts, this.isCard = false});
  final List<FinancialAccount> accounts;
  final bool isCard;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (accounts.isEmpty) {
      return Text(
          isCard ? 'Nenhum cartão cadastrado ainda.' : 'Nenhuma conta cadastrada ainda.',
          style: text.bodyMedium?.copyWith(color: KinFinColors.textMuted));
    }
    return _ListCard(children: [
      for (final a in accounts) _AccountRow(account: a, isCard: isCard),
    ]);
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.isCard});
  final FinancialAccount account;
  final bool isCard;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push(isCard ? '/cards' : '/accounts'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                  isCard ? Icons.credit_card_rounded : Icons.account_balance_rounded,
                  size: 18,
                  color: scheme.onPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(isCard ? 'Cartão de crédito' : 'Conta corrente',
                      style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MoneyText(account.balance.brl,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({required this.list});
  final List<Transaction> list;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (list.isEmpty) {
      return Text('Nada registrado ainda.',
          style: text.bodyMedium?.copyWith(color: KinFinColors.textMuted));
    }
    return _ListCard(children: [
      for (final t in list.take(5)) _TransactionRow(tx: t),
    ]);
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: tx.isExpense
          ? () => context.push('/transactions/allocate', extra: tx)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.south_west_rounded, size: 18, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.description ?? tx.category,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('${tx.date.dayMonth} · ${tx.category}',
                      style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MoneyText('-${tx.amount.brl}',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _BillsCard extends StatelessWidget {
  const _BillsCard({required this.bills});
  final List<Bill> bills;

  @override
  Widget build(BuildContext context) {
    final pending = bills.where((b) => b.status == BillStatus.pending).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final text = Theme.of(context).textTheme;
    return _ListCard(children: [
      for (final b in pending.take(3))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.description,
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(b.isOverdue ? 'vencida' : 'vence ${b.dueDate.dayMonth}',
                        style: text.labelSmall?.copyWith(
                            color: b.isOverdue ? KinFinColors.danger : KinFinColors.textMuted)),
                  ],
                ),
              ),
              MoneyText(b.amount.brl,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
    ]);
  }
}

class _DebtsCard extends StatelessWidget {
  const _DebtsCard({required this.debts, required this.installments});
  final List<Debt> debts;
  final List<Transaction> installments;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final debtTotal = debts.fold<double>(0, (s, d) => s + d.remainingAmount);
    final instTotal = installments.fold<double>(0, (s, t) => s + t.amount);
    return _ListCard(children: [
      if (debts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dívidas em aberto',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${debts.length} credor(es)',
                      style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                ],
              ),
            ),
            MoneyText(debtTotal.brl,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
      if (installments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Parcelas a vencer',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${installments.length} parcela(s)',
                      style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                ],
              ),
            ),
            MoneyText(instTotal.brl,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
    ]);
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.label, required this.icon, required this.route});
  final String label;
  final IconData icon;
  final String route;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: KinFinColors.card,
          border: Border.all(color: KinFinColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// Card "Avaliação" (saúde financeira do mês). Formato narrativo do mockup v2:
/// selo de status + frase-veredito em destaque + próximo passo acionável.
///
/// DADO REAL, NÃO FICTÍCIO: alimenta-se do `monthStoryProvider` (motor de
/// insights determinístico já existente em services/insights_engine.dart), que
/// calcula o humor do mês (tranquilo/atenção/cuidado) e as frases a partir dos
/// KPIs reais da família. Nada de nota "82" fabricada como no mockup — quando
/// não há histórico, o próprio motor devolve um convite honesto para começar.
class _AvaliacaoCard extends ConsumerWidget {
  const _AvaliacaoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final story = ref.watch(monthStoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Avaliação',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        story.when(
          loading: () => _AvaliacaoShell(
            child: Row(
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text('Calculando a avaliação do mês...',
                    style:
                        text.bodySmall?.copyWith(color: KinFinColors.textMuted)),
              ],
            ),
          ),
          error: (_, __) => _AvaliacaoShell(
            child: Text('Não foi possível avaliar o mês agora.',
                style: text.bodySmall?.copyWith(color: KinFinColors.textMuted)),
          ),
          data: (s) => _AvaliacaoContent(story: s),
        ),
      ],
    );
  }
}

class _AvaliacaoContent extends StatelessWidget {
  const _AvaliacaoContent({required this.story});
  final MonthStory story;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (label, color) = switch (story.mood) {
      StoryMood.tranquilo => ('Saudável', KinFinColors.positive),
      StoryMood.atencao => ('Atenção', KinFinColors.attention),
      StoryMood.cuidado => ('Cuidado', KinFinColors.danger),
    };
    return _AvaliacaoShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Text(story.shouldIWorry,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(story.nextStep,
              style: text.bodySmall?.copyWith(color: KinFinColors.textMuted)),
        ],
      ),
    );
  }
}

/// Superfície do card de Avaliação — mesma cara de card do resto de Finanças.
class _AvaliacaoShell extends StatelessWidget {
  const _AvaliacaoShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinFinColors.card,
        border: Border.all(color: KinFinColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// Envolve linhas numa superfície de card única, com divisores hairline —
/// mesmo padrão usado em kinfin_home_screen.dart.
class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Divider(height: 1, thickness: 1, color: KinFinColors.line));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: KinFinColors.card,
        border: Border.all(color: KinFinColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: rows),
    );
  }
}
