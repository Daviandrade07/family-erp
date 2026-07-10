import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/config/ai_config.dart';
import 'assistant_tools.dart';
import 'chat_assistant_service.dart' show ChatMessage, ChatChartPoint;

/// Assistente do chat via API OpenAI-compatible.
///
/// Funciona com qualquer provedor que exponha `/chat/completions`:
/// - **Groq Cloud** (padrão): `AI_API_KEY=gsk_...`, modelo
///   `llama-3.3-70b-versatile` — plano gratuito, inferência rápida, sem
///   treinar com os dados enviados.
/// - **Ollama local**: `--dart-define=AI_BASE_URL=http://localhost:11434/v1
///   --dart-define=AI_MODEL=llama3.1 --dart-define=AI_API_KEY=ollama`.
///
/// Usa o mesmo system prompt e as mesmas ferramentas do agente Claude
/// (assistant_tools.dart) — o escopo estrito e o function calling no
/// Supabase são idênticos.
class OpenAiCompatibleAssistantService {
  OpenAiCompatibleAssistantService(this._ref);

  final Ref _ref;

  static const _maxToolIterations = 8;

  /// Histórico no formato chat-completions (inclui mensagens `tool`).
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
        final message =
            (response['choices'] as List).first['message'] as Map<String, dynamic>;
        _history.add(message);

        final toolCalls = (message['tool_calls'] as List?) ?? const [];
        if (toolCalls.isEmpty) {
          final text = (message['content'] as String? ?? '').trim();
          return ChatMessage(
            fromUser: false,
            text: text.isEmpty ? 'Certo!' : text,
            chart: chart,
            chartIsPie: chartIsPie,
          );
        }

        for (final call in toolCalls) {
          final function = call['function'] as Map<String, dynamic>;
          final name = function['name'] as String;
          // Alguns modelos mandam arguments como '"null"', '{}' ou vazio
          // quando a ferramenta não tem parâmetros.
          final rawArgs = function['arguments'];
          var input = <String, dynamic>{};
          if (rawArgs is String && rawArgs.isNotEmpty) {
            final decoded = jsonDecode(rawArgs);
            if (decoded is Map) {
              input = Map<String, dynamic>.from(decoded);
            }
          } else if (rawArgs is Map) {
            input = Map<String, dynamic>.from(rawArgs);
          }

          String resultText;
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
            } catch (e) {
              resultText = 'Erro ao executar $name: $e';
            }
          }

          _history.add({
            'role': 'tool',
            'tool_call_id': call['id'],
            'content': resultText,
          });
        }
      }

      return const ChatMessage(
        fromUser: false,
        text: 'A consulta ficou longa demais — pode reformular a pergunta?',
      );
    } catch (e) {
      // Remove o turno com falha para não corromper o histórico.
      while (_history.isNotEmpty && _history.last['role'] != 'user') {
        _history.removeLast();
      }
      if (_history.isNotEmpty) _history.removeLast();
      return ChatMessage(
        fromUser: false,
        text: 'Não consegui falar com a IA agora ($e). '
            'Verifique a conexão e a chave da API.',
      );
    }
  }

  /// Mantém o histórico curto para caber no limite de tokens/minuto do plano
  /// gratuito. Corta turnos antigos garantindo que o primeiro item mantido
  /// seja uma mensagem de usuário "normal" (nunca um resultado de ferramenta
  /// órfão, que a API rejeitaria).
  void _trimHistory() {
    const maxMessages = 12;
    if (_history.length <= maxMessages) return;
    var start = _history.length - maxMessages;
    while (start < _history.length) {
      final m = _history[start];
      if (m['role'] == 'user' && m['content'] is String) break;
      start++;
    }
    _history.removeRange(0, start);
  }

  Future<Map<String, dynamic>> _post() async {
    _trimHistory();

    // Até 3 tentativas: o plano gratuito da Groq limita tokens/minuto e o
    // 429 informa quanto esperar ("Please try again in Xs").
    for (var attempt = 0; ; attempt++) {
      final res = await http
          .post(
            Uri.parse('${AiConfig.endpoint}/chat/completions'),
            headers: {
              'content-type': 'application/json',
              ...AiConfig.authHeaders(),
            },
            body: jsonEncode({
              'model': Env.aiModel,
              'max_tokens': 1024,
              'temperature': 0.3,
              'messages': [
                {'role': 'system', 'content': assistantSystemPrompt},
                ..._history,
              ],
              'tools': [
                for (final tool in assistantTools)
                  {
                    'type': 'function',
                    'function': {
                      'name': tool['name'],
                      'description': tool['description'],
                      'parameters': tool['parameters'],
                    },
                  },
              ],
              'tool_choice': 'auto',
            }),
          )
          .timeout(const Duration(minutes: 2));

      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }

      final body = utf8.decode(res.bodyBytes);
      if (res.statusCode == 429 && attempt < 2) {
        final match =
            RegExp(r'try again in ([0-9.]+)s').firstMatch(body);
        final waitSeconds =
            double.tryParse(match?.group(1) ?? '') ?? (5.0 * (attempt + 1));
        await Future.delayed(
            Duration(milliseconds: ((waitSeconds + 1) * 1000).round()));
        continue;
      }
      if (res.statusCode == 429) {
        throw Exception(
            'O limite gratuito de uso por minuto foi atingido — aguarde '
            'alguns segundos e pergunte de novo.');
      }
      throw Exception('IA ${res.statusCode}: $body');
    }
  }
}

final openAiCompatibleAssistantProvider =
    Provider((ref) => OpenAiCompatibleAssistantService(ref));
