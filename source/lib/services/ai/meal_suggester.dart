import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';

/// Weekly menu assistant: builds a 7-day lunch/dinner plan prioritizing
/// pantry items that are expiring soon or overstocked, minimizing waste.
class MealSuggester {
  MealSuggester(this._inventory);

  final InventoryRepository _inventory;

  /// Recipe → required base ingredients (matched loosely against the pantry).
  static const _recipes = <String, List<String>>{
    'Arroz, feijão e frango grelhado': ['arroz', 'feijão', 'frango'],
    'Macarrão ao molho de tomate': ['macarrão', 'tomate'],
    'Omelete com queijo e salada': ['ovo', 'queijo', 'tomate'],
    'Risoto simples de legumes': ['arroz', 'cenoura', 'cebola'],
    'Frango ao curry com arroz': ['frango', 'arroz'],
    'Panqueca de carne moída': ['farinha', 'carne', 'leite'],
    'Sopa de legumes': ['batata', 'cenoura', 'cebola'],
    'Escondidinho de frango': ['batata', 'frango', 'queijo'],
    'Salada completa com ovos': ['alface', 'ovo', 'tomate'],
    'Strogonoff de frango': ['frango', 'creme', 'arroz'],
    'Torta de liquidificador': ['farinha', 'ovo', 'leite'],
    'Feijoada rápida': ['feijão', 'linguiça', 'arroz'],
    'Peixe assado com legumes': ['peixe', 'batata'],
    'Lasanha de queijo': ['massa', 'queijo', 'molho'],
  };

  static const _days = [
    'monday', 'tuesday', 'wednesday', 'thursday',
    'friday', 'saturday', 'sunday',
  ];

  Future<Map<String, dynamic>> suggestWeek() async {
    final pantry = await _inventory.all();

    // Score each recipe by pantry coverage; ingredients close to expiring
    // are worth more (use them first).
    double score(List<String> ingredients) {
      var s = 0.0;
      for (final ing in ingredients) {
        final match = pantry.where((p) =>
            p.quantity > 0 &&
            p.productName.toLowerCase().contains(ing));
        if (match.isEmpty) continue;
        final item = match.first;
        s += 1.0;
        final days = item.daysToExpire;
        if (days != null && days >= 0 && days <= 7) s += 2.0;
        if (item.quantity > item.minQuantity * 3) s += 0.5;
      }
      return s / ingredients.length;
    }

    final ranked = _recipes.entries.toList()
      ..sort((a, b) => score(b.value).compareTo(score(a.value)));

    // Fill 7 days × 2 meals, cycling through best-ranked recipes without
    // repeating the same dish on consecutive slots.
    final menu = <String, dynamic>{};
    var idx = 0;
    for (final day in _days) {
      final lunch = ranked[idx % ranked.length].key;
      final dinner = ranked[(idx + ranked.length ~/ 2) % ranked.length].key;
      menu[day] = {'lunch': lunch, 'dinner': dinner};
      idx++;
    }

    // Ingredients missing from the pantry across the chosen menu.
    final chosen = <String>{};
    for (final day in menu.values) {
      for (final meal in (day as Map).values) {
        chosen.addAll(_recipes[meal] ?? const []);
      }
    }
    final missing = chosen
        .where((ing) => !pantry.any((p) =>
            p.quantity > 0 && p.productName.toLowerCase().contains(ing)))
        .toList();

    menu['_missing_ingredients'] = missing;
    return menu;
  }
}

final mealSuggesterProvider =
    Provider((ref) => MealSuggester(ref.watch(inventoryRepositoryProvider)));
