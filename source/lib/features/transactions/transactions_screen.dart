import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';
import 'transactions_controller.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        ref.read(transactionsControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transações'),
        actions: [
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
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(transactionsControllerProvider.notifier).refresh(),
        child: state.items.isEmpty && state.loading
            ? const LoadingSkeleton(itemCount: 8, itemHeight: 72)
            : state.items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Nenhuma transação',
                      subtitle:
                          'Ajuste os filtros ou lance a primeira despesa.',
                    ),
                  ])
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child:
                              Center(child: CircularProgressIndicator()),
                        );
                      }
                      final tx = state.items[i];
                      return _TransactionTile(
                        tx: tx,
                        canDelete: isAdmin,
                        onDelete: () => ref
                            .read(transactionsControllerProvider.notifier)
                            .delete(tx),
                      );
                    },
                  ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.tx,
    required this.canDelete,
    required this.onDelete,
  });

  final Transaction tx;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = tx.isExpense ? AppColors.red : AppColors.neonGreen;
    final text = Theme.of(context).textTheme;

    final tile = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.categoryColor(tx.category).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              tx.isExpense
                  ? Icons.arrow_outward_rounded
                  : Icons.arrow_downward_rounded,
              size: 18,
              color: AppColors.categoryColor(tx.category),
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
          Text(
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
          color: AppColors.red.withOpacity(0.2),
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
