import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../../services/recurrence/recurrence_engine.dart';
import '../auth/auth_controller.dart';
import '../categories/categories_screen.dart';

final recurringProvider = FutureProvider.autoDispose<List<RecurringTransaction>>(
  (ref) {
    ref.watch(aiWriteTickProvider);
    return ref.watch(recurringRepositoryProvider).all(orderBy: 'next_run', asc: true);
  },
);

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _freqLabel(RecurrenceFrequency f, int n) {
  switch (f) {
    case RecurrenceFrequency.weekly:
      return n == 1 ? 'Semanal' : 'A cada $n semanas';
    case RecurrenceFrequency.monthly:
      return n == 1 ? 'Mensal' : 'A cada $n meses';
    case RecurrenceFrequency.yearly:
      return n == 1 ? 'Anual' : 'A cada $n anos';
  }
}

/// Ocorrências ainda não lançadas, de next_run até hoje.
List<DateTime> _pending(RecurringTransaction r) => dueOccurrences(
      startedAt: r.startedAt,
      frequency: r.frequency,
      intervalCount: r.intervalCount,
      after: r.nextRun.subtract(const Duration(days: 1)),
      through: _today(),
    );

/// Recorrentes: assinaturas, salário, aluguel. A pessoa cria a regra; nada é
/// lançado sozinho — quando há ocorrências vencidas, um botão "Lançar" as
/// registra (a IA sugere, não impõe).
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurring = ref.watch(recurringProvider);
    final auth = ref.watch(authControllerProvider);
    final allCats = ref.watch(familyCategoriesProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Recorrentes')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _addOrEdit(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: recurring.when(
        loading: () => const LoadingSkeleton(itemHeight: 110),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(recurringProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.autorenew_rounded,
                title: 'Nenhum recorrente ainda',
                subtitle:
                    'Cadastre o que se repete — assinaturas, salário, aluguel — '
                    'e acompanhe as próximas datas num lugar só.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final r in list) ...[
                    _RecurringCard(
                      item: r,
                      color: categoryColorFor(allCats, r.category),
                      onTap: auth.canWrite
                          ? () => _addOrEdit(context, ref, existing: r)
                          : null,
                      onToggle: auth.canWrite
                          ? (v) => _setActive(ref, r, v)
                          : null,
                      onPost: auth.canWrite ? () => _post(context, ref, r) : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _setActive(
      WidgetRef ref, RecurringTransaction r, bool active) async {
    await ref.read(recurringRepositoryProvider).setActive(r.id!, active);
    ref.invalidate(recurringProvider);
  }

  /// Lança as ocorrências vencidas como transações (ligadas via recurring_id) e
  /// avança last_run/next_run.
  Future<void> _post(
      BuildContext context, WidgetRef ref, RecurringTransaction r) async {
    final pending = _pending(r);
    if (pending.isEmpty) return;
    final profile = ref.read(authControllerProvider).profile;
    if (profile == null) return;
    final txRepo = ref.read(transactionRepositoryProvider);
    for (final date in pending) {
      await txRepo.insert(Transaction(
        familyId: r.familyId,
        userId: profile.id,
        type: r.type,
        amount: r.amount,
        category: r.category,
        description: r.description,
        date: date,
        accountId: r.accountId,
        cardId: r.cardId,
        recurringId: r.id,
      ));
    }
    final last = pending.last;
    final nextRun = nextOccurrence(
      startedAt: r.startedAt,
      frequency: r.frequency,
      intervalCount: r.intervalCount,
      after: last,
    );
    await ref.read(recurringRepositoryProvider).updateRow(r.id!, {
      'last_run': last.toIso8601String().substring(0, 10),
      'next_run': nextRun.toIso8601String().substring(0, 10),
    });
    ref.read(aiWriteTickProvider.notifier).state++; // atualiza Finanças/Início
    ref.invalidate(recurringProvider);
    if (context.mounted) {
      AppFeedback.success(
          context, '${pending.length} lançamento(s) registrado(s).');
    }
  }

  Future<void> _addOrEdit(BuildContext context, WidgetRef ref,
      {RecurringTransaction? existing}) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final desc = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : existing.amount.toStringAsFixed(2));
    final interval = TextEditingController(
        text: (existing?.intervalCount ?? 1).toString());
    TransactionType type = existing?.type ?? TransactionType.expense;
    RecurrenceFrequency freq = existing?.frequency ?? RecurrenceFrequency.monthly;
    final allCats =
        ref.read(familyCategoriesProvider).valueOrNull ?? const <Category>[];
    List<String> catNames(TransactionType t) {
      final names = categoriesForType(allCats, t).map((c) => c.name).toList();
      return names.isEmpty
          ? (t == TransactionType.expense
              ? Categories.expense
              : Categories.revenue)
          : names;
    }

    String category = existing?.category ?? catNames(type).first;
    DateTime startedAt = existing?.startedAt ?? _today();

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
          builder: (ctx, setSheet) {
            final cats = catNames(type);
            if (!cats.contains(category)) category = cats.first;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'Novo recorrente' : 'Editar recorrente',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                SegmentedButton<TransactionType>(
                  segments: const [
                    ButtonSegment(
                        value: TransactionType.expense, label: Text('Despesa')),
                    ButtonSegment(
                        value: TransactionType.revenue, label: Text('Receita')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setSheet(() => type = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: desc,
                    decoration: const InputDecoration(
                        hintText: 'Descrição (ex.: Netflix, Aluguel)')),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: 'Valor', prefixText: 'R\$ '),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: [
                    for (final c in cats)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setSheet(() => category = v!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<RecurrenceFrequency>(
                        initialValue: freq,
                        items: const [
                          DropdownMenuItem(
                              value: RecurrenceFrequency.weekly,
                              child: Text('Semanal')),
                          DropdownMenuItem(
                              value: RecurrenceFrequency.monthly,
                              child: Text('Mensal')),
                          DropdownMenuItem(
                              value: RecurrenceFrequency.yearly,
                              child: Text('Anual')),
                        ],
                        onChanged: (v) => setSheet(() => freq = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: interval,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'A cada', hintText: '1'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Começa em ${startedAt.br}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: startedAt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setSheet(() => startedAt = picked);
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Salvar')),
                if (existing != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );

    if (saved != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) return;
    final n = int.tryParse(interval.text.trim()) ?? 1;
    final step = n < 1 ? 1 : n;

    // next_run = primeira ocorrência a partir de hoje (não faz backfill do
    // passado ao criar) — ou continua de last_run ao editar.
    final after =
        existing?.lastRun ?? _today().subtract(const Duration(days: 1));
    final nextRun = nextOccurrence(
      startedAt: startedAt,
      frequency: freq,
      intervalCount: step,
      after: after.isBefore(startedAt)
          ? startedAt.subtract(const Duration(days: 1))
          : after,
    );

    final repo = ref.read(recurringRepositoryProvider);
    if (existing == null) {
      await repo.insertRow(RecurringTransaction(
        familyId: profile!.familyId!,
        userId: profile.id,
        type: type,
        amount: value,
        category: category,
        description: desc.text.trim().isEmpty ? null : desc.text.trim(),
        frequency: freq,
        intervalCount: step,
        startedAt: startedAt,
        nextRun: nextRun,
      ).toInsert());
    } else {
      await repo.updateRow(existing.id!, {
        'type': type.name,
        'amount': value,
        'category': category,
        'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
        'frequency': freq.name,
        'interval_count': step,
        'started_at': startedAt.toIso8601String().substring(0, 10),
        'next_run': nextRun.toIso8601String().substring(0, 10),
      });
    }
    ref.invalidate(recurringProvider);
  }
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({
    required this.item,
    required this.color,
    required this.onTap,
    required this.onToggle,
    required this.onPost,
  });

  final RecurringTransaction item;
  final Color color;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onPost;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = item;
    final pending = r.active ? _pending(r) : const <DateTime>[];
    final since = occurrencesSoFar(
      startedAt: r.startedAt,
      frequency: r.frequency,
      intervalCount: r.intervalCount,
      asOf: _today(),
    );
    return Opacity(
      opacity: r.active ? 1 : 0.55,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.autorenew_rounded, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.description ?? r.category,
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${_freqLabel(r.frequency, r.intervalCount)} · ${r.category}',
                        style: text.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${r.isExpense ? '-' : '+'}${r.amount.brl}',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: r.isExpense
                        ? Theme.of(context).colorScheme.onSurface
                        : AppColors.successSage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Próxima: ${r.nextRun.dayMonth} · repete há $since',
                    style: text.labelSmall,
                  ),
                ),
                if (onToggle != null)
                  Switch(
                    value: r.active,
                    onChanged: onToggle,
                  ),
              ],
            ),
            if (pending.isNotEmpty && onPost != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onPost,
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: Text('Lançar ${pending.length} pendente(s)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
