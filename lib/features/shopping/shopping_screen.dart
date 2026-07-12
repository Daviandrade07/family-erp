import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/shopping_recommender.dart';
import '../auth/auth_controller.dart';

final shoppingListProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(shoppingRepositoryProvider).all());

/// Shopping list + the AI market recommendation (single stop vs split).
class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key});

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final name = TextEditingController();
    final qty = TextEditingController(text: '1');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Adicionar à lista',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Item')),
            const SizedBox(height: 12),
            TextField(
                controller: qty,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(hintText: 'Quantidade')),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Adicionar')),
          ],
        ),
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return;
    await ref.read(shoppingRepositoryProvider).insertRow(ShoppingItem(
          familyId: profile!.familyId!,
          itemName: name.text.trim(),
          quantity: double.tryParse(qty.text) ?? 1,
        ).toInsert());
    ref.invalidate(shoppingListProvider);
    ref.invalidate(shoppingRecommendationProvider);
  }

  Future<void> _markBought(
      BuildContext context, WidgetRef ref, ShoppingItem item) async {
    final price = TextEditingController();
    final market = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comprou "${item.itemName}"?',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Informe preço e mercado para alimentar o histórico de preços '
              'da IA (opcional).',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  hintText: 'Preço unitário', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: market,
                decoration:
                    const InputDecoration(hintText: 'Mercado')),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar compra')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    await ref.read(shoppingRepositoryProvider).markBought(
          item,
          unitPrice: double.tryParse(price.text.replaceAll(',', '.')),
          market:
              market.text.trim().isEmpty ? null : market.text.trim(),
        );
    ref.invalidate(shoppingListProvider);
    ref.invalidate(shoppingRecommendationProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(shoppingListProvider);
    final recommendation = ref.watch(shoppingRecommendationProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lista de Compras')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _addItem(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: list.when(
        loading: () => const LoadingSkeleton(itemCount: 6, itemHeight: 64),
        error: (e, _) => ErrorRetry(
            message: '$e',
            onRetry: () => ref.invalidate(shoppingListProvider)),
        data: (items) {
          final pending = items.where((i) => !i.isBought).toList();
          final bought = items.where((i) => i.isBought).take(10).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(shoppingListProvider);
              ref.invalidate(shoppingRecommendationProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                recommendation.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (rec) => rec == null
                      ? const SizedBox.shrink()
                      : _RecommendationCard(rec: rec),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: _ImportListTile(),
                ),
                if (pending.isEmpty)
                  const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Lista vazia',
                    subtitle:
                        'Itens com estoque baixo na despensa entram aqui '
                        'automaticamente.',
                  )
                else ...[
                  const SectionHeader('Pendentes'),
                  for (final item in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ShoppingTile(
                        item: item,
                        canWrite: auth.canWrite,
                        onBought: () => _markBought(context, ref, item),
                        onDelete: auth.isAdmin
                            ? () async {
                                await ref
                                    .read(shoppingRepositoryProvider)
                                    .deleteRow(item.id!);
                                ref.invalidate(shoppingListProvider);
                                ref.invalidate(
                                    shoppingRecommendationProvider);
                              }
                            : null,
                      ),
                    ),
                ],
                if (bought.isNotEmpty) ...[
                  const SectionHeader('Compradas recentemente'),
                  for (final item in bought)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Opacity(
                        opacity: 0.6,
                        child: _ShoppingTile(
                            item: item, canWrite: false, onBought: () {}),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Importação de lista por foto — HONESTA: a leitura real ainda está em
/// preparação, e a opção deixa isso claro em vez de fingir que funciona
/// (Design System: nunca parecer funcional sem ser). O toque explica a
/// alternativa que já funciona hoje (ditar para a assistente).
class _ImportListTile extends StatelessWidget {
  const _ImportListTile();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Opacity(
      opacity: 0.8,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A leitura de foto está em preparação. Por '
                'enquanto, dite os itens para a assistente: '
                '"adiciona arroz e feijão na lista".'))),
        child: Row(
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 20, color: Theme.of(context).disabledColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Importar lista por foto',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text('Fotografe a lista e eu digito por você.',
                      style: text.labelSmall),
                ],
              ),
            ),
            const StatusBadge('Em preparação', color: AppColors.amber),
          ],
        ),
      ),
    );
  }
}

class _ShoppingTile extends StatelessWidget {
  const _ShoppingTile({
    required this.item,
    required this.canWrite,
    required this.onBought,
    this.onDelete,
  });

  final ShoppingItem item;
  final bool canWrite;
  final VoidCallback onBought;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Checkbox(
            value: item.isBought,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            onChanged:
                canWrite && !item.isBought ? (_) => onBought() : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration:
                        item.isBought ? TextDecoration.lineThrough : null,
                  ),
                ),
                Row(
                  children: [
                    Text('${item.quantity.toStringAsFixed(0)} un',
                        style: text.labelSmall),
                    if (item.isAutoGenerated) ...[
                      const SizedBox(width: 6),
                      const StatusBadge('Auto',
                          color: AppColors.techBlue,
                          icon: Icons.autorenew_rounded),
                    ],
                    if (item.executionData['unit_price'] != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        ((item.executionData['unit_price'] as num)
                                .toDouble())
                            .brl,
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.neonGreen),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
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

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec});

  final ShoppingRecommendation rec;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 18, color: AppColors.techBlue),
              const SizedBox(width: 8),
              Text('Onde comprar',
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              StatusBadge(
                rec.strategy == 'split' ? 'Dividir lista' : 'Um mercado',
                color: AppColors.neonGreen,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(rec.summary, style: text.bodySmall),
          if (rec.strategy == 'split') ...[
            const SizedBox(height: 10),
            for (final entry in rec.splitPlan.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${entry.key}: ${entry.value.map((q) => q.item).join(', ')}',
                  style: text.labelSmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
