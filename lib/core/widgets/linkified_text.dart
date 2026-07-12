import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Texto com URLs http/https REAIS clicáveis (abre no navegador).
///
/// Regras de honestidade: só o que é URL de verdade vira link — nome de
/// mercado ou texto comum NUNCA ganham link inventado. Usado nas mensagens da
/// assistente (ofertas dos mercados trazem os sites das fontes).
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, this.style, this.onOpen});

  final String text;
  final TextStyle? style;

  /// Injetável para testes; padrão abre no navegador.
  final Future<void> Function(Uri uri)? onOpen;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final _urlRe = RegExp(r'https?://[^\s<>()\[\]{}"]+');

  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final open = widget.onOpen ??
        (u) async => launchUrl(u, mode: LaunchMode.externalApplication);
    await open(uri);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final m in _urlRe.allMatches(widget.text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, m.start)));
      }
      // Pontuação final de frase não faz parte da URL.
      var url = m.group(0)!;
      final trimmed = url.replaceAll(RegExp(r'[.,;:!?]+$'), '');
      final trailing = url.substring(trimmed.length);
      url = trimmed;

      final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        recognizer: recognizer,
        style: base.copyWith(
          color: AppColors.techBlue,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.techBlue,
        ),
      ));
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      cursor = m.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    // Sem URL nenhuma → texto simples (zero custo extra).
    if (spans.length == 1 && cursor == 0) {
      return Text(widget.text, style: widget.style);
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
