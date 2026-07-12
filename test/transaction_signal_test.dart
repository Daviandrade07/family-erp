import 'package:kinfin/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// T2 — Convenção de sinal de transação.
///
/// Valida o contrato usado (implicitamente) pelo trigger de saldo no banco:
/// despesa reduz o saldo (valor negativo) e receita aumenta (positivo).
/// Puro e determinístico — nenhuma dependência externa.
void main() {
  Transaction tx(TransactionType type, double amount) => Transaction(
        familyId: 'fam-1',
        userId: 'user-1',
        type: type,
        amount: amount,
        category: 'Mercado',
        date: DateTime(2026, 6, 15),
      );

  group('Transaction.signedAmount', () {
    test('expense yields a negative signed amount', () {
      expect(tx(TransactionType.expense, 50).signedAmount, -50);
    });

    test('revenue yields a positive signed amount', () {
      expect(tx(TransactionType.revenue, 50).signedAmount, 50);
    });

    test('preserves magnitude for fractional values', () {
      expect(tx(TransactionType.expense, 12.34).signedAmount, closeTo(-12.34, 1e-9));
      expect(tx(TransactionType.revenue, 12.34).signedAmount, closeTo(12.34, 1e-9));
    });
  });

  group('Transaction.isExpense', () {
    test('is true only for expense type', () {
      expect(tx(TransactionType.expense, 1).isExpense, isTrue);
      expect(tx(TransactionType.revenue, 1).isExpense, isFalse);
    });
  });
}
