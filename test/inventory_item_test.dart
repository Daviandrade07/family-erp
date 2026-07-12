import 'package:family_erp/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// T9 — Campos derivados de estoque: `isLowStock` e `daysToExpire`.
///
/// `daysToExpire` depende de `DateTime.now()`. Para eliminar flakiness, a
/// validade é construída como `meia-noite-de-hoje + Duration(days: N)`, então
/// a diferença é exatamente N — independente do horário/fuso da execução.
void main() {
  InventoryItem item({
    required double quantity,
    required double minQuantity,
    DateTime? expiration,
  }) =>
      InventoryItem(
        familyId: 'fam-1',
        productName: 'Arroz',
        quantity: quantity,
        minQuantity: minQuantity,
        expirationDate: expiration,
      );

  group('InventoryItem.isLowStock', () {
    test('is low when quantity is at or below the minimum', () {
      expect(item(quantity: 1, minQuantity: 1).isLowStock, isTrue);
      expect(item(quantity: 0.5, minQuantity: 1).isLowStock, isTrue);
    });

    test('is not low when quantity is above the minimum', () {
      expect(item(quantity: 2, minQuantity: 1).isLowStock, isFalse);
    });
  });

  group('InventoryItem.daysToExpire', () {
    final now = DateTime.now();
    final midnightToday = DateTime(now.year, now.month, now.day);

    test('is null when there is no expiration date', () {
      expect(item(quantity: 1, minQuantity: 1).daysToExpire, isNull);
    });

    test('is positive for a future expiration date', () {
      final exp = midnightToday.add(const Duration(days: 5));
      expect(item(quantity: 1, minQuantity: 1, expiration: exp).daysToExpire, 5);
    });

    test('is negative for a past expiration date', () {
      final exp = midnightToday.subtract(const Duration(days: 3));
      expect(item(quantity: 1, minQuantity: 1, expiration: exp).daysToExpire, -3);
    });

    test('is zero on the expiration day', () {
      expect(
          item(quantity: 1, minQuantity: 1, expiration: midnightToday)
              .daysToExpire,
          0);
    });
  });
}
