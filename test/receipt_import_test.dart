import 'package:family_erp/data/models/models.dart';
import 'package:family_erp/services/ai/ocr_service.dart';
import 'package:family_erp/services/receipt_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Cobre a importação determinística de nota fiscal (ETAPA 1 do BLOCO E):
/// transação de despesa + upsert de despensa com histórico de preço, sem IA.
void main() {
  ReceiptData receipt(
    List<ReceiptItem> items, {
    String merchant = 'GoodBom Indaiatuba',
  }) =>
      ReceiptData(
        merchantName: merchant,
        cnpj: '61.585.865/0001-01',
        date: DateTime(2026, 6, 15),
        items: items,
      );

  test('nota nova: cria a transação de despesa e os itens no estoque', () async {
    final txRepo = FakeTransactionRepository();
    final invRepo = FakeInventoryRepository(); // estoque vazio
    final service = ReceiptImportService(txRepo, invRepo);

    final result = await service.import(
      receipt(const [
        ReceiptItem(name: 'Arroz 5kg', quantity: 1, unitPrice: 24.90),
        ReceiptItem(name: 'Feijão 1kg', quantity: 2, unitPrice: 8.50),
      ]),
      familyId: 'fam-1',
      userId: 'user-1',
    );

    // --- transação ---
    expect(txRepo.inserted, hasLength(1));
    final tx = txRepo.inserted.first;
    expect(tx.type, TransactionType.expense);
    expect(tx.category, 'Mercado');
    expect(tx.amount, closeTo(24.90 + 2 * 8.50, 1e-9));
    expect(tx.description, 'GoodBom Indaiatuba');
    expect(tx.date, DateTime(2026, 6, 15));
    expect(tx.tags, ['nota-fiscal']);

    // --- itens criados ---
    expect(result.itemsCreated, 2);
    expect(result.itemsUpdated, 0);
    expect(invRepo.inserted, hasLength(2));
    expect(invRepo.updated, isEmpty);

    // price_history no item recém-criado
    final firstInsert = invRepo.inserted.first;
    final history = firstInsert['price_history'] as List;
    expect(history, hasLength(1));
    expect((history.first as Map)['price'], 24.90);
    expect((history.first as Map)['market'], 'GoodBom Indaiatuba');
  });

  test('item já existente: soma a quantidade e acrescenta price_history',
      () async {
    final txRepo = FakeTransactionRepository();
    final existing = InventoryItem(
      id: 'inv-1',
      familyId: 'fam-1',
      productName: 'Arroz 5kg',
      quantity: 1,
      minQuantity: 1,
      priceHistory: [
        PricePoint(
            price: 22.0,
            market: 'Covabra Supermercados',
            date: DateTime(2026, 5, 10)),
      ],
    );
    final invRepo = FakeInventoryRepository([existing]);
    final service = ReceiptImportService(txRepo, invRepo);

    final result = await service.import(
      receipt(const [
        // nome em caixa diferente: deve casar por lower(name)
        ReceiptItem(name: 'arroz 5kg', quantity: 2, unitPrice: 25.0),
      ]),
      familyId: 'fam-1',
      userId: 'user-1',
    );

    // a transação é sempre criada
    expect(txRepo.inserted, hasLength(1));

    // atualizou, não criou
    expect(result.itemsUpdated, 1);
    expect(result.itemsCreated, 0);
    expect(invRepo.inserted, isEmpty);
    expect(invRepo.updated, hasLength(1));

    final update = invRepo.updated.first;
    expect(update.id, 'inv-1');
    expect(update.data['quantity'], 3); // 1 + 2

    final history = update.data['price_history'] as List;
    expect(history, hasLength(2)); // preço antigo + o novo da nota
    expect((history.last as Map)['price'], 25.0);
    expect((history.last as Map)['market'], 'GoodBom Indaiatuba');
  });
}
