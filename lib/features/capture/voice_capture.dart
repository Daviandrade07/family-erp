import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../services/ai/audio_transcription_service.dart';
import '../../services/ai/recording_bytes.dart';
import '../../services/ai/write_safety.dart';

/// Estados da captura de voz (compartilhados por chat e Registro Rápido).
enum VoiceState { idle, preparing, recording, paused, transcribing }

typedef RecordingBytesReader = Future<Uint8List> Function(String path);
typedef VoiceCaptureFactory = VoiceCaptureController Function(
    TranscribeFn transcribe);

/// Controller da gravação de voz — UMA máquina de estados para o chat e o
/// Registro Rápido (P2.2), no lugar das duas cópias anteriores.
///
/// Regras de UX que ele garante:
/// - feedback imediato: ao tocar no mic o estado vira `preparing` na hora;
/// - vermelho/onda só enquanto grava; `paused` é neutro;
/// - NUNCA envia sozinho: [finish] só roda quando o usuário aciona enviar.
class VoiceCaptureController extends ChangeNotifier {
  VoiceCaptureController({
    required this.transcribe,
    RecordingBytesReader? readBytes,
  }) : _readBytes = readBytes ?? recordingBytes;

  final TranscribeFn transcribe;
  final RecordingBytesReader _readBytes;
  final _recorder = AudioRecorder();

  VoiceState state = VoiceState.idle;

  bool get isActive =>
      state == VoiceState.recording || state == VoiceState.paused;

  void _set(VoiceState s) {
    state = s;
    notifyListeners();
  }

  /// Inicia a gravação. Retorna uma mensagem humana de erro, ou null.
  Future<String?> begin() async {
    if (state != VoiceState.idle) return null;
    _set(VoiceState.preparing); // feedback < 1s: "Preparando…"
    try {
      if (!await _recorder.hasPermission()) {
        _set(VoiceState.idle);
        return 'Permita o uso do microfone para falar.';
      }
      var path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/vc_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
        path: path,
      );
      _set(VoiceState.recording);
      return null;
    } catch (e, st) {
      developer.log('voice begin failed',
          name: 'voice', error: e, stackTrace: st);
      _set(VoiceState.idle);
      return humanizeError(e);
    }
  }

  Future<void> togglePause() async {
    try {
      if (state == VoiceState.recording) {
        await _recorder.pause();
        _set(VoiceState.paused);
      } else if (state == VoiceState.paused) {
        await _recorder.resume();
        _set(VoiceState.recording);
      }
    } catch (e, st) {
      developer.log('voice pause failed',
          name: 'voice', error: e, stackTrace: st);
    }
  }

  /// Descarta a gravação sem transcrever nem enviar.
  Future<void> cancel() async {
    if (!isActive) return;
    try {
      await _recorder.stop();
    } catch (_) {}
    _set(VoiceState.idle);
  }

  /// Para a gravação e transcreve. Retorna (texto, erroHumano).
  /// Só é chamado por ação explícita do usuário (enviar).
  Future<(String?, String?)> finish() async {
    if (!isActive) return (null, null);
    _set(VoiceState.transcribing);
    try {
      final path = await _recorder.stop();
      if (path == null) throw Exception('Nada gravado.');
      final bytes = await _readBytes(path);
      final text = await transcribe(
        bytes,
        filename: kIsWeb ? 'audio.webm' : 'audio.m4a',
        contentType: kIsWeb ? 'audio/webm' : 'audio/mp4',
      );
      _set(VoiceState.idle);
      if (text.trim().isEmpty) {
        return (null, 'Não entendi o áudio. Tente falar de novo.');
      }
      return (text.trim(), null);
    } catch (e, st) {
      developer.log('voice finish failed',
          name: 'voice', error: e, stackTrace: st);
      _set(VoiceState.idle);
      return (null, humanizeError(e));
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}

/// Fábrica injetável: telas continuam usando o gravador de produção, e testes
/// podem trocar somente a leitura de bytes sem depender de arquivo ou microfone.
final voiceCaptureFactoryProvider = Provider<VoiceCaptureFactory>(
  (ref) => (transcribe) => VoiceCaptureController(transcribe: transcribe),
);

/// Indicador visual da captura: "Preparando… / Ouvindo… / Pausado /
/// Entendendo o áudio…", com barras animadas simples enquanto grava.
/// Respeita a redução de movimento do sistema (barras estáticas).
class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({super.key, required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final (String label, bool live) = switch (state) {
      VoiceState.preparing => ('Preparando…', false),
      VoiceState.recording => ('Ouvindo… fale agora', true),
      VoiceState.paused => ('Pausado — envie ou continue', false),
      VoiceState.transcribing => ('Entendendo o áudio…', false),
      VoiceState.idle => ('', false),
    };

    Widget bar(double height, int i) {
      final base = Container(
        width: 3,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: live ? AppColors.red : Theme.of(context).disabledColor,
          borderRadius: BorderRadius.circular(2),
        ),
      );
      if (!live || reduceMotion) return base;
      return base.animate(onPlay: (c) => c.repeat(reverse: true)).scaleY(
            begin: 0.35,
            end: 1,
            duration: 450.ms,
            delay: (i * 110).ms,
            curve: Curves.easeInOut,
          );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state == VoiceState.transcribing || state == VoiceState.preparing)
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, h) in const [8.0, 15.0, 11.0, 17.0].indexed)
              bar(h, i),
          ]),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: text.labelMedium?.copyWith(
              color: live ? AppColors.red : null,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
