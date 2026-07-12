import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fundo da identidade "Casa Viva": ink profundo com dois brilhos radiais
/// (aurora) — teal no topo-esquerda e ameixa embaixo-direita. Fica ATRÁS de
/// todas as telas (os Scaffolds são transparentes), dando profundidade sem
/// competir com o conteúdo. No tema claro, um fundo calmo e sólido.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) {
      return ColoredBox(color: AppColors.lightBg, child: child);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.darkBg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Brilho teal — topo-esquerda.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.7, -1.0),
                radius: 1.1,
                colors: [Color(0x66284C63), Color(0x00284C63)],
                stops: [0.0, 0.55],
              ),
            ),
          ),
          // Brilho ameixa — embaixo-direita.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.9, 0.95),
                radius: 1.0,
                colors: [Color(0x59362A54), Color(0x00362A54)],
                stops: [0.0, 0.5],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
