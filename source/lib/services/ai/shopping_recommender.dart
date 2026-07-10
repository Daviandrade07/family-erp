import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// Price estimate of one shopping item at one market.
class MarketQuote {
  const MarketQuote({required this.item, required this.market, required this.price});

  final String item;
  final String market;
  final double price;
}

/// Final recommendation for the pending shopping list.
class ShoppingRecommendation {
  const ShoppingRecommendation({
    required this.strategy,
    required this.summary,
    required this.singleStoreName,
    required this.singleStoreTotal,
    required this.splitTotal,
    required this.splitPlan,
    required this.travelCostSingle,
    required this.travelCostSplit,
    required this.quotes,
  });

  /// 'single' or 'split'
  final String strategy;
  final String summary;
  final String singleStoreName;
  final double singleStoreTotal;
  final double splitTotal;

  /// market name → items to buy there
  final Map<String, List<MarketQuote>> splitPlan;
  final double travelCostSingle;
  final double travelCostSplit;
  final List<MarketQuote> quotes;

  double get savings =>
      (singleStoreTotal + travelCostSingle) - (splitTotal + travelCostSplit);
}

/// Recommendation engine: crosses pantry `price_history` with market
/// geolocation, prices the pending list per market, adds displacement cost
/// (distance × R$/km) and decides between one-stop shopping vs splitting.
class ShoppingRecommender {
  ShoppingRecommender(this._shopping, this._inventory, this._markets);

  final ShoppingRepository _shopping;
  final InventoryRepository _inventory;
  final MarketRepository _markets;

  /// Cost per km driven (fuel + wear), and fixed cost per extra stop (time).
  static const costPerKm = 1.20;
  static const costPerExtraStop = 6.0;

  /// Coordenadas padrão: centro de Indaiatuba-SP (os mercados parceiros do
  /// sistema são exclusivamente da cidade).
  Future<ShoppingRecommendation?> run({
    double userLat = -23.0904,
    double userLng = -47.2181,
  }) async {
    final pending = (await _shopping.all())
        .where((i) => !i.isBought)
        .toList();
    if (pending.isEmpty) return null;

    final inventory = await _inventory.all();
    final markets = await _markets.all();
    if (markets.isEmpty) return null;

    // --- 1. Quote every pending item at every market -------------------
    // Uses the latest known price per (product, market) from price_history;
    // markets without history for an item get the cross-market median +5%
    // (unknown-price penalty).
    final quotes = <MarketQuote>[];
    for (final item in pending) {
      final history = inventory
          .firstWhere(
            (inv) =>
                inv.productName.toLowerCase() == item.itemName.toLowerCase(),
            orElse: () => InventoryItem(
                familyId: item.familyId,
                productName: item.itemName,
                quantity: 0,
                minQuantity: 0),
          )
          .priceHistory;

      final latestByMarket = <String, PricePoint>{};
      for (final p in history) {
        final prev = latestByMarket[p.market];
        if (prev == null || p.date.isAfter(prev.date)) {
          latestByMarket[p.market] = p;
        }
      }

      final knownPrices = latestByMarket.values.map((p) => p.price).toList()
        ..sort();
      final median = knownPrices.isEmpty
          ? 10.0 // no data at all: neutral placeholder price
          : knownPrices[knownPrices.length ~/ 2];

      for (final m in markets) {
        final known = latestByMarket[m.name]?.price;
        quotes.add(MarketQuote(
          item: item.itemName,
          market: m.name,
          price: (known ?? median * 1.05) * item.quantity,
        ));
      }
    }

    // --- 2. Travel cost per market (haversine, round trip) -------------
    final travelCost = <String, double>{
      for (final m in markets)
        m.name: _haversineKm(userLat, userLng, m.lat, m.lng) * 2 * costPerKm,
    };

    // --- 3. Single-store option: cheapest basket + its travel ----------
    String bestSingle = markets.first.name;
    double bestSingleCost = double.infinity;
    for (final m in markets) {
      final basket = quotes
          .where((q) => q.market == m.name)
          .fold<double>(0, (s, q) => s + q.price);
      final total = basket + travelCost[m.name]!;
      if (total < bestSingleCost) {
        bestSingleCost = total;
        bestSingle = m.name;
      }
    }
    final singleBasket = quotes
        .where((q) => q.market == bestSingle)
        .fold<double>(0, (s, q) => s + q.price);

    // --- 4. Split option: each item at its cheapest market --------------
    final splitPlan = <String, List<MarketQuote>>{};
    for (final item in pending) {
      final itemQuotes =
          quotes.where((q) => q.item == item.itemName).toList()
            ..sort((a, b) => a.price.compareTo(b.price));
      final best = itemQuotes.first;
      splitPlan.putIfAbsent(best.market, () => []).add(best);
    }
    final splitBasket = splitPlan.values
        .expand((l) => l)
        .fold<double>(0, (s, q) => s + q.price);
    final splitTravel = splitPlan.keys
            .map((m) => travelCost[m]!)
            .fold<double>(0, (s, c) => s + c) +
        math.max(0, splitPlan.length - 1) * costPerExtraStop;

    // --- 5. Decision -----------------------------------------------------
    final singleTotal = singleBasket + travelCost[bestSingle]!;
    final splitTotal = splitBasket + splitTravel;
    final useSplit = splitTotal < singleTotal - 1.0 && splitPlan.length > 1;

    final diff = (singleTotal - splitTotal).abs();
    final summary = useSplit
        ? 'Dividir a lista entre ${splitPlan.keys.join(' e ')} economiza '
            'R\$ ${diff.toStringAsFixed(2)} mesmo somando o deslocamento extra.'
        : 'Comprar tudo no $bestSingle compensa: a economia de dividir a '
            'lista (R\$ ${(singleBasket - splitBasket).toStringAsFixed(2)}) '
            'não cobre o custo de deslocamento extra.';

    return ShoppingRecommendation(
      strategy: useSplit ? 'split' : 'single',
      summary: summary,
      singleStoreName: bestSingle,
      singleStoreTotal: singleBasket,
      splitTotal: splitBasket,
      splitPlan: splitPlan,
      travelCostSingle: travelCost[bestSingle]!,
      travelCostSplit: splitTravel,
      quotes: quotes,
    );
  }

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}

final shoppingRecommenderProvider = Provider(
  (ref) => ShoppingRecommender(
    ref.watch(shoppingRepositoryProvider),
    ref.watch(inventoryRepositoryProvider),
    ref.watch(marketRepositoryProvider),
  ),
);

final shoppingRecommendationProvider =
    FutureProvider.autoDispose<ShoppingRecommendation?>(
  (ref) => ref.watch(shoppingRecommenderProvider).run(),
);
