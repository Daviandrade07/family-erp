import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Acesso à assistente da família — a BÚSSOLA, símbolo próprio do Kinfin
/// (guia e direção). Botão compacto e VISÍVEL em qualquer tela/tema, sem
/// competir com o conteúdo.
class AssistantButton extends StatelessWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Assistente da família',
        child: Material(
          color: AppColors.brandLagoon.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => context.push('/chat'),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.explore_rounded,
                  size: 22, color: AppColors.brandLagoon),
            ),
          ),
        ),
      ),
    );
  }
}
