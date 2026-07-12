import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/write_confirmation_card.dart';
import '../../services/ai/audio_transcription_service.dart';
import '../../services/ai/confirmation_service.dart';
import '../chat/chat_controller.dart';
import 'voice_capture.dart';

/// Registro Rápido (P2 — "Agora registrar não dá trabalho").
///
/// Bottom-sheet que abre em cima de qualquer tela: a pessoa fala ou digita
/// ("gastei 80 no mercado", "boleto da escola vence sexta", "adiciona arroz
/// na lista") e a assistente entende, confirma quando há ambiguidade e grava.
/// Usa o MESMO cérebro do chat (mesmo controller, mesmas guardas, mesma
/// confirmação editável, mesmo tick de dados vivos) — nada de caminho novo de
/// gravação, nada de risco novo.
Future<void> showQuickCapture(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QuickCaptureSheet(),
  );
}

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet();

  @override
  ConsumerState<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<_QuickCaptureSheet> {
  final _input = TextEditingController();
  late final VoiceCaptureController _voice;

  /// Nº de mensagens no histórico quando o sheet enviou — a resposta da
  /// assistente é a primeira mensagem dela depois desse ponto.
  int? _sentAtCount;

  /// `ref` não pode ser usado no dispose (Riverpod); o notifier é capturado no
  /// initState e o estado "há pendência?" é espelhado a cada build.
  late final WriteConfirmationController _confirmations;
  bool _hasPending = false;

  @override
  void initState() {
    super.initState();
    _confirmations = ref.read(writeConfirmationControllerProvider.notifier);
    _voice = ref.read(voiceCaptureFactoryProvider)(
      ref.read(transcriptionProvider),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    // Se o sheet fechar com uma confirmação pendente, cancela — nada é gravado
    // sem resposta e o executor nunca fica aguardando para sempre. O resolve é
    // adiado para depois do frame: providers não podem ser modificados durante
    // o desmonte da árvore.
    if (_hasPending) {
      final confirmations = _confirmations;
      Future.microtask(() => confirmations.resolve(false));
    }
    _input.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty) return;
    final count = ref.read(chatControllerProvider).messages.length;
    setState(() => _sentAtCount = count);
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(msg);
  }

  Future<void> _micAction() async {
    switch (_voice.state) {
      case VoiceState.idle:
        final err = await _voice.begin();
        if (err != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(err)));
        }
      case VoiceState.recording:
      case VoiceState.paused:
        await _voice.togglePause();
      case VoiceState.preparing:
      case VoiceState.transcribing:
        break;
    }
  }

  /// Enviar: gravando/pausado → para, transcreve e envia numa ação só.
  /// Nunca envia sem esse toque explícito do usuário.
  Future<void> _sendAction() async {
    if (_voice.isActive) {
      final (text, err) = await _voice.finish();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: AppColors.red));
      }
      if (text != null) await _send(text);
      return;
    }
    if (_voice.state != VoiceState.idle) return;
    await _send();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final pending = ref.watch(writeConfirmationControllerProvider);
    _hasPending = pending != null; // espelho para o dispose (ver acima)
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // Resposta da assistente para O QUE este sheet enviou.
    String? reply;
    if (_sentAtCount != null &&
        !chat.thinking &&
        chat.messages.length > _sentAtCount! + 1) {
      final last = chat.messages.last;
      if (!last.fromUser) reply = last.text;
    }
    final busy = _sentAtCount != null && chat.thinking && pending == null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.explore_outlined,
                    size: 20, color: AppColors.neonGreen),
                const SizedBox(width: 8),
                Text('O que aconteceu?',
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Confirmação editável (a mesma trava do chat) ----
            if (pending != null)
              WriteConfirmationCard(key: ValueKey(pending), pending: pending)
            else if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (reply != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: AppColors.neonGreen),
                    const SizedBox(width: 8),
                    Expanded(child: Text(reply, style: text.bodyMedium)),
                  ],
                ),
              )
                  // "O Respiro": o feedback de sucesso surge com um leve
                  // crescer, dando a sensação de conclusão.
                  .animate()
                  .fadeIn(duration: 220.ms)
                  .scaleXY(begin: 0.96, curve: Curves.easeOut),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _sentAtCount = null),
                      child: const Text('Registrar outro'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              if (_voice.state == VoiceState.idle)
                TextField(
                  controller: _input,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'gastei 80 no mercado…',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Falar',
                          onPressed: _micAction,
                          icon: const Icon(Icons.mic_outlined),
                        ),
                        IconButton(
                          tooltip: 'Enviar',
                          onPressed: _sendAction,
                          icon: const Icon(Icons.send_rounded,
                              color: AppColors.neonGreen),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Gravando/pausado/transcrevendo: indicador vivo + cancelar +
                // pausar/retomar + ENVIAR (que para e envia numa ação só).
                Container(
                  height: 56,
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: RecordingIndicator(state: _voice.state)),
                      if (_voice.isActive) ...[
                        IconButton(
                          tooltip: 'Cancelar gravação',
                          visualDensity: VisualDensity.compact,
                          onPressed: _voice.cancel,
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: _voice.state == VoiceState.recording
                              ? 'Pausar'
                              : 'Continuar gravando',
                          visualDensity: VisualDensity.compact,
                          onPressed: _micAction,
                          icon: Icon(
                              _voice.state == VoiceState.recording
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 22),
                        ),
                        IconButton(
                          tooltip: 'Parar e enviar',
                          visualDensity: VisualDensity.compact,
                          onPressed: _sendAction,
                          icon: const Icon(Icons.send_rounded,
                              color: AppColors.neonGreen),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Também entendo: "paguei a luz" · "boleto da escola vence '
                'sexta" · "adiciona arroz na lista"',
                style: text.labelSmall
                    ?.copyWith(color: text.bodySmall?.color?.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/transactions/new');
                  },
                  child: Text('Prefiro o formulário completo',
                      style: text.labelSmall),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
