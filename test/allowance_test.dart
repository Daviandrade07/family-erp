import 'package:family_erp/data/repositories/repositories.dart';
import 'package:family_erp/services/alerts_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// T3 — Semáforo "quanto posso gastar" (`spendingAllowanceProvider`).
///
/// `free = totalBalance − billsPending`; `perDay = free / diasRestantes`.
/// Para não depender do dia do mês, os cenários com `perDay` fixo escalam o
/// `free` pelos dias restantes (calculados com a mesma fórmula da produção).
void main() {
  // Dias restantes no mês, igual à conta feita dentro do provider.
  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final daysLeft = daysInMonth - now.day + 1;

  Future<SpendingAllowance> run({
    required double totalBalance,
    required double billsPending,
    required double todaySpent,
  }) async {
    final container = ProviderContainer(overrides: [
      analyticsRepositoryProvider.overrideWithValue(
        FakeAnalyticsRepository(
          kpisResult:
              buildKpis(totalBalance: totalBalance, billsPending: billsPending),
          todaySpent: todaySpent,
        ),
      ),
    ]);
    addTearDown(container.dispose);
    return container.read(spendingAllowanceProvider.future);
  }

  test('vermelho e perDay 0 quando não há margem (contas > saldo)', () async {
    final a = await run(totalBalance: 100, billsPending: 200, todaySpent: 0);
    expect(a.status, AllowanceStatus.vermelho);
    expect(a.perDay, 0);
    expect(a.freeThisMonth, -100);
  });

  test('sem dados não aparece como crise financeira', () async {
    final a = await run(totalBalance: 0, billsPending: 0, todaySpent: 0);
    expect(a.status, AllowanceStatus.semDados);
    expect(a.message, contains('primeiro movimento'));
  });

  test('verde quando há margem e nada foi gasto hoje', () async {
    final free = 300.0 * daysLeft; // perDay = 300
    final a = await run(totalBalance: free, billsPending: 0, todaySpent: 0);
    expect(a.status, AllowanceStatus.verde);
    expect(a.perDay, closeTo(300, 1e-9));
    expect(a.daysLeft, daysLeft);
  });

  test('amarelo quando o gasto de hoje passa de 70% do limite diário',
      () async {
    final free = 300.0 * daysLeft; // perDay = 300; 70% = 210
    final a = await run(totalBalance: free, billsPending: 0, todaySpent: 250);
    expect(a.status, AllowanceStatus.amarelo);
  });

  test('vermelho quando o gasto de hoje ultrapassa o limite diário', () async {
    final free = 300.0 * daysLeft; // perDay = 300
    final a = await run(totalBalance: free, billsPending: 0, todaySpent: 301);
    expect(a.status, AllowanceStatus.vermelho);
  });

  test('perDay = free / diasRestantes', () async {
    final a = await run(totalBalance: 1000, billsPending: 100, todaySpent: 0);
    expect(a.freeThisMonth, 900);
    expect(a.perDay, closeTo(900 / daysLeft, 1e-9));
  });
}
