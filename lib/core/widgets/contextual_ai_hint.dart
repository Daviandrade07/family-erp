import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/alerts_service.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// Consultor contextual DISCRETO: uma linha derivada dos dados reais (sem custo
/// de IA), dismissível por um toque que abre o chat já no contexto. É a IA
/// "onde você está" — nunca invasiva, no máximo 1 por tela.
class ContextualAiHint extends ConsumerWidget {
  const ContextualAiHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const [];
    final overdue =
        alerts.where((a) => a.severity == AlertSeverity.critico).length;
    final soon =
        alerts.where((a) => a.severity == AlertSeverity.atencao).length;

    String? line;
    if (overdue > 0) {
      line = '$overdue conta${overdue > 1 ? 's' : ''} vencida${overdue > 1 ? 's' : ''}. '
          'Quer que eu monte o plano de pagamento?';
    } else if (soon > 0) {
      line = '$soon conta${soon > 1 ? 's vencem' : ' vence'} em breve. '
          'Quer o plano de pagamento?';
    }
    if (line == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () => context.push('/chat'),
        child: Row(
          children: [
            const Icon(Icons.explore_outlined,
                size: 18, color: AppColors.neonGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(line,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
