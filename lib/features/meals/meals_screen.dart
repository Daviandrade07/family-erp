import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/meal_ai_suggester.dart';
import '../../services/ai/meal_suggester.dart';
import '../auth/auth_controller.dart';

final _weekPlanProvider =
    FutureProvider.autoDispose.family<MealPlan?, DateTime>(
        (ref, weekStart) => ref.watch(mealRepositoryProvider).forWeek(weekStart));

/// Weekly menu assistant driven by the pantry contents.
class MealsScreen extends ConsumerStatefulWidget {
  const MealsScreen({super.key});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  DateTime _weekStart = DateTime.now().startOfWeek;
  bool _generating = false;

  static const _dayLabels = {
    'monday': 'Segunda',
    'tuesday': 'Terça',
    'wednesday': 'Quarta',
    'thursday': 'Quinta',
    'friday': 'Sexta',
    'saturday': 'Sábado',
    'sunday': 'Domingo',
  };

  /// Joga na lista de compras os itens que faltam (deduplicando com o que já
  /// está pendente). Resolve a falha crônica do Paprika: planejar refeição sem
  /// gerar a lista de compras.
  Future<void> _addMissingToShopping(List<String> items) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null || items.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(shoppingRepositoryProvider);
      final existing = await repo.all();
      final pending = existing
          .where((i) => !i.isBought)
          .map((i) => i.itemName.trim().toLowerCase())
          .toSet();

      var added = 0;
      for (final name in items) {
        final clean = name.trim();
        if (clean.isEmpty || pending.contains(clean.toLowerCase())) continue;
        await repo.insertRow(ShoppingItem(
          familyId: profile!.familyId!,
          itemName: clean,
          quantity: 1,
          executionData: const {'source': 'cardapio'},
        ).toInsert());
        pending.add(clean.toLowerCase());
        added++;
      }
      messenger.showSnackBar(SnackBar(
          content: Text(added == 0
              ? 'Esses itens já estão na lista de compras.'
              : '$added item(ns) adicionado(s) à lista de compras.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Erro ao adicionar à lista: $e'),
          backgroundColor: AppColors.red));
    }
  }

  Future<void> _generate() async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    setState(() => _generating = true);
    try {
      final menu = await ref.read(mealSuggesterProvider).suggestWeek();
      await ref.read(mealRepositoryProvider).upsert(MealPlan(
            familyId: profile!.familyId!,
            weekStart: _weekStart,
            menuData: menu,
          ));
      ref.invalidate(_weekPlanProvider(_weekStart));
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
            context, 'Não foi possível gerar o cardápio agora. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(_weekPlanProvider(_weekStart));
    final canWrite = ref.watch(authControllerProvider).canWrite;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cardápio Semanal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _weekStart =
                    _weekStart.subtract(const Duration(days: 7))),
              ),
              Expanded(
                child: Text(
                  'Semana de ${_weekStart.dayMonth}',
                  textAlign: TextAlign.center,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => setState(() =>
                    _weekStart = _weekStart.add(const Duration(days: 7))),
              ),
            ],
          ),
          if (canWrite)
            FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restaurant_menu_rounded),
              label: Text(_generating
                  ? 'Analisando a despensa...'
                  : 'Gerar cardápio da semana'),
            ),
          const SizedBox(height: 12),
          _DishSuggestions(
              onAddMissing: canWrite ? _addMissingToShopping : null),
          const SizedBox(height: 8),
          plan.when(
            loading: () =>
                const LoadingSkeleton(itemCount: 4, itemHeight: 90),
            error: (e, _) => ErrorRetry(
                message: '$e',
                onRetry: () =>
                    ref.invalidate(_weekPlanProvider(_weekStart))),
            data: (p) {
              if (p == null) {
                return const EmptyState(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Sem cardápio para esta semana',
                  subtitle:
                      'Gere um cardápio com a IA: ela prioriza o que está '
                      'vencendo na despensa para evitar desperdício.',
                );
              }
              final missing =
                  (p.menuData['_missing_ingredients'] as List?)
                          ?.cast<String>() ??
                      const [];
              return Column(
                children: [
                  for (final day in _dayLabels.entries)
                    if (p.menuData[day.key] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(day.value,
                                  style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.techBlue)),
                              const SizedBox(height: 8),
                              _MealRow(
                                  icon: Icons.wb_sunny_outlined,
                                  label: 'Almoço',
                                  value: p.menuData[day.key]['lunch'] ?? '—'),
                              const SizedBox(height: 6),
                              _MealRow(
                                  icon: Icons.nightlight_outlined,
                                  label: 'Jantar',
                                  value:
                                      p.menuData[day.key]['dinner'] ?? '—'),
                            ],
                          ),
                        ),
                      ),
                  if (missing.isNotEmpty)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shopping_basket_outlined,
                                  size: 18, color: AppColors.amber),
                              const SizedBox(width: 8),
                              Text('Faltam na despensa',
                                  style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final m in missing)
                                StatusBadge(m, color: AppColors.amber),
                            ],
                          ),
                          if (canWrite) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    _addMissingToShopping(missing),
                                icon: const Icon(
                                    Icons.add_shopping_cart_rounded, size: 18),
                                label: const Text(
                                    'Adicionar tudo à lista de compras'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.amber),
        const SizedBox(width: 8),
        Text('$label: ', style: text.labelMedium),
        Expanded(
          child: Text(value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Seção "O que dá pra fazer com o que tenho?": a IA olha a despensa real e
/// sugere pratos, priorizando o que está perto de vencer.
class _DishSuggestions extends ConsumerWidget {
  const _DishSuggestions({this.onAddMissing});

  /// Callback para jogar os itens que faltam de um prato na lista de compras.
  final void Function(List<String> items)? onAddMissing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(dishSuggestionsProvider);
    final text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.soup_kitchen_rounded,
                  size: 18, color: AppColors.neonGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text('O que dá pra fazer com o que tenho?',
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Atualizar sugestões',
                onPressed: () => ref.invalidate(dishSuggestionsProvider),
              ),
            ],
          ),
          const SizedBox(height: 4),
          suggestions.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('A IA está olhando sua despensa...'),
                ],
              ),
            ),
            error: (e, _) => ErrorRetry(
                message: '$e',
                onRetry: () => ref.invalidate(dishSuggestionsProvider)),
            data: (dishes) {
              if (dishes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Cadastre itens na despensa para eu sugerir pratos.',
                    style: text.bodySmall,
                  ),
                );
              }
              return Column(
                children: [
                  for (final d in dishes)
                    _DishTile(dish: d, onAddMissing: onAddMissing),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DishTile extends StatelessWidget {
  const _DishTile({required this.dish, this.onAddMissing});

  final DishSuggestion dish;
  final void Function(List<String> items)? onAddMissing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dish.name,
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (dish.usesExpiring)
                const StatusBadge('Usa o que vence',
                    color: AppColors.amber,
                    icon: Icons.hourglass_bottom_rounded),
            ],
          ),
          if (dish.have.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Você tem: ${dish.have.join(', ')}',
                  style: text.labelSmall
                      ?.copyWith(color: AppColors.neonGreen)),
            ),
          if (dish.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('Falta comprar: ${dish.missing.join(', ')}',
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.amber)),
                  ),
                  if (onAddMissing != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Adicionar o que falta à lista de compras',
                      icon: const Icon(Icons.add_shopping_cart_rounded,
                          size: 18, color: AppColors.amber),
                      onPressed: () => onAddMissing!(dish.missing),
                    ),
                ],
              ),
            ),
          const Divider(height: 12),
        ],
      ),
    );
  }
}
