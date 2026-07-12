import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../auth/auth_controller.dart';

final billsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(aiWriteTickProvider); // dados vivos: atualiza quando a IA grava
  return ref.watch(billRepositoryProvider).all();
});

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  Future<void> _billSheet(BuildContext context, WidgetRef ref,
      {Bill? existing}) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final description = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(
        text: existing != null ? existing.amount.toStringAsFixed(2) : '');
    DateTime dueDate =
        existing?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    BillRecurrence recurrence = existing?.recurrence ?? BillRecurrence.none;
    BillPriority priority = existing?.priority ?? BillPriority.media;
    String? category = existing?.category;

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
              Text(existing == null ? 'Nova conta a pagar' : 'Editar conta',
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

    final data = Bill(
      familyId: profile!.familyId!,
      description: description.text.trim(),
      amount: value,
      dueDate: dueDate,
      recurrence: recurrence,
      priority: priority,
      category: category,
    ).toInsert();
    if (existing != null) {
      await ref.read(billRepositoryProvider).updateRow(existing.id!, data);
    } else {
      await ref.read(billRepositoryProvider).insertRow(data);
    }
    ref.invalidate(billsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Bill bill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover conta?'),
        content: Text('${bill.description} — ${bill.amount.brl}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(billRepositoryProvider).deleteRow(bill.id!);
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
              onPressed: () => _billSheet(context, ref),
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
              title: 'Nenhuma conta por enquanto',
              subtitle: 'Cadastre a primeira no + e eu aviso antes de vencer. '
                  'As recorrentes renovam sozinhas ao serem pagas.',
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
                      onEdit: auth.canWrite
                          ? () => _billSheet(context, ref, existing: b)
                          : null,
                      onDelete:
                          auth.isAdmin ? () => _delete(context, ref, b) : null,
                    ),
                  ),
                if (paid.isNotEmpty) const SectionHeader('Pagas'),
                for (final b in paid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Opacity(
                      opacity: 0.6,
                      child: _BillTile(
                        bill: b,
                        onDelete: auth.isAdmin
                            ? () => _delete(context, ref, b)
                            : null,
                      ),
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

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, this.onPay, this.onEdit, this.onDelete});

  final Bill bill;
  final VoidCallback? onPay;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
                // Dieta de badges (Design System): 1 badge de status; o resto
                // é texto — prioridade não é urgência, então não leva cor.
                Row(children: [badge]),
                const SizedBox(height: 4),
                Text(
                  [
                    if (bill.category != null) bill.category!,
                    'Prioridade ${bill.priority.labelPt.toLowerCase()}',
                    if (bill.recurrence != BillRecurrence.none)
                      bill.recurrence == BillRecurrence.monthly
                          ? 'Mensal'
                          : 'Anual',
                  ].join(' · '),
                  style: text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(bill.amount.brl,
              style:
                  text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (onPay != null) ...[
            const SizedBox(width: 8),
            // Outlined: a ação primária (verde) da tela é o FAB de criar —
            // N botões "Pagar" verdes competindo violam o Design System.
            OutlinedButton(
              onPressed: onPay,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Pagar'),
            ),
          ],
          if (onEdit != null || onDelete != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('Remover')),
              ],
            ),
        ],
      ),
    );
  }
}
