import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-3A — Rounding exato das parcelas.
///
/// Testa o seam puro `buildInstallmentRows`: a soma das N parcelas deve ser
/// exatamente o total (última absorve o resto). Sem Supabase.
void main() {
  Transaction tx({double amount = 100, int? installments}) => Transaction(
        familyId: 'fam-1',
        userId: 'user-1',
        type: TransactionType.expense,
        amount: amount,
        category: 'Mercado',
        description: 'Compra',
        date: DateTime(2026, 6, 15),
        totalInstallments: installments,
      );

  double sumAmounts(List<Map<String, dynamic>> rows) =>
      rows.fold(0.0, (s, r) => s + double.parse(r['amount'].toString()));

  test('100 / 3 → soma exata 100,00 (33,33 + 33,33 + 33,34)', () {
    final rows = TransactionRepository.buildInstallmentRows(
        tx(amount: 100, installments: 3));
    expect(rows.length, 3);
    expect(rows.map((r) => r['amount']).toList(),
        ['33.33', '33.33', '33.34']);
    expect(sumAmounts(rows), closeTo(100.00, 1e-9));
  });

  test('10 / 6 → soma exata 10,00', () {
    final rows = TransactionRepository.buildInstallmentRows(
        tx(amount: 10, installments: 6));
    expect(rows.length, 6);
    expect(sumAmounts(rows), closeTo(10.00, 1e-9));
  });

  test('1 parcela → valor igual ao total', () {
    final rows = TransactionRepository.buildInstallmentRows(
        tx(amount: 100, installments: 1));
    expect(rows.length, 1);
    expect(double.parse(rows.first['amount'].toString()), 100.0);
  });

  test('sem parcelamento (null) → 1 linha com o total', () {
    final rows = TransactionRepository.buildInstallmentRows(tx(amount: 49.9));
    expect(rows.length, 1);
    expect(double.parse(rows.first['amount'].toString()), 49.9);
  });

  test('preserva campos e numera/dateia as parcelas', () {
    final rows = TransactionRepository.buildInstallmentRows(
        tx(amount: 100, installments: 3));
    for (var i = 0; i < 3; i++) {
      expect(rows[i]['installment_number'], i + 1);
      expect(rows[i]['type'], 'expense');
      expect(rows[i]['category'], 'Mercado');
      expect(rows[i]['description'], 'Compra');
      expect(rows[i]['family_id'], 'fam-1');
    }
    expect(rows[0]['date'], '2026-06-15');
    expect(rows[1]['date'], '2026-07-15');
    expect(rows[2]['date'], '2026-08-15');
  });
}
