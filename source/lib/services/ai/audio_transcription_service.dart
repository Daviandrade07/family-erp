import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/config/ai_config.dart';

/// Transcrição inteligente de áudio (voz → texto) via Whisper na Groq,
/// através do proxy (a chave fica no servidor). Entende fala com sotaque e
/// ruído e devolve em português.
class AudioTranscriptionService {
  static const _model = 'whisper-large-v3-turbo';

  Future<String> transcribe(
    Uint8List bytes, {
    String filename = 'audio.webm',
    String contentType = 'audio/webm',
  }) async {
    if (!AiConfig.available) {
      throw Exception('Entre na sua conta para usar o áudio.');
    }
    final uri = Uri.parse('${AiConfig.endpoint}/audio/transcriptions');
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(AiConfig.authHeaders())
      ..fields['model'] = _model
      ..fields['language'] = 'pt'
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ));

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception('Transcrição falhou (${resp.statusCode}).');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (json['text'] as String? ?? '').trim();
  }
}

final audioTranscriptionService = AudioTranscriptionService();
