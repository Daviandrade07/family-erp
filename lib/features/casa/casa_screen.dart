import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/assistant_button.dart';
import '../../services/alerts_service.dart';
import '../settings/usage_mode_controller.dart';

/// Casa = o cluster da família: despensa, lista de compras e cardápio num só
/// lugar. Só aparece quando o usuário quer gerir a casa (níveis de uso).
class CasaScreen extends StatelessWidget {
  const CasaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Despensa', 'O que tem em casa e o que vence', Icons.kitchen_outlined,
          '/inventory'),
      ('Lista de compras', 'O que falta comprar',
          Icons.shopping_cart_outlined, '/shopping'),
      ('Cardápio', 'O que dá pra cozinhar na semana',
          Icons.restaurant_menu_outlined, '/meals'),
    ];
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Casa'),
        actions: const [AssistantButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (final (title, sub, icon, route) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: () => context.push(route),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.techBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: AppColors.techBlue),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(sub, style: text.labelSmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const _CasaDreamLink(),
        ]
            .animate(interval: 80.ms)
            .fadeIn(duration: 320.ms)
            .slideY(begin: 0.08, curve: Curves.easeOutCubic),
      ),
    );
  }
}

/// A ponte Casa → sonho: uma linha discreta que lembra que cuidar da casa
/// também é cuidar do plano da família. Usa os dados reais (itens perto de
/// vencer) quando existem; nunca repete o card do sonho da Home.
class _CasaDreamLink extends ConsumerWidget {
  const _CasaDreamLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const [];
    final expiring = alerts.where((a) => a.route == '/inventory').length;
    final solo = ref.watch(usageModeProvider) == UsageMode.solo;
    final donoDoSonho = solo ? 'do seu sonho' : 'do sonho da família';

    final line = expiring > 0
        ? 'Você tem $expiring ite${expiring > 1 ? 'ns' : 'm'} perto de vencer — '
            'usá-los evita desperdício, e desperdício evitado é sonho mais perto.'
        : 'Usar o que já tem em casa reduz gastos — sua casa também participa '
            '$donoDoSonho.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: AppColors.violet),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withValues(alpha: 0.75)),
            ),
          ),
        ],
      ),
    );
  }
}
