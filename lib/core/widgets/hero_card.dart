import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// Rótulo "eyebrow" da identidade Casa Viva: pequeno, em MENTA, maiúsculo e
/// espaçado, acima do título de um hero. Orienta sem competir.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.mint,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
      ),
    );
  }
}

/// Card-hero (bloco de destaque no topo das telas principais): gradiente sutil
/// que ecoa a aurora + eyebrow + conteúdo. Reaproveita o [AppCard] (que já
/// aceita `gradient`), só compõe o cabeçalho.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.eyebrow,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final String eyebrow;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      gradient: _heroGradient(context),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(eyebrow),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Gradiente do hero — teal→escuro→ameixa no dark (eco da aurora); no claro,
/// um véu de menta bem suave sobre o card.
Gradient _heroGradient(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF243447), Color(0xFF1E2536), Color(0xFF2C2444)],
      stops: [0.0, 0.55, 1.0],
    );
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.lightCard,
      AppColors.mint.withValues(alpha: 0.10),
    ],
  );
}
