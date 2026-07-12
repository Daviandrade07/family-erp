import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';

/// One line item extracted from a receipt.
class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final double quantity;
  final double unitPrice;

  double get total => quantity * unitPrice;
}

/// Structured result of scanning a fiscal receipt (NFC-e).
class ReceiptData {
  const ReceiptData({
    required this.merchantName,
    required this.cnpj,
    required this.date,
    required this.items,
  });

  final String merchantName;
  final String cnpj;
  final DateTime date;
  final List<ReceiptItem> items;

  double get total => items.fold(0, (s, i) => s + i.total);
}

/// Contract for receipt OCR. Swap [MockOcrService] for a real implementation
/// (Google ML Kit, AWS Textract, SEFAZ QR-code lookup) without touching the UI.
abstract class OcrService {
  Future<ReceiptData> scanReceipt(Uint8List imageBytes);
}

/// Deterministic mock: simulates processing latency and returns a realistic
/// Brazilian grocery receipt. Seeded by image bytes so the same photo always
/// yields the same receipt.
class MockOcrService implements OcrService {
  // Mercados de Indaiatuba-SP — mesmos nomes da tabela `markets`, para que
  // o histórico de preços alimentado pelo OCR case com o recomendador.
  static const _merchants = [
    ('GoodBom Indaiatuba', '61.585.865/0001-01'),
    ('Sumerbol Supermercados', '52.276.719/0001-02'),
    ('Pague Menos Indaiatuba', '55.789.011/0001-03'),
    ('Covabra Supermercados', '46.395.463/0001-04'),
  ];

  static const _catalog = [
    ('Arroz 5kg', 24.90),
    ('Feijão carioca 1kg', 8.49),
    ('Leite integral 1L', 4.99),
    ('Café torrado 500g', 18.90),
    ('Óleo de soja 900ml', 7.29),
    ('Açúcar refinado 1kg', 4.19),
    ('Macarrão espaguete 500g', 4.79),
    ('Papel higiênico 12un', 21.90),
    ('Detergente 500ml', 2.89),
    ('Frango congelado 1kg', 12.90),
    ('Banana prata kg', 6.49),
    ('Tomate kg', 8.99),
    ('Queijo mussarela 300g', 14.50),
    ('Sabonete 90g', 2.49),
  ];

  @override
  Future<ReceiptData> scanReceipt(Uint8List imageBytes) async {
    await Future.delayed(const Duration(milliseconds: 1400));

    final seed = imageBytes.isEmpty
        ? DateTime.now().millisecondsSinceEpoch
        : imageBytes.fold<int>(17, (h, b) => h * 31 + b) & 0x7fffffff;
    final rng = Random(seed);

    final merchant = _merchants[rng.nextInt(_merchants.length)];
    final itemCount = 4 + rng.nextInt(6);
    final picked = List.of(_catalog)..shuffle(rng);

    final items = picked.take(itemCount).map((p) {
      final qty = p.$1.contains('kg') && !p.$1.contains('1kg')
          ? (0.5 + rng.nextDouble() * 2).toStringAsFixed(3)
          : (1 + rng.nextInt(3)).toString();
      // ±8% price noise, like real market fluctuation
      final price = p.$2 * (0.92 + rng.nextDouble() * 0.16);
      return ReceiptItem(
        name: p.$1,
        quantity: double.parse(qty),
        unitPrice: double.parse(price.toStringAsFixed(2)),
      );
    }).toList();

    return ReceiptData(
      merchantName: merchant.$1,
      cnpj: merchant.$2,
      date: DateTime.now().subtract(Duration(hours: rng.nextInt(48))),
      items: items,
    );
  }
}

final ocrServiceProvider = Provider<OcrService>((ref) {
  // Env.useMockAi keeps the demo fully offline; a real integration would
  // return an MlKitOcrService / TextractOcrService here.
  assert(Env.useMockAi, 'Real OCR backend not configured — set USE_MOCK_AI=true');
  return MockOcrService();
});
