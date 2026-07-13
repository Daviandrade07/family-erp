import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/hero_card.dart';
import '../../core/widgets/money_text.dart';
import 'paused_goals_controller.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

/// Metas da FAMÍLIA (userId null) — exclui metas pessoais de qualquer membro.
/// Metas pessoais aparecem só na Home KinFin (Modo Solo), não aqui.
final goalsProvider = FutureProvider.autoDispose((ref) async {
  final all = await ref.watch(goalRepositoryProvider).all();
  return all.where((g) => !g.isPersonal).toList();
});

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

  /// Ritmos da meta: oferecer, explicar e deixar escolher — nunca cobrar.
  Future<void> _showPaceSheet(
      BuildContext context, WidgetRef ref, FinancialGoal g, bool paused) async {
    final text = Theme.of(context).textTheme;
    final remaining =
        (g.targetAmount - g.currentAmount).clamp(0, double.infinity);
    final days = g.deadline?.daysUntil;
    String? confortavel;
    String? acelerar;
    if (remaining > 0 && days != null && days > 0) {
      final months = (days / 30).ceil().clamp(1, 600);
      confortavel = '${(remaining / months).brl}/mês até ${g.deadline!.dayMonth}';
      final fast = (months / 2).ceil().clamp(1, 600);
      acelerar = '${(remaining / fast).brl}/mês para chegar ~2× antes';
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ritmo — ${g.name}',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Sugestões calmas. Você escolhe o passo — nada de cobrança.',
                style: text.labelMedium),
            const SizedBox(height: 16),
            if (confortavel != null) ...[
              _PaceRow(
                  icon: Icons.self_improvement_rounded,
                  color: AppColors.successSage,
                  title: 'Confortável',
                  subtitle: 'Guardando $confortavel.'),
              const SizedBox(height: 10),
              _PaceRow(
                  icon: Icons.speed_rounded,
                  color: AppColors.brandLagoon,
                  title: 'Acelerar',
                  subtitle: 'Guardando $acelerar.'),
              const SizedBox(height: 10),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                    'Defina um prazo na meta para ver o ritmo sugerido.',
                    style: text.bodyMedium),
              ),
            _PaceRow(
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.amber,
              title: paused ? 'Retomar meta' : 'Pausar meta',
              subtitle: paused
                  ? 'Voltar a acompanhar esta meta.'
                  : 'Tira a pressão: some das ativas até você retomar.',
              onTap: () {
                ref.read(pausedGoalsProvider.notifier).toggle(g.id!);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final auth = ref.watch(authControllerProvider);
    final paused = ref.watch(pausedGoalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas Financeiras'),
        actions: const [PrivacyToggle()],
      ),
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
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.flag_outlined,
              title: 'Nenhuma meta ainda',
              subtitle:
                  'Crie metas como "Viagem" ou "Reserva de emergência" e '
                  'acompanhe o progresso da família.',
            );
          }
          final text = Theme.of(context).textTheme;
          bool isPaused(FinancialGoal g) => paused.contains(g.id);
          // Resumo no topo: metas PAUSADAS não entram em "ativas" nem em
          // "falta economizar" — pausar tira a pressão, sem sumir com a meta.
          final ativas =
              list.where((g) => g.progress < 1 && !isPaused(g)).length;
          final concluidas = list.where((g) => g.progress >= 1).length;
          final acumulado =
              list.fold<double>(0, (s, g) => s + g.currentAmount);
          final falta = list.where((g) => !isPaused(g)).fold<double>(
              0,
              (s, g) =>
                  s + (g.targetAmount - g.currentAmount).clamp(0, double.infinity));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Eyebrow('Metas'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _GoalStat(
                        icon: Icons.flag_outlined,
                        label: 'Metas ativas',
                        value: '$ativas',
                        accent: AppColors.brandLagoon)),
                const SizedBox(width: 12),
                Expanded(
                    child: _GoalStat(
                        icon: Icons.savings_outlined,
                        label: 'Total acumulado',
                        value: acumulado.brlCompact,
                        accent: AppColors.successSage,
                        money: true)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _GoalStat(
                        icon: Icons.trending_up_rounded,
                        label: 'Falta economizar',
                        value: falta.brlCompact,
                        accent: AppColors.amber,
                        money: true)),
                const SizedBox(width: 12),
                Expanded(
                    child: _GoalStat(
                        icon: Icons.emoji_events_outlined,
                        label: 'Concluídas',
                        value: '$concluidas',
                        accent: Theme.of(context).colorScheme.primary)),
              ]),
              const SizedBox(height: 22),
              Text('Suas metas',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final g in list) ...[
                _GoalCard(
                  goal: g,
                  paused: isPaused(g),
                  onTap: auth.canWrite
                      ? () => _addOrDeposit(context, ref, goal: g)
                      : null,
                  onPace: (auth.canWrite && g.id != null)
                      ? () => _showPaceSheet(context, ref, g, isPaused(g))
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Cartão-estatística do resumo de metas: ícone tingido + número grande
/// (serifado pelo tema) + rótulo. Compacto, para caber dois por linha.
class _GoalStat extends StatelessWidget {
  const _GoalStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.money = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  /// Se o valor é dinheiro (respeita o modo privacidade). Contagens não.
  final bool money;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: money
                ? MoneyText(value,
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700))
                : Text(value,
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: text.labelSmall?.copyWith(
                  color: text.bodySmall?.color?.withValues(alpha: 0.7)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Cartão de uma meta: nome, % , barra de progresso e a linha
/// "R$ atual de R$ alvo · Faltam R$ X · N dias". Metas pausadas ficam calmas
/// (esmaecidas, com selo "Pausada") — sem pressão. O botão "Ritmo" abre as
/// opções confortável/acelerar/pausar.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onTap,
    required this.onPace,
    this.paused = false,
  });

  final FinancialGoal goal;
  final VoidCallback? onTap;
  final VoidCallback? onPace;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final g = goal;
    final daysLeft = g.deadline?.daysUntil;
    final missing = (g.targetAmount - g.currentAmount).clamp(0, double.infinity);
    final done = g.progress >= 1;
    final card = AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(g.name,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (paused)
                StatusBadge('Pausada',
                    color: AppColors.amber, icon: Icons.pause_rounded)
              else
                StatusBadge(
                  g.progress.pct,
                  color: done ? AppColors.successSage : AppColors.brandLagoon,
                  icon: done
                      ? Icons.emoji_events_outlined
                      : Icons.flag_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          DynamicProgressBar(ratio: g.progress, height: 12),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: MoneyText(
                  done
                      ? '${g.currentAmount.brl} — meta alcançada 🎉'
                      : '${g.currentAmount.brl} de ${g.targetAmount.brl}'
                          ' · Faltam ${missing.brl}',
                  style: text.bodySmall,
                  maxLines: 1,
                ),
              ),
              if (daysLeft != null && !done && !paused) ...[
                const SizedBox(width: 8),
                Text(
                  daysLeft >= 0 ? '$daysLeft dias' : 'vencida',
                  style: text.labelSmall?.copyWith(
                      color: daysLeft >= 0 ? null : AppColors.red),
                ),
              ],
            ],
          ),
          if (onPace != null && !done) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onPace,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  foregroundColor: AppColors.brandLagoon,
                ),
                icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.speed_rounded,
                    size: 18),
                label: Text(paused ? 'Retomar' : 'Ritmo'),
              ),
            ),
          ],
        ],
      ),
    );
    // Meta pausada: esmaecida e calma, sem sumir.
    return paused ? Opacity(opacity: 0.6, child: card) : card;
  }
}

/// Linha de opção de ritmo na folha (ícone tingido + título + explicação).
/// Informativa quando [onTap] é nulo; acionável quando não.
class _PaceRow extends StatelessWidget {
  const _PaceRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: text.labelSmall),
            ],
          ),
        ),
        if (onTap != null)
          const Icon(Icons.chevron_right_rounded),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
    );
  }
}
