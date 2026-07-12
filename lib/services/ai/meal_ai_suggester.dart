import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/config/ai_config.dart';
import '../../data/repositories/repositories.dart';
import 'meal_suggester.dart';

/// Um prato sugerido pela IA a partir da despensa real.
class DishSuggestion {
  const DishSuggestion({
    required this.name,
    required this.have,
    required this.missing,
    required this.usesExpiring,
  });

  final String name;

  /// Ingredientes que a família já tem na despensa.
  final List<String> have;

  /// Poucos itens que faltam comprar.
  final List<String> missing;

  /// Usa algum ingrediente que está perto do vencimento.
  final bool usesExpiring;

  factory DishSuggestion.fromJson(Map<String, dynamic> j) => DishSuggestion(
        name: (j['nome'] ?? j['name'] ?? 'Prato').toString(),
        have: ((j['tem'] ?? j['have'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        missing: ((j['falta'] ?? j['missing'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        usesExpiring: j['usa_vencendo'] == true || j['uses_expiring'] == true,
      );
}

/// Sugere pratos que dá pra fazer com o que há na despensa, usando o modelo
/// de IA (Groq). Prioriza itens perto do vencimento para evitar desperdício.
/// Sem chave de IA, cai no [MealSuggester] baseado em regras.
class MealAiSuggester {
  MealAiSuggester(this._ref);

  final Ref _ref;

  Future<List<DishSuggestion>> suggest() async {
    final inventory = await _ref.read(inventoryRepositoryProvider).all();
    final available =
        inventory.where((i) => i.quantity > 0).toList();
    if (available.isEmpty) return const [];

    if (!AiConfig.available) {
      // Fallback: usa o motor de regras (cardápio semanal) e extrai pratos.
      final menu = await _ref.read(mealSuggesterProvider).suggestWeek();
      final dishes = <String>{};
      for (final entry in menu.entries) {
        if (entry.key.startsWith('_')) continue;
        final day = entry.value as Map;
        for (final meal in day.values) {
          dishes.add(meal.toString());
        }
      }
      return dishes
          .take(8)
          .map((d) => DishSuggestion(
              name: d, have: const [], missing: const [], usesExpiring: false))
          .toList();
    }

    final despensa = available.map((i) {
      final days = i.daysToExpire;
      final flag = (days != null && days <= 7) ? ' ⚠(vence em ${days}d)' : '';
      return '- ${i.productName} '
          '(${i.quantity.toStringAsFixed(i.quantity % 1 == 0 ? 0 : 1)} '
          '${i.unit})$flag';
    }).join('\n');

    final prompt = '''
Você é um assistente de cozinha econômica brasileira. Com base SÓ nos
ingredientes da despensa abaixo, sugira de 5 a 8 pratos simples e do dia a dia
que dá pra fazer em casa. Priorize os itens marcados com ⚠ (perto do
vencimento) para evitar desperdício.

Para cada prato: use principalmente o que a família já tem e liste no máximo
2-3 itens comuns que faltam comprar (sal, óleo, cebola etc. contam como
"faltando" só se não estiverem na lista).

DESPENSA:
$despensa

Responda APENAS com JSON válido, sem texto antes ou depois, no formato:
{"pratos":[{"nome":"...","tem":["item1","item2"],"falta":["item3"],"usa_vencendo":true}]}
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
              'model': Env.aiModel,
              'temperature': 0.5,
              'max_tokens': 1024,
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        throw Exception('IA ${res.statusCode}');
      }
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final content =
          (json['choices'] as List).first['message']['content'] as String;
      final parsed = _extractJson(content);
      final pratos = (parsed['pratos'] ?? parsed['dishes'] ?? const []) as List;
      return pratos
          .map((p) => DishSuggestion.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    } catch (_) {
      // Em falha, degrada para o motor de regras.
      final menu = await _ref.read(mealSuggesterProvider).suggestWeek();
      final dishes = <String>{};
      for (final entry in menu.entries) {
        if (entry.key.startsWith('_')) continue;
        for (final meal in (entry.value as Map).values) {
          dishes.add(meal.toString());
        }
      }
      return dishes
          .take(8)
          .map((d) => DishSuggestion(
              name: d, have: const [], missing: const [], usesExpiring: false))
          .toList();
    }
  }

  /// Extrai o primeiro objeto JSON do texto (modelos às vezes envolvem em prosa).
  Map<String, dynamic> _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return const {};
    return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
  }
}

final mealAiSuggesterProvider = Provider((ref) => MealAiSuggester(ref));

/// Carrega as sugestões sob demanda (recarregável).
final dishSuggestionsProvider =
    FutureProvider.autoDispose<List<DishSuggestion>>(
        (ref) => ref.watch(mealAiSuggesterProvider).suggest());
