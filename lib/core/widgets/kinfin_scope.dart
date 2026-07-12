import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/kinfin_theme.dart';
import '../../features/settings/usage_mode_controller.dart';

/// Envelope das telas KinFin. Aplica o tema KinFin (acento por modo) e pinta um
/// fundo **opaco** dark-premium por baixo — é essa opacidade que **cobre a
/// aurora global do Casa Viva**, permitindo as duas identidades convivendo
/// durante a migração. Telas antigas (fora deste escopo) seguem intactas.
class KinFinScope extends ConsumerWidget {
  const KinFinScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSolo = ref.watch(usageModeProvider) == UsageMode.solo;
    return Theme(
      data: KinFinTheme.build(isSolo: isSolo),
      child: KinFinBackground(isSolo: isSolo, child: child),
    );
  }
}

/// Fundo near-black com um brilho radial sutil tingido pelo modo (roxo no Solo,
/// verde no Compartilhado). **Opaco** por natureza — cobre qualquer fundo atrás.
class KinFinBackground extends StatelessWidget {
  const KinFinBackground({super.key, required this.isSolo, required this.child});

  final bool isSolo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: KinFinColors.bg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.85, -1.0),
                radius: 1.1,
                colors: [KinFinColors.glow(isSolo), const Color(0x00000000)],
                stops: const [0.0, 0.55],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
