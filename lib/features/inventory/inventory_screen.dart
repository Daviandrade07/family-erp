import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../auth/auth_controller.dart';

final inventoryProvider = FutureProvider.autoDispose((ref) {
  ref.watch(aiWriteTickProvider); // dados vivos
  return ref.watch(inventoryRepositoryProvider).all();
});

/// Pantry: expiration badges (green/yellow/red), one-tap consumption
/// (auto decrement) and low-stock trigger feeding the shopping list.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final name = TextEditingController();
    final qty = TextEditingController(text: '1');
    final minQty = TextEditingController(text: '1');
    final location = TextEditingController();
    DateTime? expiration;

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
              Text('Novo item na despensa',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(hintText: 'Produto')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qty,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(hintText: 'Quantidade'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: minQty,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(hintText: 'Qtd. mínima'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: location,
                  decoration: const InputDecoration(
                      hintText: 'Local (geladeira, armário...)')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(expiration == null
                    ? 'Data de validade (opcional)'
                    : 'Vence em ${expiration!.br}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate:
                        DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 365)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setSheet(() => expiration = picked);
                },
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

    if (saved != true || name.text.trim().isEmpty) return;
    await ref.read(inventoryRepositoryProvider).insertRow(InventoryItem(
          familyId: profile!.familyId!,
          productName: name.text.trim(),
          quantity: double.tryParse(qty.text) ?? 1,
          minQuantity: double.tryParse(minQty.text) ?? 1,
          location: location.text.trim().isEmpty
              ? null
              : location.text.trim(),
          expirationDate: expiration,
        ).toInsert());
    ref.invalidate(inventoryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(inventoryProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Despensa')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _addItem(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: items.when(
        loading: () => const LoadingSkeleton(itemCount: 6, itemHeight: 80),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(inventoryProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.kitchen_outlined,
                title: 'Despensa vazia',
                subtitle:
                    'Cadastre os produtos de casa. Itens abaixo do mínimo '
                    'entram sozinhos na lista de compras.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(inventoryProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _InventoryTile(
                    item: list[i],
                    canWrite: auth.canWrite,
                    onConsume: () async {
                      await ref
                          .read(inventoryRepositoryProvider)
                          .consume(list[i], 1);
                      ref.invalidate(inventoryProvider);
                    },
                    onDelete: auth.isAdmin
                        ? () async {
                            await ref
                                .read(inventoryRepositoryProvider)
                                .deleteRow(list[i].id!);
                            ref.invalidate(inventoryProvider);
                          }
                        : null,
                  ),
                ),
              ),
      ),
    );
  }
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({
    required this.item,
    required this.canWrite,
    required this.onConsume,
    this.onDelete,
  });

  final InventoryItem item;
  final bool canWrite;
  final VoidCallback onConsume;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = item.daysToExpire;

    final expirationBadge = days == null
        ? null
        : days < 0
            ? StatusBadge('Vencido há ${-days}d',
                color: AppColors.red, icon: Icons.dangerous_outlined)
            : days <= 3
                ? StatusBadge('Vence em ${days}d',
                    color: AppColors.red, icon: Icons.warning_amber_rounded)
                : days <= 7
                    ? StatusBadge('Vence em ${days}d',
                        color: AppColors.amber, icon: Icons.schedule_rounded)
                    : StatusBadge('OK · ${days}d',
                        color: AppColors.neonGreen,
                        icon: Icons.check_circle_outline);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (expirationBadge != null) expirationBadge,
                    if (item.isLowStock)
                      const StatusBadge('Estoque baixo',
                          color: AppColors.amber,
                          icon: Icons.inventory_2_outlined),
                    if (item.location != null)
                      StatusBadge(item.location!,
                          color: AppColors.techBlue,
                          icon: Icons.place_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit}',
                style:
                    text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('mín. ${item.minQuantity.toStringAsFixed(0)}',
                  style: text.labelSmall),
            ],
          ),
          if (canWrite) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Consumir 1',
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppColors.techBlue),
              onPressed: item.quantity > 0 ? onConsume : null,
            ),
          ],
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
