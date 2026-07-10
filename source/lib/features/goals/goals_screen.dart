import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

final goalsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(goalRepositoryProvider).all());

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  Future<void> _addOrDeposit(BuildContext context, WidgetRef ref,
      {FinancialGoal? goal}) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final name = TextEditingController(text: goal?.name ?? '');
    final target = TextEditingController(
        text: goal == null ? '' : goal.targetAmount.toStringAsFixed(0));
    final deposit = TextEditingController();
    DateTime? deadline = goal?.deadline;

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
              Text(goal == null ? 'Nova meta' : 'Atualizar meta',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      hintText: 'Ex.: Viagem, Reserva de emergência')),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    hintText: 'Valor alvo', prefixText: 'R\$ '),
              ),
              if (goal != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: deposit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'Aportar agora (+)', prefixText: 'R\$ '),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(deadline == null
                    ? 'Prazo (opcional)'
                    : 'Até ${deadline!.br}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate:
                        DateTime.now().add(const Duration(days: 180)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setSheet(() => deadline = picked);
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

    if (saved != true) return;
    final targetValue =
        double.tryParse(target.text.replaceAll(',', '.'));
    if (name.text.trim().isEmpty || targetValue == null) return;

    final repo = ref.read(goalRepositoryProvider);
    if (goal == null) {
      await repo.insertRow(FinancialGoal(
        familyId: profile!.familyId!,
        name: name.text.trim(),
        targetAmount: targetValue,
        currentAmount: 0,
        deadline: deadline,
      ).toInsert());
    } else {
      final add =
          double.tryParse(deposit.text.replaceAll(',', '.')) ?? 0;
      await repo.updateRow(goal.id!, {
        'name': name.text.trim(),
        'target_amount': targetValue,
        'current_amount': goal.currentAmount + add,
        'deadline': deadline?.toIso8601String().substring(0, 10),
      });
    }
    ref.invalidate(goalsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Metas Financeiras')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _addOrDeposit(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: goals.when(
        loading: () => const LoadingSkeleton(itemCount: 4, itemHeight: 110),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(goalsProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.flag_outlined,
                title: 'Nenhuma meta ainda',
                subtitle:
                    'Crie metas como "Viagem" ou "Reserva de emergência" e '
                    'acompanhe o progresso da família.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final g = list[i];
                  final text = Theme.of(context).textTheme;
                  final daysLeft = g.deadline?.daysUntil;
                  return AppCard(
                    onTap: auth.canWrite
                        ? () => _addOrDeposit(context, ref, goal: g)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(g.name,
                                  style: text.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700)),
                            ),
                            StatusBadge(
                              g.progress.pct,
                              color: g.progress >= 1
                                  ? AppColors.neonGreen
                                  : AppColors.techBlue,
                              icon: g.progress >= 1
                                  ? Icons.emoji_events_outlined
                                  : Icons.flag_outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DynamicProgressBar(ratio: g.progress, height: 12),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '${g.currentAmount.brl} de ${g.targetAmount.brl}',
                                style: text.bodySmall),
                            if (daysLeft != null)
                              Text(
                                daysLeft >= 0
                                    ? '$daysLeft dias restantes'
                                    : 'Prazo vencido',
                                style: text.labelSmall?.copyWith(
                                    color: daysLeft >= 0
                                        ? null
                                        : AppColors.red),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
