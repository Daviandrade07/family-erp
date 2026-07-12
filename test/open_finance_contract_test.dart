import 'package:flutter_test/flutter_test.dart';
import 'package:family_erp/services/open_finance/open_finance_contract.dart';

void main() {
  test('conexão ativa permite leitura e revogação', () {
    const connection = OpenFinanceConnection(
      id: 'consent-1',
      status: OpenFinanceConnectionStatus.active,
      scopes: {OpenFinanceScope.accounts, OpenFinanceScope.transactions},
    );

    expect(connection.canRead, isTrue);
    expect(connection.isRevocable, isTrue);
  });

  test('conexão expirada não é tratada como leitura disponível', () {
    const connection = OpenFinanceConnection(
      id: 'consent-2',
      status: OpenFinanceConnectionStatus.expired,
      scopes: {OpenFinanceScope.balances},
    );

    expect(connection.canRead, isFalse);
    expect(connection.isRevocable, isFalse);
  });
}
