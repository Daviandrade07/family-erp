import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/usage_mode_controller.dart';

/// Chave Solo/Compartilhado — o coração do KinFin. Proeminente (não escondida em
/// Ajustes). O lado ativo usa o **primário do tema** (que no KinFinScope é o
/// acento do modo: roxo no Solo, verde no Compartilhado), então **a cor
/// comunica o modo** sem o usuário precisar ler. Ao trocar, o `usageModeProvider`
/// muda → o `KinFinScope` recolore a tela toda na hora.
class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(usageModeProvider);
    final scheme = Theme.of(context).colorScheme;

    Widget seg(UsageMode m, IconData icon, String label) {
      final active = mode == m;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(usageModeProvider.notifier).set(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: active ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color:
                          active ? scheme.onPrimary : scheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          seg(UsageMode.solo, Icons.person_outline_rounded, 'Solo'),
          seg(UsageMode.grupo, Icons.groups_2_outlined, 'Compartilhado'),
        ],
      ),
    );
  }
}
