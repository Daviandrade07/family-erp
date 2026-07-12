import 'dart:convert';

import 'package:family_erp/data/models/models.dart';
import 'package:family_erp/data/repositories/repositories.dart';
import 'package:family_erp/services/ai/assistant_tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// T4 — Ferramenta `can_i_afford` (`AssistantToolExecutor.execute`).
///
/// Regras: available = saldo de contas não-cartão; committed = contas
/// pendentes que vencem em 30 dias; reserva = max(100, 10% do saldo);
/// livre = available − committed − reserva. Testa o JSON de veredito.
void main() {
  Future<Map<String, dynamic>> ask({
    required List<FinancialAccount> accounts,
    required List<Bill> bills,
    required Object amount,
  }) async {
    final container = ProviderContainer(overrides: [
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository(accounts)),
      billRepositoryProvider.overrideWithValue(FakeBillRepository(bills)),
    ]);
    addTearDown(container.dispose);
    final executor = container.read(assistantToolExecutorProvider);
    final raw = await executor.execute('can_i_afford', {'amount': amount});
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  final soon = DateTime.now().add(const Duration(days: 10));

  test('pode_comprar quando sobra bem acima da reserva', () async {
    final r = await ask(
      accounts: [buildAccount(balance: 1000)],
      bills: const [],
      amount: 100,
    );
    expect(r['veredito'], 'pode_comprar');
    expect(r['pode_comprar'], isTrue);
  });

  test('cabe_mas_aperta_a_reserva quando invade a reserva de segurança', () async {
    final r = await ask(
      accounts: [buildAccount(balance: 1000)],
      bills: const [],
      amount: 950, // livre = 1000 - 0 - 100 = 900; 950 > 900, mas <= 1000
    );
    expect(r['veredito'], 'cabe_mas_aperta_a_reserva');
    expect(r['pode_comprar'], isFalse);
  });

  test('compromete_contas_do_mes quando passa do saldo livre de contas', () async {
    final r = await ask(
      accounts: [buildAccount(balance: 1000)],
      bills: [buildBill(amount: 500, dueDate: soon)], // committed = 500
      amount: 700, // > available - committed (500), mas <= available (1000)
    );
    expect(r['veredito'], 'compromete_contas_do_mes');
    expect(r['pode_comprar'], isFalse);
  });

  test('nao_ha_saldo quando o valor excede o saldo em conta', () async {
    final r = await ask(
      accounts: [buildAccount(balance: 1000)],
      bills: const [],
      amount: 1500,
    );
    expect(r['veredito'], 'nao_ha_saldo');
    expect(r['pode_comprar'], isFalse);
  });

  test('cartão de crédito não conta como saldo disponível', () async {
    final r = await ask(
      accounts: [
        buildAccount(balance: 100, id: 'bank'),
        buildAccount(
            balance: 5000, id: 'card', type: AccountType.creditCard),
      ],
      bills: const [],
      amount: 300, // > 100 (só o banco conta) → sem saldo
    );
    expect(r['saldo_em_conta'], 100);
    expect(r['veredito'], 'nao_ha_saldo');
  });

  test('retorna erro quando o valor é ausente ou não-positivo', () async {
    final r = await ask(
      accounts: [buildAccount(balance: 1000)],
      bills: const [],
      amount: 0,
    );
    expect(r.containsKey('erro'), isTrue);
  });
}
