import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hero_card.dart';
import '../../core/widgets/money_text.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';

const _monthsShortPt = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez', //
];

final _cardsProvider = FutureProvider.autoDispose<List<FinancialAccount>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(accountRepositoryProvider).all(orderBy: 'name', asc: true);
});

/// Últimos 6 meses de lançamentos do cartão selecionado — insumo do hero
/// (fatura do mês), do gráfico e das abas Compras/Parcelas.
final _cardTxProvider =
    FutureProvider.autoDispose.family<List<Transaction>, String>((ref, cardId) {
  ref.watch(aiWriteTickProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month - 5, 1);
  final to = DateTime(now.year, now.month + 1, 0);
  return ref
      .watch(transactionRepositoryProvider)
      .byCard(cardId, from: from, to: to);
});

/// Cartões & Faturas (inspirado no Pluma): fatura do mês em destaque, evolução
/// de 6 meses em barras e as compras do mês separadas em Todos / Compras /
/// Parcelas. Honesto por natureza: como ainda não modelamos data de
/// fechamento, chamamos de "fatura do mês" (gastos do cartão no mês), não de
/// fatura fechada.
class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key});

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> {
  String? _cardId;
  int _tab = 0; // 0 Todos · 1 Compras · 2 Parcelas

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(_cardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cartões'),
        actions: const [PrivacyToggle()],
      ),
      body: cardsAsync.when(
        loading: () => const LoadingSkeleton(itemCount: 4, itemHeight: 96),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(_cardsProvider)),
        data: (all) {
          final cards =
              all.where((a) => a.type == AccountType.creditCard).toList();
          if (cards.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                EmptyState(
                  icon: Icons.credit_card_off_outlined,
                  title: 'Nenhum cartão de crédito',
                  subtitle:
                      'Cadastre um cartão em Contas e Cartões para acompanhar a '
                      'fatura, o histórico e as parcelas aqui.',
                  actionLabel: 'Ir para Contas e Cartões',
                  onAction: () => context.push('/accounts'),
                ),
              ],
            );
          }

          final selected = cards.firstWhere((c) => c.id == _cardId,
              orElse: () => cards.first);
          final txAsync = ref.watch(_cardTxProvider(selected.id));

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_cardsProvider);
              ref.invalidate(_cardTxProvider(selected.id));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (cards.length > 1)
                  _CardPicker(
                    cards: cards,
                    selected: selected,
                    onPick: (c) => setState(() => _cardId = c.id),
                  ),
                txAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: LoadingSkeleton(itemCount: 3, itemHeight: 96),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text('Não foi possível carregar: $e'),
                  ),
                  data: (txs) => _CardBody(
                    card: selected,
                    txs: txs,
                    tab: _tab,
                    onTab: (i) => setState(() => _tab = i),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Seletor de cartão (como o "Todos os cartões" do Pluma) — chips roláveis.
class _CardPicker extends StatelessWidget {
  const _CardPicker(
      {required this.cards, required this.selected, required this.onPick});

  final List<FinancialAccount> cards;
  final FinancialAccount selected;
  final ValueChanged<FinancialAccount> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.name),
                  selected: c.id == selected.id,
                  avatar: Icon(Icons.credit_card_rounded,
                      size: 16,
                      color: c.id == selected.id
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.catSlate),
                  onSelected: (_) => onPick(c),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody(
      {required this.card,
      required this.txs,
      required this.tab,
      required this.onTab});

  final FinancialAccount card;
  final List<Transaction> txs;
  final int tab;
  final ValueChanged<int> onTab;

  bool _isInstallment(Transaction t) =>
      t.totalInstallments != null && t.totalInstallments! > 1;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Lançamentos do mês corrente (a "fatura do mês").
    final current = txs
        .where((t) =>
            t.isExpense && t.date.year == now.year && t.date.month == now.month)
        .toList();
    final faturaMes = current.fold<double>(0, (s, t) => s + t.amount);

    // Buckets de 6 meses para o gráfico (mês antigo → atual).
    final months =
        List.generate(6, (i) => DateTime(now.year, now.month - 5 + i, 1));
    final buckets = months.map((m) {
      return txs
          .where((t) =>
              t.isExpense && t.date.year == m.year && t.date.month == m.month)
          .fold<double>(0, (s, t) => s + t.amount);
    }).toList();

    final filtered = switch (tab) {
      1 => current.where((t) => !_isInstallment(t)).toList(),
      2 => current.where(_isInstallment).toList(),
      _ => current,
    };

    final children = <Widget>[
      const SizedBox(height: 12),
      _InvoiceHero(card: card, faturaMes: faturaMes, month: now),
      const SizedBox(height: 12),
      _SixMonthChart(months: months, values: buckets),
      const SizedBox(height: 20),
      _Tabs(tab: tab, onTab: onTab),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            switch (tab) {
              1 => 'Nenhuma compra à vista no cartão neste mês.',
              2 => 'Nenhuma parcela no cartão neste mês.',
              _ => 'Nenhum lançamento no cartão neste mês.',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      else
        for (final t in filtered) ...[
          _CardTxRow(tx: t),
          const SizedBox(height: 8),
        ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.04, curve: Curves.easeOutCubic);
  }
}

/// Hero da fatura do mês: valor grande (serifado pelo tema) + uso do limite.
class _InvoiceHero extends StatelessWidget {
  const _InvoiceHero(
      {required this.card, required this.faturaMes, required this.month});

  final FinancialAccount card;
  final double faturaMes;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasLimit = card.creditLimit != null && card.creditLimit! > 0;
    // Uso do limite usa o SALDO do cartão (dívida atual), coerente com a tela
    // de Contas — não o gasto do mês.
    final used =
        hasLimit ? (-card.balance / card.creditLimit!).clamp(0.0, 1.0) : null;
    return HeroCard(
      eyebrow: 'Fatura',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month.monthYear, style: text.labelMedium),
          const SizedBox(height: 4),
          MoneyText(faturaMes.brl,
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Compras lançadas no ${card.name} neste mês',
              style: text.labelSmall?.copyWith(
                  color: text.bodySmall?.color?.withValues(alpha: 0.7))),
          if (used != null) ...[
            const SizedBox(height: 14),
            DynamicProgressBar(ratio: used, height: 10),
            const SizedBox(height: 6),
            Text(
              'Limite usado: ${(used * 100).toStringAsFixed(0)}% de '
              '${card.creditLimit!.brl}',
              style: text.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _SixMonthChart extends StatelessWidget {
  const _SixMonthChart({required this.months, required this.values});

  final List<DateTime> months;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.25;
    final lastIndex = months.length - 1;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Últimos 6 meses',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                      '${_monthsShortPt[months[group.x].month - 1]}\n${rod.toY.brl}',
                      TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= months.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_monthsShortPt[months[i].month - 1],
                              style: text.labelSmall),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < values.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i],
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          color: i == lastIndex
                              ? AppColors.brandLagoon
                              : AppColors.brandLagoon.withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 0, label: Text('Todos')),
        ButtonSegment(value: 1, label: Text('Compras')),
        ButtonSegment(value: 2, label: Text('Parcelas')),
      ],
      selected: {tab},
      onSelectionChanged: (s) => onTab(s.first),
    );
  }
}

/// Linha de lançamento do cartão: ícone da categoria, descrição, meta (autor ·
/// data · parcela) e o valor à direita. Gasto é neutro (padrão profissional).
class _CardTxRow extends StatelessWidget {
  const _CardTxRow({required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = AppColors.categoryColor(tx.category);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shopping_bag_outlined, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? tx.beneficiary ?? tx.category,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    tx.category,
                    tx.date.dayMonth,
                    if (tx.totalInstallments != null &&
                        tx.totalInstallments! > 1)
                      '${tx.installmentNumber}/${tx.totalInstallments}',
                  ].join(' · '),
                  style: text.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText('-${tx.amount.brl}',
              style: text.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
