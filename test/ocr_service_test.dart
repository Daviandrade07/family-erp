import 'dart:typed_data';

import 'package:kinfin/services/ai/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockOcrService', () {
    test('extracts a structured receipt with merchant, CNPJ, date and items',
        () async {
      final service = MockOcrService();
      final receipt =
          await service.scanReceipt(Uint8List.fromList([1, 2, 3, 4]));

      expect(receipt.merchantName, isNotEmpty);
      expect(receipt.cnpj, matches(RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}')));
      expect(receipt.items.length, inInclusiveRange(4, 9));
      expect(receipt.total, greaterThan(0));
      for (final item in receipt.items) {
        expect(item.quantity, greaterThan(0));
        expect(item.unitPrice, greaterThan(0));
        expect(item.total, closeTo(item.quantity * item.unitPrice, 0.001));
      }
    });

    test('is deterministic for the same photo bytes', () async {
      final service = MockOcrService();
      final bytes = Uint8List.fromList(List.generate(64, (i) => i * 7 % 251));

      final a = await service.scanReceipt(bytes);
      final b = await service.scanReceipt(bytes);

      expect(a.merchantName, b.merchantName);
      expect(a.cnpj, b.cnpj);
      expect(a.items.length, b.items.length);
      expect(a.total, closeTo(b.total, 0.001));
    });
  });
}
