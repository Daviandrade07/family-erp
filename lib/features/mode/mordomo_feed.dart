import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kinfin_theme.dart';
import '../../services/mordomo/mordomo_service.dart';
import '../../services/mordomo/suggestion.dart';

Color _sevColor(SuggestionSeverity s) => switch (s) {
      SuggestionSeverity.urgent => KinFinColors.danger,
      SuggestionSeverity.attention => KinFinColors.attention,
      SuggestionSeverity.info => KinFinColors.info,
    };

String _sevLabel(SuggestionSeverity s) => switch (s) {
      SuggestionSeverity.urgent => 'Urgente',
      SuggestionSeverity.attention => 'Atenção',
      SuggestionSeverity.info => 'Info',
    };

IconData _sevIcon(SuggestionSeverity s) => switch (s) {
      SuggestionSeverity.urgent => Icons.priority_high_rounded,
      SuggestionSeverity.attention => Icons.trending_up_rounded,
      SuggestionSeverity.info => Icons.auto_awesome_rounded,
    };

/// Ícone em círculo com a cor da severidade em opacidade reduzida — a marca
/// visual de cada item do feed.
class _SeverityAvatar extends StatelessWidget {
  const _SeverityAvatar(this.severity, {this.size = 40});
  final SuggestionSeverity severity;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = _sevColor(severity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(_sevIcon(severity), size: size * 0.46, color: c),
    );
  }
}

/// "Próximos passos" — o feed do mordomo. Card-herói para o topo (mais grave),
/// linhas leves para o resto, e o estado vazio positivo. Nesta fase os cards
/// **só navegam** (não escrevem). Confiança filtra em 0.65, mas o número não
/// aparece — tom de convite, sem culpa.
class MordomoFeed extends ConsumerWidget {
  const MordomoFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(mordomoFeedProvider);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Próximos passos',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        feed.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (result) {
            if (result.isEmpty) return const _EmptyFeed();
            return Column(
              children: [
                _HeroCard(item: result.top.first),
                for (final s in result.top.skip(1)) _LightRow(item: s),
                if (result.moreCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text('+${result.moreCount} sugestão(ões) por ora',
                        style: text.labelSmall
                            ?.copyWith(color: KinFinColors.textMuted)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge(this.severity);
  final SuggestionSeverity severity;
  @override
  Widget build(BuildContext context) {
    final c = _sevColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_sevLabel(severity),
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

void _dismiss(WidgetRef ref, String id) =>
    ref.read(feedDismissedProvider.notifier).add(id);
void _snooze(WidgetRef ref, String id) => ref
    .read(feedSnoozedProvider.notifier)
    .update((s) => {...s, id});
void _open(BuildContext context, String? route) {
  if (route != null) context.push(route);
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.item});
  final Suggestion item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SeverityAvatar(item.severity, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(item.title,
                                style: text.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 8),
                          _SeverityBadge(item.severity),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(item.body,
                          style: text.bodyMedium?.copyWith(
                              color: KinFinColors.textMuted, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                    onPressed: () => _dismiss(ref, item.id),
                    child: const Text('Ignorar')),
                TextButton(
                    onPressed: () => _snooze(ref, item.id),
                    child: const Text('Agora não')),
                const Spacer(),
                FilledButton(
                    onPressed: () => _open(context, item.route),
                    child: Text(item.actionLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LightRow extends ConsumerWidget {
  const _LightRow({required this.item});
  final Suggestion item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _open(context, item.route),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _SeverityAvatar(item.severity),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (item.body.isNotEmpty)
                      Text(item.body,
                          style: text.labelSmall
                              ?.copyWith(color: KinFinColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Agora não',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: KinFinColors.textMuted,
                onPressed: () => _snooze(ref, item.id),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: KinFinColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: KinFinColors.positive.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: KinFinColors.positive),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tudo em dia',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text('Seus gastos estão no ritmo do mês.',
                      style: text.bodySmall
                          ?.copyWith(color: KinFinColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
