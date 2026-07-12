import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import 'ai/ocr_service.dart';

/// Resultado de uma importação de nota (quantos itens foram criados/atualizados).
class ReceiptImportResult {
  const ReceiptImportResult({
    required this.itemsCreated,
    required this.itemsUpdated,
  });

  final int itemsCreated;
  final int itemsUpdated;
}

/// Importação DETERMINÍSTICA de nota fiscal — grava a compra sem passar pelo
/// LLM. Replica exatamente o que os executores de IA fazem hoje
/// (`add_transaction` + `add_pantry_items`), mas a partir do `ReceiptData` já
/// estruturado do OCR.
///
/// Nesta etapa o serviço ainda NÃO é chamado pela UI (o botão de scan segue
/// mandando texto ao chat); o wiring é a etapa 2 do BLOCO E.
class ReceiptImportService {
  ReceiptImportService(this._transactions, this._inventory);

  final TransactionRepository _transactions;
  final InventoryRepository _inventory;

  Future<ReceiptImportResult> import(
    ReceiptData receipt, {
    required String familyId,
    required String userId,
  }) async {
    // 1. Despesa da nota (categoria Mercado). Sem account_id — igual ao fluxo
    //    atual da IA; regra de saldo/conta é F2, fora deste escopo.
    final tx = Transaction(
      familyId: familyId,
      userId: userId,
      type: TransactionType.expense,
      category: 'Mercado',
      amount: receipt.total,
      description: receipt.merchantName,
      date: receipt.date,
      tags: const ['nota-fiscal'],
    );
    await _transactions.insert(tx);

    // 2. Upsert dos itens na despensa (espelha _addPantryItems: um único fetch,
    //    match por lower(name); o mercado da nota vira o market do PricePoint).
    final inventory = await _inventory.all();
    var created = 0;
    var updated = 0;

    for (final item in receipt.items) {
      InventoryItem? existing;
      for (final inv in inventory) {
        if (inv.productName.toLowerCase() == item.name.toLowerCase()) {
          existing = inv;
          break;
        }
      }

      final point = PricePoint(
        price: item.unitPrice,
        market: receipt.merchantName,
        date: DateTime.now(),
      );

      if (existing != null) {
        await _inventory.updateRow(existing.id!, {
          'quantity': existing.quantity + item.quantity,
          'price_history': [
            for (final p in existing.priceHistory) p.toJson(),
            point.toJson(),
          ],
        });
        updated++;
      } else {
        await _inventory.insertRow(InventoryItem(
          familyId: familyId,
          productName: item.name,
          quantity: item.quantity,
          minQuantity: 1,
          priceHistory: [point],
        ).toInsert());
        created++;
      }
    }

    return ReceiptImportResult(itemsCreated: created, itemsUpdated: updated);
  }
}

final receiptImportServiceProvider = Provider(
  (ref) => ReceiptImportService(
    ref.watch(transactionRepositoryProvider),
    ref.watch(inventoryRepositoryProvider),
  ),
);
