import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/economy_tips.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/assistant_button.dart';
import '../../core/widgets/money_text.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../../services/alerts_service.dart';
import '../../services/dream_outlook_service.dart';
import '../../services/insights_engine.dart';
import '../capture/quick_capture_sheet.dart';
import '../auth/auth_controller.dart';
import '../settings/simple_mode_controller.dart';
import 'simple_home_screen.dart';

final weekSummaryProvider = FutureProvider.autoDispose<WeekSummary>((ref) {
  ref.watch(aiWriteTickProvider); // dados vivos
  return ref.watch(analyticsRepositoryProvider).weekSummary();
});

/// Home dos 5 segundos: conta uma história, de cima pra baixo —
/// 1) como a família está hoje · 2) qual é o próximo passo ·
/// 3) como isso aproxima o sonho · 4) um sinal de progresso.
/// Cada card responde uma pergunta e é lido em até 3 segundos. Números brutos
/// (KPIs) vivem em Análises; a lista de lembretes vive no sino.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Pop-up com UMA dica de economia por abertura do app (ciclo de 100
    // dicas embaralhadas, sem repetição até esgotar).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => EconomyTipPopup.maybeShow(context));
  }

  @override
  Widget build(BuildContext context) {
    // Modo simples (opcional): substitui o início por poucos botões grandes.
    if (ref.watch(simpleModeProvider)) {
      return const SimpleHomeScreen();
    }

    final profile = ref.watch(authControllerProvider).profile;
    final alerts = ref.watch(alertsProvider);

    Future<void> refresh() async {
      ref.invalidate(weekSummaryProvider);
      ref.invalidate(alertsProvider);
      ref.invalidate(spendingAllowanceProvider);
      ref.invalidate(dreamOutlookProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, ${profile?.name.split(' ').first ?? ''}'),
            Text(
              DateTime.now().monthYear,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          const PrivacyToggle(),
          const AssistantButton(),
          IconButton(
            tooltip: 'Lembretes',
            icon: Badge(
              isLabelVisible: alerts.valueOrNull?.isNotEmpty ?? false,
              label: Text('${alerts.valueOrNull?.length ?? ''}'),
              backgroundColor: AppColors.red,
              child: const Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () => _showAlertsSheet(context, ref),
          ),
        ],
      ),
      // Registro Rápido (P2): a única ação primária da Home — falar/digitar
      // e pronto, sem formulário e sem trocar de tela.
      floatingActionButton: (profile?.canWrite ?? false)
          ? FloatingActionButton(
              onPressed: () => showQuickCapture(context),
              backgroundColor: AppColors.brandCoral,
              foregroundColor: const Color(0xFF3A1611),
              tooltip: 'Registrar',
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          // Entrada em cascata: os cards surgem em sequência ao abrir a tela —
          // dá vida e sensação premium, em qualquer estado (vazio ou cheio).
          children: [
            const _TodayCard(),
            const SizedBox(height: 12),
            const _NextStepCard(),
            const SizedBox(height: 12),
            const _DreamCard(),
            const SizedBox(height: 12),
            const _ProgressCard(),
            const SizedBox(height: 20),
            const _MonthStoryCard(),
          ]
              .animate(interval: 70.ms)
              .fadeIn(duration: 320.ms)
              .slideY(begin: 0.08, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  void _showAlertsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (context, ref, __) {
          final alerts = ref.watch(alertsProvider);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (context, controller) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded,
                          color: AppColors.amber),
                      const SizedBox(width: 8),
                      Text('Lembretes',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: alerts.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('$e'),
                      data: (list) => list.isEmpty
                          ? const EmptyState(
                              icon: Icons.check_circle_outline,
                              title: 'Tudo em dia!',
                              subtitle:
                                  'Nenhuma conta vencendo, comida estragando '
                                  'ou estoque baixo agora.')
                          : ListView(
                              controller: controller,
                              children: [
                                for (final a in list) _AlertTile(alert: a),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// BEAT 1 — "Hoje": comunica tranquilidade antes de dinheiro. A cor e a frase
/// dizem, numa olhada, se a família pode respirar; o valor vem depois, discreto.
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowance = ref.watch(spendingAllowanceProvider);
    final text = Theme.of(context).textTheme;

    return allowance.when(
      loading: () => const SizedBox(
          height: 92, child: LoadingSkeleton(itemCount: 1, itemHeight: 92)),
      error: (_, __) => const SizedBox.shrink(),
      data: (a) {
        final (Color color, IconData icon, String feeling, String money) =
            switch (a.status) {
          AllowanceStatus.semDados => (
              Theme.of(context).colorScheme.outline,
              Icons.spa_rounded,
              'Vamos começar com calma.',
              'Registre um movimento para eu entender o ritmo da casa.'
            ),
          AllowanceStatus.verde => (
              AppColors.neonGreen,
              Icons.check_circle_rounded,
              'Você pode respirar tranquilo hoje.',
              'Dá pra gastar até ${a.perDay.brl} sem apertar.'
            ),
          AllowanceStatus.amarelo => (
              AppColors.amber,
              Icons.info_rounded,
              'Dá pra seguir o dia com tranquilidade.',
              'Tente ficar por volta de ${a.perDay.brl} hoje.'
            ),
          AllowanceStatus.vermelho => (
              AppColors.red,
              Icons.warning_amber_rounded,
              'Hoje pede um pouquinho de cuidado.',
              a.perDay <= 0
                  ? 'O mês já está no limite — segure o que der.'
                  : 'Você já passou do ritmo ideal de hoje.'
            ),
        };
        // Card neutro e calmo: a cor aparece só num ícone pequeno de status —
        // nada de card vermelho competindo com o "Próximo passo".
        return AppCard(
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hoje',
                        style: text.labelSmall?.copyWith(
                            color: text.bodySmall?.color?.withValues(alpha: 0.7))),
                    const SizedBox(height: 2),
                    Text(feeling,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(money,
                        style: text.labelSmall?.copyWith(
                            color: text.bodySmall?.color?.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// BEAT 2 — "Próximo passo": UMA recomendação prioritária a partir dos sinais
/// que já existem (contas, validade, estoque). Determinístico, sem IA. Toque
/// leva direto à ação para quem quer ser guiado; glanceável para quem se
/// organiza sozinho.
class _NextStepCard extends ConsumerWidget {
  const _NextStepCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final text = Theme.of(context).textTheme;
    return alerts.when(
      loading: () => const SizedBox(
          height: 84, child: LoadingSkeleton(itemCount: 1, itemHeight: 84)),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final top = list.isEmpty ? null : list.first;
        final color = top?.color ?? AppColors.neonGreen;
        final icon = top?.icon ?? Icons.verified_rounded;
        final title = top?.title ?? 'Tudo em dia por aqui 🎉';
        final subtitle = top?.subtitle ??
            'Nada pendente agora. Aproveite o dia com tranquilidade.';
        // Herói da Home: tratamento especial permitido a UM card por tela —
        // tint sólido suave, sem gradiente (Design System).
        return AppCard(
          onTap: top?.route == null ? null : () => context.push(top!.route!),
          color: color.withValues(alpha: 0.08),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Próximo passo',
                        style: text.labelSmall?.copyWith(
                            color: text.bodySmall?.color?.withValues(alpha: 0.7))),
                    const SizedBox(height: 2),
                    Text(title,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(subtitle,
                        style: text.labelSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (top?.route != null) const Icon(Icons.chevron_right_rounded),
            ],
          ),
        );
      },
    );
  }
}

/// BEAT 3 — "Seu sonho": mostra como o ritmo atual aproxima o objetivo
/// principal da família, com esperança e proximidade (não só um percentual).
/// Toque leva aos objetivos.
class _DreamCard extends ConsumerWidget {
  const _DreamCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlook = ref.watch(dreamOutlookProvider);
    final text = Theme.of(context).textTheme;
    const accent = AppColors.violet;

    return outlook.when(
      loading: () => const SizedBox(
          height: 110, child: LoadingSkeleton(itemCount: 1, itemHeight: 110)),
      error: (_, __) => const SizedBox.shrink(),
      data: (d) {
        return AppCard(
          onTap: () => context.push('/goals'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.star_rounded, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Seu sonho',
                            style: text.labelSmall?.copyWith(
                                color:
                                    text.bodySmall?.color?.withValues(alpha: 0.7))),
                        if (d.hasGoal)
                          Text(d.goal!.name,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (d.hasGoal) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: d.progress,
                    minHeight: 8,
                    backgroundColor: accent.withValues(alpha: 0.14),
                    valueColor: const AlwaysStoppedAnimation(accent),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(d.headline,
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(d.subline, style: text.labelSmall),
            ],
          ),
        );
      },
    );
  }
}

/// BEAT 4 — "Seu progresso": um único sinal de avanço da semana, sempre
/// honesto e para a frente — nunca mostra um número ruim.
class _ProgressCard extends ConsumerWidget {
  const _ProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(weekSummaryProvider);
    final text = Theme.of(context).textTheme;

    return summary.when(
      loading: () => const SizedBox(
          height: 80, child: LoadingSkeleton(itemCount: 1, itemHeight: 80)),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        if (s.isEmpty) return const SizedBox.shrink();
        final (IconData icon, String line) = _progressLine(s);
        return AppCard(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.neonGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Seu progresso',
                        style: text.labelSmall?.copyWith(
                            color: text.bodySmall?.color?.withValues(alpha: 0.7))),
                    const SizedBox(height: 2),
                    Text(line,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  (IconData, String) _progressLine(WeekSummary s) {
    if (s.balance > 0) {
      return (
        Icons.savings_rounded,
        'Essa semana você guardou ${s.balance.brl}. Continue assim! 👏'
      );
    }
    final change = s.expenseChange;
    if (change != null && change < -0.05) {
      return (
        Icons.trending_down_rounded,
        'Você gastou ${change.abs().pct} menos que a semana passada. Mandou bem! 🎉'
      );
    }
    // Semana neutra/apertada: nada de número negativo — só o avanço.
    return (
      Icons.eco_rounded,
      'Cada dia organizado te deixa mais perto dos seus planos. 🌱'
    );
  }
}

/// Resumo mensal humano: usa o motor determinístico já existente, portanto não
/// inventa justificativas nem depende de uma conversa com IA para ser útil.
class _MonthStoryCard extends ConsumerWidget {
  const _MonthStoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final story = ref.watch(monthStoryProvider);
    final text = Theme.of(context).textTheme;
    return story.when(
      loading: () => const SizedBox(
          height: 118, child: LoadingSkeleton(itemCount: 1, itemHeight: 118)),
      error: (_, __) => const SizedBox.shrink(),
      data: (value) {
        final (color, icon, label) = switch (value.mood) {
          StoryMood.tranquilo => (
              AppColors.successSage,
              Icons.sentiment_satisfied_rounded,
              'Resumo do mês'
            ),
          StoryMood.atencao => (
              AppColors.amber,
              Icons.tips_and_updates_rounded,
              'Resumo do mês'
            ),
          StoryMood.cuidado => (
              AppColors.brandCoral,
              Icons.route_rounded,
              'Resumo do mês'
            ),
        };
        return AppCard(
          onTap: () => context.push('/analytics'),
          color: color.withValues(alpha: 0.08),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: text.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 12),
              Text(value.shouldIWorry,
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(value.nextStep,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium),
            ],
          ),
        );
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final AppAlert alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: alert.route == null ? null : () => context.push(alert.route!),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: alert.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(alert.icon, size: 18, color: alert.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(alert.subtitle,
                      style: text.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (alert.route != null)
              const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
