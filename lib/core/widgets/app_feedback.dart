import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Feedback unificado do app: um único padrão de aviso (snackbar flutuante,
/// arredondado, com ícone + cor semântica) que sobe suave. Substitui os avisos
/// soltos espalhados — sucesso é verde, erro é vermelho, informação é laguna.
class AppFeedback {
  const AppFeedback._();

  static void success(BuildContext context, String message) => _show(
      context, message, Icons.check_circle_rounded, AppColors.successSage);

  static void error(BuildContext context, String message) =>
      _show(context, message, Icons.error_outline_rounded, AppColors.red);

  static void info(BuildContext context, String message) =>
      _show(context, message, Icons.info_outline_rounded, AppColors.brandLagoon);

  static void _show(
      BuildContext context, String message, IconData icon, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        elevation: 3,
        duration: const Duration(seconds: 3),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: scheme.onInverseSurface)),
            ),
          ],
        ),
      ));
  }
}
