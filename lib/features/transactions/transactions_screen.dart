import 'package:flutter/material.dart';
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
import '../auth/auth_controller.dart';
import '../categories/categories_screen.dart';
import 'transactions_controller.dart';

/// Totais (receitas/despesas) do mês SELECIONADO — alimentam o resumo do topo
/// e refletem a navegação de mês. Reagem a gravações da IA.
final _monthTotalsProvider = FutureProvider.autoDispose
    .family<({double revenue, double expenses}), DateTime>((ref, month) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(transactionRepositoryProvider).monthTotals(month);
});

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        ref.read(transactionsControllerProvider.notifier).loadMore();
      }
    });
    // Ao abrir, escopa a lista ao mês atual (o resumo e a lista passam a
    // refletir o mês selecionado). Pós-frame para não mexer no provider durante
    // o build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyMonth(_month));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Aplica o mês selecionado ao filtro (preserva tipo e busca).
  void _applyMonth(DateTime month) {
    setState(() => _month = DateTime(month.year, month.month));
    final f = ref.read(transactionsControllerProvider).filter;
    ref.read(transactionsControllerProvider.notifier).applyFilter(f.copyWith(
          from: () => DateTime(_month.year, _month.month),
          to: () => DateTime(_month.year, _month.month + 1, 0),
        ));
  }

  void _applySearch(String q) {
    final f = ref.read(transactionsControllerProvider).filter;
    ref.read(transactionsControllerProvider.notifier).applyFilter(
          f.copyWith(search: () => q.trim().isEmpty ? null : q.trim()),
        );
  }

  Future<void> _openFilters() async {
    final current = ref.read(transactionsControllerProvider).filter;
    final result = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: current),
    );
    if (result != null && mounted) {
      ref.read(transactionsControllerProvider.notifier).applyFilter(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsControllerProvider);
    final canWrite = ref.watch(authControllerProvider).canWrite;
    final isAdmin = ref.watch(authControllerProvider).isAdmin;
    final allCats = ref.watch(familyCategoriesProvider).valueOrNull;

    // Movimentações agrupadas por dia (padrão de app financeiro profissional):
    // cada dia vira um cabeçalho "Hoje / Ontem / 12 jul" com o saldo do dia.
    final entries = _groupByDay(state.items, state.hasMore);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transações'),
        actions: [
          const PrivacyToggle(),
          IconButton(
            icon: const Icon(Icons.insights_rounded),
            tooltip: 'Gráficos avançados',
            onPressed: () => context.push('/analytics'),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: !state.filter.isEmpty,
              child: const Icon(Icons.tune_rounded),
            ),
            tooltip: 'Filtros',
            onPressed: _openFilters,
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton(
              onPressed: () => context.push('/transactions/new'),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          // Navegador de mês ‹ Mês Ano › — escopa a lista e o resumo.
          _MonthNavigator(
            month: _month,
            onPrev: () =>
                _applyMonth(DateTime(_month.year, _month.month - 1)),
            onNext: () =>
                _applyMonth(DateTime(_month.year, _month.month + 1)),
          ),
          // Resumo do mês SELECIONADO (Receitas/Despesas/Saldo), no hero.
          _MonthSummaryHeader(month: _month),
          // Pílulas de filtro por tipo, visíveis no topo (não no sheet).
          _TypeFilterPills(
            selected: state.filter.type,
            onSelect: (t) => ref
                .read(transactionsControllerProvider.notifier)
                .applyFilter(state.filter.copyWith(type: () => t)),
          ),
          // Busca persistente e visível.
          _SearchField(controller: _search, onSubmit: _applySearch),
          Expanded(
            child: RefreshIndicator(
        onRefresh: () =>
            ref.read(transactionsControllerProvider.notifier).refresh(),
        child: state.items.isEmpty && state.loading
            ? const LoadingSkeleton(itemCount: 8, itemHeight: 72)
            : state.items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Nada por aqui ainda',
                      subtitle: 'Registre o primeiro gasto no + — ou conte '
                          'para a assistente: "gastei 50 no mercado".',
                    ),
                  ])
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: entries.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (context, i) {
                      // Sem respiro extra logo antes de um novo dia — o próprio
                      // cabeçalho do dia já traz o espaçamento superior.
                      final next =
                          i + 1 < entries.length ? entries[i + 1] : null;
                      if (next is _DayHeader) return const SizedBox.shrink();
                      return const SizedBox(height: 8);
                    },
                    itemBuilder: (context, i) {
                      if (i >= entries.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child:
                              Center(child: CircularProgressIndicator()),
                        );
                      }
                      final e = entries[i];
                      if (e is _DayHeader) {
                        return _DaySeparator(day: e.day, net: e.net);
                      }
                      final tx = e as Transaction;
                      return _TransactionTile(
                        tx: tx,
                        categoryColor: categoryColorFor(allCats, tx.category),
                        canDelete: isAdmin,
                        onDelete: () => ref
                            .read(transactionsControllerProvider.notifier)
                            .delete(tx),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resumo do MÊS SELECIONADO no topo das Movimentações, no hero. Usa os totais
/// reais do mês (query dedicada), nunca a soma dos itens carregados (parcial).
class _MonthSummaryHeader extends ConsumerWidget {
  const _MonthSummaryHeader({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(_monthTotalsProvider(month));
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: HeroCard(
        eyebrow: 'Transações',
        padding: const EdgeInsets.all(16),
        child: totals.when(
          loading: () => const SizedBox(
              height: 44, child: Center(child: LinearProgressIndicator())),
          error: (_, __) => const SizedBox.shrink(),
          data: (t) {
            final saldo = t.revenue - t.expenses;
            return Row(
              children: [
                _SummaryCol(
                  label: 'Receitas',
                  value: t.revenue.brl,
                  color: AppColors.successSage,
                ),
                _SummaryDivider(),
                _SummaryCol(
                  label: 'Despesas',
                  value: t.expenses.brl,
                  color: text.bodyLarge?.color,
                ),
                _SummaryDivider(),
                _SummaryCol(
                  label: 'Saldo',
                  value: '${saldo >= 0 ? '' : '-'}${saldo.abs().brl}',
                  color: saldo >= 0 ? AppColors.successSage : AppColors.red,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCol extends StatelessWidget {
  const _SummaryCol(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
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
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
      );
}

/// Navegador de mês ‹ Mês Ano › centralizado, com setas.
class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator(
      {required this.month, required this.onPrev, required this.onNext});

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = month.monthYear; // ex.: "julho 2026"
    final cap = label.isEmpty
        ? label
        : '${label[0].toUpperCase()}${label.substring(1)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Mês anterior',
          ),
          Expanded(
            child: Text(
              cap,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Próximo mês',
          ),
        ],
      ),
    );
  }
}

/// Busca persistente e visível de transações (aplica no submit; botão de
/// limpar aparece quando há texto). Reaproveita o filtro `search` do backend.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextField(
        controller: widget.controller,
        onSubmitted: widget.onSubmit,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar transações',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Limpar',
                  onPressed: () {
                    widget.controller.clear();
                    widget.onSubmit('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}

/// Filtro por tipo em pílulas sólidas, no topo da tela (não escondido no
/// sheet). Ativo = pílula menta (primário); inativo = superfície com hairline.
class _TypeFilterPills extends StatelessWidget {
  const _TypeFilterPills({required this.selected, required this.onSelect});

  final TransactionType? selected;
  final ValueChanged<TransactionType?> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget pill(String label, TransactionType? value) {
      final sel = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: sel ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => onSelect(value),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: sel ? Colors.transparent : scheme.outline),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          pill('Todas', null),
          pill('Receitas', TransactionType.revenue),
          pill('Despesas', TransactionType.expense),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.tx,
    required this.categoryColor,
    required this.canDelete,
    required this.onDelete,
  });

  final Transaction tx;
  final Color categoryColor;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Gasto comum é NEUTRO (não vermelho — vermelho é urgência, não "toda
    // despesa"); só receita ganha verde. Padrão de app financeiro profissional.
    final text = Theme.of(context).textTheme;
    final color = tx.isExpense
        ? Theme.of(context).colorScheme.onSurface
        : AppColors.successSage;

    final tile = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              tx.isExpense
                  ? Icons.arrow_outward_rounded
                  : Icons.arrow_downward_rounded,
              size: 18,
              color: categoryColor,
            ),
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
                    if (tx.userName != null) tx.userName!,
                    tx.date.br,
                    if (tx.totalInstallments != null)
                      '${tx.installmentNumber}/${tx.totalInstallments}',
                  ].join(' · '),
                  style: text.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            '${tx.isExpense ? '-' : '+'}${tx.amount.brl}',
            style: text.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );

    if (!canDelete) return tile;
    return Dismissible(
      key: ValueKey(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir transação?'),
          content: Text('${tx.description ?? tx.category} — ${tx.amount.brl}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                child: const Text('Excluir')),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: tile,
    );
  }
}

/// Cabeçalho de um dia dentro da lista (net = saldo do dia; null quando o dia
/// pode estar incompleto por paginação, evitando mostrar número errado).
class _DayHeader {
  const _DayHeader(this.day, this.net);
  final DateTime day;
  final double? net;
}

/// Agrupa as transações (já ordenadas por data desc) em cabeçalhos de dia +
/// linhas. O subtotal de cada dia é omitido no último dia carregado quando
/// ainda há mais páginas, para nunca exibir um total parcial como se fosse fechado.
List<Object> _groupByDay(List<Transaction> items, bool hasMore) {
  if (items.isEmpty) return const [];
  String key(DateTime d) => '${d.year}-${d.month}-${d.day}';
  final net = <String, double>{};
  for (final tx in items) {
    final k = key(tx.date);
    net[k] = (net[k] ?? 0) + (tx.isExpense ? -tx.amount : tx.amount);
  }
  final lastKey = key(items.last.date);
  final out = <Object>[];
  String? current;
  for (final tx in items) {
    final k = key(tx.date);
    if (k != current) {
      final partial = hasMore && k == lastKey;
      out.add(_DayHeader(tx.date.dateOnly, partial ? null : net[k]));
      current = k;
    }
    out.add(tx);
  }
  return out;
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day, required this.net});

  final DateTime day;
  final double? net;

  String get _label {
    final d = day.daysUntil;
    if (d == 0) return 'Hoje';
    if (d == -1) return 'Ontem';
    if (d == 1) return 'Amanhã';
    final s = day.dayMonth; // ex.: "12 jul"
    return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Row(
        children: [
          Text(
            _label,
            style: text.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (net != null)
            MoneyText(
              '${net! >= 0 ? '+' : '−'}${net!.abs().brl}',
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final TransactionFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TransactionType? _type = widget.initial.type;
  late String? _category = widget.initial.category;
  late String? _userId = widget.initial.userId;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  late final _search =
      TextEditingController(text: widget.initial.search ?? '');
  late final _tag = TextEditingController(text: widget.initial.tag ?? '');

  List<AppUser> _members = const [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;
    final members = await ref
        .read(authRepositoryProvider)
        .familyMembers(profile!.familyId!);
    if (mounted) setState(() => _members = members);
  }

  @override
  void dispose() {
    _search.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtros avançados',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType?>(
              segments: const [
                ButtonSegment(value: null, label: Text('Tudo')),
                ButtonSegment(
                    value: TransactionType.expense, label: Text('Despesas')),
                ButtonSegment(
                    value: TransactionType.revenue, label: Text('Receitas')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Categories.expense)
                  FilterChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (sel) =>
                        setState(() => _category = sel ? c : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_members.isNotEmpty)
              DropdownButtonFormField<String?>(
                value: _userId,
                decoration:
                    const InputDecoration(hintText: 'Filtrar por pessoa'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Todas as pessoas')),
                  for (final m in _members)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) => setState(() => _userId = v),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _tag,
              decoration: const InputDecoration(
                  hintText: 'Tag (ex.: viagem, escola)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                  hintText: 'Buscar descrição ou beneficiário'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range_rounded),
              label: Text(_from == null
                  ? 'Período'
                  : '${_from!.br} → ${_to!.br}'),
              onPressed: _pickRange,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                        context, const TransactionFilter()),
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      TransactionFilter(
                        type: _type,
                        category: _category,
                        userId: _userId,
                        tag: _tag.text.trim().isEmpty
                            ? null
                            : _tag.text.trim(),
                        from: _from,
                        to: _to,
                        search: _search.text.trim().isEmpty
                            ? null
                            : _search.text.trim(),
                      ),
                    ),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
