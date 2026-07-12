import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/theme_controller.dart';

/// Texto de valor em R$ que respeita o **modo privacidade**: quando a pessoa
/// escolhe ocultar (olhinho na barra), mostra "••••" no lugar do número.
///
/// Recebe a string JÁ formatada (ex.: `tx.amount.brl`, `'-${x.brl}'`), então
/// cada tela mantém sua lógica de sinal/prefixo — aqui só decidimos mostrar ou
/// mascarar. Assim o toggle cobre todos os valores de forma consistente.
class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.formatted, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String formatted;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideAmountsProvider);
    return Text(
      hidden ? 'R\$ ••••' : formatted,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}

/// Botão de olho para ligar/desligar o modo privacidade — vai nas barras das
/// telas financeiras (como em app de banco).
class PrivacyToggle extends ConsumerWidget {
  const PrivacyToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideAmountsProvider);
    return IconButton(
      tooltip: hidden ? 'Mostrar valores' : 'Ocultar valores',
      icon: Icon(
        hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
      ),
      onPressed: () => ref.read(hideAmountsProvider.notifier).toggle(),
    );
  }
}
