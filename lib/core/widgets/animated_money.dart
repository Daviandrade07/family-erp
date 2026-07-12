import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/theme_controller.dart';
import '../utils/formatters.dart';

/// Valor monetário que "conta" suavemente até o número ao aparecer — dá vida
/// aos resumos (saldo, totais) sem custo de performance. Respeita a redução de
/// movimento do sistema (mostra o valor final direto) e o **modo privacidade**
/// (mostra "••••" quando a pessoa escolhe ocultar).
class AnimatedMoney extends ConsumerWidget {
  const AnimatedMoney(
    this.value, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 650),
  });

  final double value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(hideAmountsProvider)) {
      return Text('R\$ ••••', style: style);
    }
    if (MediaQuery.of(context).disableAnimations) {
      return Text(value.brl, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(v.brl, style: style),
    );
  }
}
