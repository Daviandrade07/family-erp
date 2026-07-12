import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../../services/categories/category_rules.dart';
import '../auth/auth_controller.dart';

/// Categorias da família (padrões globais + customizadas). Reage a gravações.
final familyCategoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) {
    ref.watch(aiWriteTickProvider);
    return ref.watch(categoryRepositoryProvider).all(orderBy: 'name', asc: true);
  },
);

/// Categorias NÃO arquivadas de um tipo — insumo dos seletores de criação.
List<Category> categoriesForType(List<Category> all, TransactionType type) =>
    all.where((c) => c.type == type && !c.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

/// Cor da categoria por nome (resolve o token; inclui arquivadas, para colorir
/// o histórico). Fallback no mapa estático conhecido enquanto carrega.
Color categoryColorFor(List<Category>? all, String name) {
  if (all != null) {
    for (final c in all) {
      if (c.name == name) return AppColors.tokenColor(c.colorToken);
    }
  }
  return AppColors.categoryColor(name);
}

const kCategoryIcons = <String, IconData>{
  'tag': Icons.sell_outlined,
  'cart': Icons.shopping_cart_outlined,
  'home': Icons.home_outlined,
  'car': Icons.directions_car_outlined,
  'health': Icons.favorite_outline,
  'food': Icons.restaurant_outlined,
  'fun': Icons.celebration_outlined,
  'money': Icons.payments_outlined,
  'pet': Icons.pets_outlined,
  'study': Icons.school_outlined,
  'bill': Icons.receipt_long_outlined,
  'phone': Icons.smartphone_outlined,
};
IconData categoryIcon(String? key) => kCategoryIcons[key] ?? Icons.sell_outlined;

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(familyCategoriesProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _addOrEdit(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: cats.when(
        loading: () => const LoadingSkeleton(itemHeight: 60),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(familyCategoriesProvider)),
        data: (all) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _section(context, ref, 'Despesas', all, TransactionType.expense,
                auth.canWrite),
            _section(context, ref, 'Receitas', all, TransactionType.revenue,
                auth.canWrite),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, WidgetRef ref, String title,
      List<Category> all, TransactionType type, bool canWrite) {
    final items = all.where((c) => c.type == type).toList()
      ..sort((a, b) {
        if (a.archived != b.archived) return a.archived ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        for (final c in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CategoryRow(
              item: c,
              onTap: (canWrite && !c.isDefault && !c.archived)
                  ? () => _addOrEdit(context, ref, existing: c)
                  : null,
              onArchive: (canWrite && !c.isDefault)
                  ? () => _setArchived(ref, c, !c.archived)
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _setArchived(
      WidgetRef ref, Category c, bool archived) async {
    await ref.read(categoryRepositoryProvider).setArchived(c.id!, archived);
    ref.invalidate(familyCategoriesProvider);
  }

  Future<void> _addOrEdit(BuildContext context, WidgetRef ref,
      {Category? existing}) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;
    final all = ref.read(familyCategoriesProvider).valueOrNull ?? const [];

    final name = TextEditingController(text: existing?.name ?? '');
    TransactionType type = existing?.type ?? TransactionType.expense;
    String colorToken = existing?.colorToken ?? AppColors.categoryTokens.keys.first;
    String? icon = existing?.icon;

    final action = await showModalBottomSheet<String>(
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
              Text(existing == null ? 'Nova categoria' : 'Editar categoria',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (existing == null) ...[
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
              ],
              TextField(
                controller: name,
                decoration: const InputDecoration(hintText: 'Nome da categoria'),
              ),
              const SizedBox(height: 16),
              Text('Cor', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in AppColors.categoryTokens.entries)
                    _Swatch(
                      color: e.value,
                      selected: colorToken == e.key,
                      onTap: () => setSheet(() => colorToken = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Ícone', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in kCategoryIcons.entries)
                    _IconChoice(
                      icon: e.value,
                      color: AppColors.tokenColor(colorToken),
                      selected: icon == e.key,
                      onTap: () => setSheet(() => icon = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('Salvar')),
              if (existing != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: const Text('Excluir categoria',
                      style: TextStyle(color: AppColors.red)),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final repo = ref.read(categoryRepositoryProvider);

    // Excluir: só de vez se não for padrão e não estiver em uso; caso
    // contrário, arquiva (preserva o histórico).
    if (action == 'delete' && existing != null) {
      final inUse = await repo.isInUse(existing.name);
      if (canDeleteCategory(existing, inUse: inUse)) {
        await repo.deleteRow(existing.id!);
        if (context.mounted) AppFeedback.success(context, 'Categoria excluída.');
      } else {
        await repo.setArchived(existing.id!, true);
        if (context.mounted) {
          AppFeedback.info(
              context, 'Categoria em uso — arquivada em vez de excluída.');
        }
      }
      ref.invalidate(familyCategoriesProvider);
      return;
    }

    if (action != 'save') return;
    final newName = name.text.trim();
    if (!categoryNameAvailable(newName, type, all, excludingId: existing?.id)) {
      if (context.mounted) {
        AppFeedback.error(
            context,
            newName.isEmpty
                ? 'Dê um nome à categoria.'
                : 'Já existe uma categoria "$newName".');
      }
      return;
    }

    if (existing == null) {
      await repo.insertRow(Category(
        familyId: profile!.familyId,
        name: newName,
        type: type,
        colorToken: colorToken,
        icon: icon,
      ).toInsert());
    } else {
      if (existing.name != newName) {
        await repo.rename(existing.id!, existing.name, newName);
      }
      await repo.updateRow(existing.id!, {
        'color_token': colorToken,
        if (icon != null) 'icon': icon,
      });
    }
    ref.invalidate(familyCategoriesProvider);
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.item, this.onTap, this.onArchive});

  final Category item;
  final VoidCallback? onTap;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = AppColors.tokenColor(item.colorToken);
    return Opacity(
      opacity: item.archived ? 0.5 : 1,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(categoryIcon(item.icon), size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.name,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (item.isDefault)
              const StatusBadge('Padrão', color: AppColors.lagoon)
            else if (item.archived)
              TextButton(
                  onPressed: onArchive, child: const Text('Restaurar'))
            else if (onArchive != null)
              IconButton(
                tooltip: 'Arquivar',
                icon: const Icon(Icons.archive_outlined, size: 20),
                onPressed: onArchive,
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : scheme.outline, width: selected ? 2 : 1),
        ),
        child: Icon(icon, size: 20, color: selected ? color : scheme.onSurface),
      ),
    );
  }
}
