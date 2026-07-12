import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-2 — Reconciliação Bill↔Caixa.
///
/// Testa o núcleo puro `billPaymentTransaction` (decide SE e COMO a despesa é
/// gerada). A orquestração no banco (update condicional pending→paid + insert)
/// é a garantia de idempotência e é verificada por construção: a transação só
/// é criada quando o update transiciona a bill de fato.
void main() {
  Bill bill({String? account, String? category}) => Bill(
        id: 'bill-1',
        familyId: 'fam-1',
        description: 'Conta de luz',
        amount: 120.0,
        dueDate: DateTime(2026, 6, 10),
        category: category,
        accountId: account,
      );

  group('BillRepository.billPaymentTransaction', () {
    test('bill vinculada a conta gera despesa com os campos corretos', () {
      final tx = BillRepository.billPaymentTransaction(
        bill(account: 'acc-1', category: 'Energia'),
        userId: 'user-1',
        on: DateTime(2026, 6, 15),
      );

      expect(tx, isNotNull);
      expect(tx!.type, TransactionType.expense);
      expect(tx.amount, 120.0);
      expect(tx.category, 'Energia');
      expect(tx.description, 'Conta de luz');
      expect(tx.accountId, 'acc-1');
      expect(tx.date, DateTime(2026, 6, 15));
      expect(tx.tags, ['conta-paga']);
      expect(tx.familyId, 'fam-1');
      expect(tx.userId, 'user-1');
    });

    test('bill SEM conta não gera transação (apenas lembrete)', () {
      final tx = BillRepository.billPaymentTransaction(
        bill(), // sem conta vinculada
        userId: 'user-1',
      );
      expect(tx, isNull);
    });

    test('categoria cai em "Outros" quando a bill não tem categoria', () {
      final tx = BillRepository.billPaymentTransaction(
        bill(account: 'acc-1'), // sem categoria
        userId: 'user-1',
      );
      expect(tx!.category, 'Outros');
    });
  });
}
