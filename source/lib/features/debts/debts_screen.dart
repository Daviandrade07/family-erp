import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

final _debtsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(debtRepositoryProvider).all());

final _installmentsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(transactionRepositoryProvider).upcomingInstallments());

/// Controle de fiado, crediário e dívidas + parcelas a vencer, num lugar só:
/// quanto devo, pra quem e quando vence.
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  Future<void> _addDebt(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final creditor = TextEditingController();
    final amount = TextEditingController();
    final installments = TextEditingController();
    BillPriority priority = BillPriority.media;

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
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Registrar fiado / dívida',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Ex.: fiado na venda da esquina, crediário da loja.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                  controller: creditor,
                  decoration: const InputDecoration(
                      hintText: 'Para quem devo? (loja, pessoa)')),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    hintText: 'Valor total', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: installments,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    hintText: 'Em quantas vezes? (opcional)'),
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
    if (creditor.text.trim().isEmpty || value == null) return;

    await ref.read(debtRepositoryProvider).insertRow(Debt(
          familyId: profile!.familyId!,
          creditor: creditor.text.trim(),
          originalAmount: value,
          remainingAmount: value,
          installments: int.tryParse(installments.text),
          priority: priority,
        ).toInsert());
    ref.invalidate(_debtsProvider);
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, Debt debt) async {
    final amount = TextEditingController(
        text: debt.remainingAmount.toStringAsFixed(2));
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registrar pagamento — ${debt.creditor}',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Restante: ${debt.remainingAmount.brl}',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  hintText: 'Valor pago', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar pagamento')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '.'));
    if (value == null || value <= 0) return;
    await ref.read(debtRepositoryProvider).registerPayment(debt, value);
    ref.invalidate(_debtsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(_debtsProvider);
    final installments = ref.watch(_installmentsProvider);
    final auth = ref.watch(authControllerProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Fiado e Parcelas')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _addDebt(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              icon: const Icon(Icons.add),
              label: const Text('Fiado'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_debtsProvider);
          ref.invalidate(_installmentsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // ---- Total devido ----
            debts.maybeWhen(
              data: (list) {
                final totalDebt =
                    list.fold<double>(0, (s, d) => s + d.remainingAmount);
                final totalInst = installments.maybeWhen(
                    data: (i) => i.fold<double>(0, (s, t) => s + t.amount),
                    orElse: () => 0.0);
                final total = totalDebt + totalInst;
                return AppCard(
                  gradient: LinearGradient(colors: [
                    AppColors.red.withOpacity(0.14),
                    AppColors.amber.withOpacity(0.05),
                  ]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Você deve no total',
                          style: text.labelMedium?.copyWith(
                              color:
                                  text.bodySmall?.color?.withOpacity(0.7))),
                      const SizedBox(height: 4),
                      Text(total.brl,
                          style: text.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.red)),
                      const SizedBox(height: 4),
                      Text(
                          'Fiado/dívidas: ${totalDebt.brl} · Parcelas a vencer: ${totalInst.brl}',
                          style: text.labelSmall),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),

            // ---- Fiado / dívidas ----
            const SectionHeader('Fiado e dívidas'),
            debts.when(
              loading: () =>
                  const LoadingSkeleton(itemCount: 3, itemHeight: 84),
              error: (e, _) => ErrorRetry(
                  message: '$e',
                  onRetry: () => ref.invalidate(_debtsProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.handshake_outlined,
                      title: 'Nenhum fiado registrado',
                      subtitle:
                          'Anote o que comprou fiado ou no crediário para não '
                          'perder o controle de quanto deve e pra quem.',
                    )
                  : Column(
                      children: [
                        for (final d in list)
                          _DebtTile(
                            debt: d,
                            onPay: auth.canWrite
                                ? () => _pay(context, ref, d)
                                : null,
                            onDelete: auth.isAdmin
                                ? () async {
                                    await ref
                                        .read(debtRepositoryProvider)
                                        .deleteRow(d.id!);
                                    ref.invalidate(_debtsProvider);
                                  }
                                : null,
                          ),
                      ],
                    ),
            ),

            // ---- Parcelas a vencer ----
            installments.maybeWhen(
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Parcelas a vencer'),
                        for (final t in list) _InstallmentTile(tx: t),
                      ],
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt, this.onPay, this.onDelete});

  final Debt debt;
  final VoidCallback? onPay;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final paid = debt.originalAmount - debt.remainingAmount;
    final progress =
        debt.originalAmount == 0 ? 0.0 : paid / debt.originalAmount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(debt.creditor,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                StatusBadge(
                  debt.priority.labelPt,
                  color: switch (debt.priority) {
                    BillPriority.muitoAlta => AppColors.red,
                    BillPriority.alta => AppColors.amber,
                    BillPriority.media => AppColors.techBlue,
                    BillPriority.baixa => AppColors.neonGreen,
                  },
                  icon: Icons.flag_rounded,
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DynamicProgressBar(ratio: progress, height: 8),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Falta ${debt.remainingAmount.brl}',
                    style: text.bodySmall?.copyWith(
                        color: AppColors.red, fontWeight: FontWeight.w700)),
                Text(
                    'de ${debt.originalAmount.brl}'
                    '${debt.installments != null ? ' · ${debt.installments}x' : ''}'
                    '${debt.interestRate != null ? ' · ${debt.interestRate!.toStringAsFixed(1)}%/mês' : ''}',
                    style: text.labelSmall),
              ],
            ),
            if (onPay != null && debt.remainingAmount > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onPay,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Registrar pagamento'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.violet.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.credit_card_rounded,
                  size: 18, color: AppColors.violet),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.description ?? tx.category,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    'Parcela ${tx.installmentNumber ?? '?'}/${tx.totalInstallments} · vence ${tx.date.br}',
                    style: text.labelSmall,
                  ),
                ],
              ),
            ),
            Text(tx.amount.brl,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
