import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

final billsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(billRepositoryProvider).all());

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final description = TextEditingController();
    final amount = TextEditingController();
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    BillRecurrence recurrence = BillRecurrence.none;
    BillPriority priority = BillPriority.media;
    String? category;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nova conta a pagar',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                  controller: description,
                  decoration: const InputDecoration(
                      hintText: 'Ex.: Energia, Internet, Aluguel')),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    hintText: 'Valor', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text('Vence em ${dueDate.br}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: dueDate,
                    firstDate: DateTime(2020),
                    lastDate:
                        DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setSheet(() => dueDate = picked);
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<BillRecurrence>(
                segments: const [
                  ButtonSegment(
                      value: BillRecurrence.none, label: Text('Única')),
                  ButtonSegment(
                      value: BillRecurrence.monthly, label: Text('Mensal')),
                  ButtonSegment(
                      value: BillRecurrence.yearly, label: Text('Anual')),
                ],
                selected: {recurrence},
                onSelectionChanged: (s) =>
                    setSheet(() => recurrence = s.first),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration:
                    const InputDecoration(hintText: 'Categoria'),
                items: [
                  for (final c in BillCategories.all)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setSheet(() => category = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BillPriority>(
                initialValue: priority,
                decoration:
                    const InputDecoration(hintText: 'Prioridade'),
                items: [
                  for (final p in BillPriority.values)
                    DropdownMenuItem(
                        value: p, child: Text('Prioridade: ${p.labelPt}')),
                ],
                onChanged: (v) =>
                    setSheet(() => priority = v ?? BillPriority.media),
              ),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salvar')),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (description.text.trim().isEmpty || value == null) return;

    await ref.read(billRepositoryProvider).insertRow(Bill(
          familyId: profile!.familyId!,
          description: description.text.trim(),
          amount: value,
          dueDate: dueDate,
          recurrence: recurrence,
          priority: priority,
          category: category,
        ).toInsert());
    ref.invalidate(billsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(billsProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contas a Pagar')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _add(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: bills.when(
        loading: () => const LoadingSkeleton(itemCount: 6, itemHeight: 80),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(billsProvider)),
        data: (list) {
          final pending = list
              .where((b) => b.status == BillStatus.pending)
              .toList();
          final paid = list
              .where((b) => b.status == BillStatus.paid)
              .take(10)
              .toList();

          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Nenhuma conta cadastrada',
              subtitle: 'Contas recorrentes renovam sozinhas ao serem pagas.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(billsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (pending.isNotEmpty) const SectionHeader('Pendentes'),
                for (final b in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _BillTile(
                      bill: b,
                      onPay: auth.canWrite
                          ? () async {
                              await ref
                                  .read(billRepositoryProvider)
                                  .markPaid(b);
                              ref.invalidate(billsProvider);
                            }
                          : null,
                    ),
                  ),
                if (paid.isNotEmpty) const SectionHeader('Pagas'),
                for (final b in paid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Opacity(
                        opacity: 0.6, child: _BillTile(bill: b)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, this.onPay});

  final Bill bill;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = bill.dueDate.daysUntil;

    final badge = bill.status == BillStatus.paid
        ? const StatusBadge('Paga',
            color: AppColors.neonGreen, icon: Icons.check_circle_outline)
        : bill.isOverdue
            ? StatusBadge('Atrasada ${-days}d',
                color: AppColors.red, icon: Icons.error_outline)
            : days <= 3
                ? StatusBadge('Vence em ${days}d',
                    color: AppColors.amber, icon: Icons.schedule_rounded)
                : StatusBadge(bill.dueDate.dayMonth,
                    color: AppColors.techBlue, icon: Icons.event_outlined);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bill.description,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    badge,
                    StatusBadge(
                      bill.priority.labelPt,
                      color: switch (bill.priority) {
                        BillPriority.muitoAlta => AppColors.red,
                        BillPriority.alta => AppColors.amber,
                        BillPriority.media => AppColors.techBlue,
                        BillPriority.baixa => AppColors.neonGreen,
                      },
                      icon: Icons.flag_rounded,
                    ),
                    if (bill.category != null)
                      StatusBadge(bill.category!,
                          color: AppColors.violet,
                          icon: Icons.label_outline_rounded),
                    if (bill.recurrence != BillRecurrence.none)
                      StatusBadge(
                        bill.recurrence == BillRecurrence.monthly
                            ? 'Mensal'
                            : 'Anual',
                        color: AppColors.violet,
                        icon: Icons.repeat_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Text(bill.amount.brl,
              style:
                  text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (onPay != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onPay,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Pagar'),
            ),
          ],
        ],
      ),
    );
  }
}
