import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_feedback.dart';
import 'auth_controller.dart';

/// Portão de **AAL2** para ações sensíveis (exportar dados, sair da família,
/// remover 2FA, etc.).
///
/// Regra: se a pessoa NÃO tem 2FA (TOTP verificado), não há o que exigir e a
/// ação segue — nunca criamos fricção falsa. Se tem 2FA mas a sessão ainda é
/// AAL1, pedimos o código do app autenticador uma vez para elevar a sessão.
/// A fonte da verdade é o nível REAL da sessão, nunca uma coluna gravável.
Future<bool> requireAal2(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final auth = ref.read(authControllerProvider.notifier);
  final hasTotp = await auth.hasVerifiedTotp();
  if (!hasTotp) return true; // 2FA não configurado → nada a exigir
  if (auth.hasAal2) return true; // sessão já elevada

  if (!context.mounted) return false;
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => _Aal2Dialog(reason: reason),
  );
  if (code == null || code.trim().length < 6) return false;

  try {
    await auth.elevateToAal2(code.trim());
    if (auth.hasAal2) return true;
    if (context.mounted) {
      AppFeedback.error(context, 'Código inválido. Tente de novo.');
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      AppFeedback.error(context, 'Código inválido ou expirado.');
    }
    return false;
  }
}

class _Aal2Dialog extends StatefulWidget {
  const _Aal2Dialog({required this.reason});
  final String reason;

  @override
  State<_Aal2Dialog> createState() => _Aal2DialogState();
}

class _Aal2DialogState extends State<_Aal2Dialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Confirme com o 2FA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Para ${widget.reason}, digite o código de 6 números do seu '
              'app autenticador.', style: text.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: text.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6),
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _code.text),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
