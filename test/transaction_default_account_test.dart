import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-1 — conta padrão para lançamentos sem conta/cartão.
///
/// Testa o helper puro `withDefaultAccount`, que decide se a conta default é
/// injetada no mapa de inserção. A resolução da conta em si (consulta ao
/// Supabase) é uma chamada fina, verificada por construção — o importador de
/// nota e os demais fluxos herdam este comportamento por passarem pelo
/// `TransactionRepository.insert`.
void main() {
  Map<String, dynamic> expenseRow({String? account, String? card}) =>
      Transaction(
        familyId: 'fam-1',
        userId: 'user-1',
        type: TransactionType.expense,
        amount: 50,
        category: 'Mercado',
        date: DateTime(2026, 6, 15),
        accountId: account,
        cardId: card,
      ).toInsert();

  group('TransactionRepository.withDefaultAccount', () {
    test('injeta a conta default quando não há conta nem cartão', () {
      final row = TransactionRepository.withDefaultAccount(
        expenseRow(),
        defaultAccountId: 'acc-default',
      );
      expect(row['account_id'], 'acc-default');
    });

    test('não altera quando já há account_id explícito', () {
      final row = TransactionRepository.withDefaultAccount(
        expenseRow(account: 'acc-x'),
        defaultAccountId: 'acc-default',
      );
      expect(row['account_id'], 'acc-x');
    });

    test('não altera quando há card_id (compra no cartão)', () {
      final row = TransactionRepository.withDefaultAccount(
        expenseRow(card: 'card-x'),
        defaultAccountId: 'acc-default',
      );
      expect(row['account_id'], isNull);
      expect(row['card_id'], 'card-x');
    });

    test('sem conta default (nenhuma conta cadastrada): mantém sem conta',
        () {
      final row = TransactionRepository.withDefaultAccount(
        expenseRow(),
        defaultAccountId: null,
      );
      expect(row['account_id'], isNull);
    });
  });
}
