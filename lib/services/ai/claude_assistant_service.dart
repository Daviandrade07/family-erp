import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import 'assistant_tools.dart';
import 'chat_assistant_service.dart' show ChatMessage, ChatChartPoint;
import 'write_safety.dart';

/// Assistente do chat via API da Anthropic (Claude).
///
/// - Modelo: claude-opus-4-8 (thinking adaptativo) + prompt caching.
/// - Usa o system prompt e as ferramentas compartilhadas de
///   assistant_tools.dart — o function calling grava/consulta o Supabase pelo
///   cliente autenticado do usuário logado (RLS impõe user_id/family_id).
class ClaudeAssistantService {
  ClaudeAssistantService(this._ref);

  final Ref _ref;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-4-8';
  static const _maxToolIterations = 8;

  /// Histórico no formato da Messages API. Os blocos de conteúdo do
  /// assistente são reenviados intactos (incluindo thinking blocks), como a
  /// API exige em loops de tool use.
  final List<Map<String, dynamic>> _history = [];

  void reset() => _history.clear();

  Future<ChatMessage> send(String userText) async {
    if (_history.isEmpty) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      userText = '[Data atual: $today]\n$userText';
    }
    _history.add({'role': 'user', 'content': userText});

    List<ChatChartPoint>? chart;
    var chartIsPie = false;

    try {
      for (var i = 0; i < _maxToolIterations; i++) {
        final response = await _post();
        final content =
            (response['content'] as List).cast<Map<String, dynamic>>();
        final stopReason = response['stop_reason'] as String?;

        _history.add({'role': 'assistant', 'content': content});

        if (stopReason == 'refusal') {
          return const ChatMessage(
            fromUser: false,
            text: 'Não posso ajudar com esse assunto. Meu papel é cuidar das '
                'finanças da família e das compras de mercado em Indaiatuba. 😊',
          );
        }

        if (stopReason == 'pause_turn') {
          continue; // servidor pausou; reenviar histórico continua o turno
        }

        if (stopReason != 'tool_use') {
          final text = content
              .where((b) => b['type'] == 'text')
              .map((b) => b['text'] as String)
              .join('\n')
              .trim();
          return ChatMessage(
            fromUser: false,
            text: text.isEmpty ? 'Certo!' : text,
            chart: chart,
            chartIsPie: chartIsPie,
          );
        }

        // Executa todas as ferramentas pedidas e devolve os resultados em UMA
        // única mensagem de usuário (exigência da API p/ chamadas paralelas).
        final results = <Map<String, dynamic>>[];
        for (final block in content) {
          if (block['type'] != 'tool_use') continue;
          final name = block['name'] as String;
          final input = Map<String, dynamic>.from(block['input'] ?? const {});
          String resultText;
          var isError = false;

          if (name == 'render_chart') {
            chartIsPie = input['chart_type'] == 'pie';
            chart = ((input['points'] as List?) ?? const [])
                .map((p) => ChatChartPoint(
                      label: '${p['label']}',
                      value: (p['value'] as num).toDouble(),
                    ))
                .toList();
            resultText = 'Gráfico renderizado na interface do chat.';
          } else {
            try {
              resultText = await _ref
                  .read(assistantToolExecutorProvider)
                  .execute(name, input);
            } catch (e, st) {
              developer.log('tool execution failed: $name',
                  name: 'ai', error: e, stackTrace: st);
              resultText = jsonEncode({
                'erro': 'nao_foi_possivel_concluir',
                'orientacao': 'Peça desculpas em 1 frase e sugira tentar de '
                    'novo. Não cite detalhes técnicos.',
              });
              isError = true;
            }
          }

          results.add({
            'type': 'tool_result',
            'tool_use_id': block['id'],
            'content': resultText,
            if (isError) 'is_error': true,
          });
        }
        _history.add({'role': 'user', 'content': results});
      }

      return const ChatMessage(
        fromUser: false,
        text: 'A consulta ficou longa demais — pode reformular a pergunta?',
      );
    } catch (e, st) {
      developer.log('chat turn failed', name: 'ai', error: e, stackTrace: st);
      while (_history.isNotEmpty && _history.last['role'] != 'user') {
        _history.removeLast();
      }
      if (_history.isNotEmpty) _history.removeLast();
      return ChatMessage(fromUser: false, text: humanizeError(e));
    }
  }

  Future<Map<String, dynamic>> _post() async {
    final res = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': Env.anthropicApiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': _model,
            'max_tokens': 4096,
            'thinking': {'type': 'adaptive'},
            'system': [
              {
                'type': 'text',
                'text': assistantSystemPrompt,
                // Prompt estável em cache: ~90% mais barato nas mensagens
                // seguintes da conversa.
                'cache_control': {'type': 'ephemeral'},
              },
            ],
            'tools': [
              for (final tool in assistantTools)
                {
                  'name': tool['name'],
                  'description': tool['description'],
                  'input_schema': tool['parameters'],
                },
            ],
            'messages': _history,
          }),
        )
        .timeout(const Duration(minutes: 3));

    if (res.statusCode != 200) {
      final body = utf8.decode(res.bodyBytes);
      throw Exception('Claude API ${res.statusCode}: $body');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}

final claudeAssistantProvider =
    Provider((ref) => ClaudeAssistantService(ref));
