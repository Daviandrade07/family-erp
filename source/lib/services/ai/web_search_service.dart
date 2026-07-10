import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/ai_config.dart';

/// Resultado de uma busca web (promoções/preços em sites e redes dos mercados).
class WebSearchResult {
  const WebSearchResult({required this.answer, required this.sources});

  final String answer;
  final List<String> sources;

  bool get isEmpty => answer.trim().isEmpty && sources.isEmpty;
}

/// Busca informações na internet (sites oficiais, Instagram e Google) usando o
/// modelo agêntico da Groq `groq/compound-mini`, que tem web search embutido.
///
/// Usado para trazer promoções/ofertas/preços atuais dos mercados de
/// Indaiatuba — dados que não estão no banco local. Sempre retorna as fontes
/// (URLs) encontradas para citação transparente.
class WebSearchService {
  static const _model = 'groq/compound-mini';

  /// Faz uma busca web com foco em mercados/promoções de Indaiatuba-SP.
  Future<WebSearchResult> searchMarketOffers({
    required String query,
  }) async {
    if (!AiConfig.available) {
      return const WebSearchResult(
        answer: 'Busca na internet indisponível: entre na sua conta para '
            'habilitar a busca web de promoções.',
        sources: [],
      );
    }

    final prompt = '''
Você é um pesquisador de ofertas de supermercado. Faça uma busca na web
(sites oficiais, Instagram das lojas e Google) sobre: $query

Contexto: cidade de INDAIATUBA-SP e região (Salto, Itu, Elias Fausto).
Mercados relevantes: GoodBom, Sumerbol, Pague Menos, Covabra, Cato, Atacadão,
Tenda, Assaí, Paulistão, Carrefour.

Regras:
- Priorize encartes/ofertas da semana e posts recentes de promoção.
- Traga produtos e preços que encontrar, sempre com a fonte (URL).
- Se não encontrar preços específicos, informe honestamente e indique os
  canais oficiais (site/Instagram) onde o usuário pode conferir.
- Responda em português do Brasil, curto e organizado.
''';

    try {
      final res = await http
          .post(
            Uri.parse('${AiConfig.endpoint}/chat/completions'),
            headers: {
              'content-type': 'application/json',
              ...AiConfig.authHeaders(),
            },
            body: jsonEncode({
              'model': _model,
              'temperature': 0.2,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) {
        return WebSearchResult(
          answer: 'Não consegui buscar na internet agora (${res.statusCode}).',
          sources: const [],
        );
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final message =
          (json['choices'] as List).first['message'] as Map<String, dynamic>;
      final answer = (message['content'] as String? ?? '').trim();

      // Extrai as URLs das buscas executadas pelo modelo agêntico.
      final sources = <String>{};
      final executed = message['executed_tools'] as List? ?? const [];
      for (final tool in executed) {
        final output = (tool as Map)['output']?.toString() ?? '';
        for (final match
            in RegExp(r'https?://[^\s"\)]+').allMatches(output)) {
          sources.add(match.group(0)!);
        }
      }

      return WebSearchResult(answer: answer, sources: sources.take(6).toList());
    } catch (e) {
      return WebSearchResult(
        answer: 'Falha na busca web: $e',
        sources: const [],
      );
    }
  }
}

final webSearchService = WebSearchService();
