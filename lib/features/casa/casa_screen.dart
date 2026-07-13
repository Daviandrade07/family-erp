import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/kinfin_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/assistant_button.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/ai/ai_write_tick.dart';
import '../../services/alerts_service.dart';
import '../mode/mode_switch.dart';
import '../settings/usage_mode_controller.dart';

/// Despesas recentes disponíveis para dividir entre a família (mesma fonte real
/// já usada em Finanças — nada fabricado).
final _recentExpensesProvider = FutureProvider.autoDispose<List<Transaction>>((ref) {
  ref.watch(aiWriteTickProvider);
  return ref.watch(transactionRepositoryProvider).recentExpenses(days: 30);
});

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
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Casa'),
            SizedBox(width: 10),
            ModeChip(),
          ],
        ),
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
          const SizedBox(height: 4),
          Text('Família',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const _DivideExpenseCard(),
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

/// Entrada "Dividir despesa entre a família" — ADITIVA ao acesso que já existe
/// em Finanças (tocar numa transação recente). Como a `AllocateExpenseScreen`
/// precisa de UMA transação, aqui abrimos um seletor de despesas recentes reais
/// e, ao escolher, empurramos a mesma rota `/transactions/allocate` já usada.
class _DivideExpenseCard extends StatelessWidget {
  const _DivideExpenseCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => _showDivideExpensePicker(context),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KinFinColors.shared.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.groups_2_outlined, color: KinFinColors.shared),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dividir despesa entre a família',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('Escolha uma despesa recente para ratear entre todos',
                    style: text.labelSmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

/// Folha inferior que lista as despesas recentes reais. Ao tocar numa, navega
/// para a tela de alocação já existente (validação de 100% intacta).
Future<void> _showDivideExpensePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final text = Theme.of(context).textTheme;
        final expenses = ref.watch(_recentExpensesProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Qual despesa dividir?',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                expenses.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('Não foi possível carregar as despesas agora.',
                        style: text.bodyMedium),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                            'Nenhuma despesa recente para dividir. Registre um '
                            'gasto e ele aparece aqui.',
                            style: text.bodyMedium),
                      );
                    }
                    return Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final tx = list[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(tx.description ?? tx.category,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${tx.date.dayMonth} · ${tx.category}'),
                            trailing: Text('-${tx.amount.brl}',
                                style: text.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              context.push('/transactions/allocate', extra: tx);
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
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
