import 'dart:async';

import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/data/repositories/repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fakes manuais compartilhados pelos testes da micro-etapa 0.2.
///
/// Cada fake `implements` a classe de produção e sobrescreve APENAS os métodos
/// realmente exercitados pelo alvo sob teste; qualquer outro membro cai em
/// [noSuchMethod], que lança — assim um uso inesperado falha alto em vez de
/// silenciar. Nenhum toca Supabase, rede ou disco.

// ---------------------------------------------------------------------------
// Analytics (usado por spendingAllowanceProvider)
// ---------------------------------------------------------------------------
class FakeAnalyticsRepository implements AnalyticsRepository {
  FakeAnalyticsRepository({required this.kpisResult, required this.todaySpent});

  final DashboardKpis kpisResult;
  final double todaySpent;

  @override
  Future<DashboardKpis> kpis() async => kpisResult;

  @override
  Future<double> todayExpenses() async => todaySpent;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeAnalyticsRepository não implementa ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Account / Bill (usados por can_i_afford)
// ---------------------------------------------------------------------------
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository(this._accounts);

  final List<FinancialAccount> _accounts;

  @override
  Future<List<FinancialAccount>> all(
          {String orderBy = 'created_at', bool asc = false}) async =>
      _accounts;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeAccountRepository não implementa ${invocation.memberName}');
}

class FakeBillRepository implements BillRepository {
  FakeBillRepository(this._bills);

  final List<Bill> _bills;

  @override
  Future<List<Bill>> all({String orderBy = 'due_date', bool asc = true}) async =>
      _bills;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeBillRepository não implementa ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Transaction / Inventory (usados pela importação determinística de nota)
// ---------------------------------------------------------------------------
class FakeTransactionRepository implements TransactionRepository {
  /// Transações capturadas por insert (não persiste nada de verdade).
  final List<Transaction> inserted = [];

  @override
  Future<void> insert(Transaction tx) async => inserted.add(tx);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeTransactionRepository não implementa ${invocation.memberName}');
}

class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository([List<InventoryItem>? initial])
      : _items = initial ?? const [];

  final List<InventoryItem> _items;

  /// Chamadas capturadas.
  final List<Map<String, dynamic>> inserted = [];
  final List<({String id, Map<String, dynamic> data})> updated = [];

  @override
  Future<List<InventoryItem>> all(
          {String orderBy = 'expiration_date', bool asc = true}) async =>
      _items;

  @override
  Future<void> insertRow(Map<String, dynamic> data) async =>
      inserted.add(data);

  @override
  Future<void> updateRow(String id, Map<String, dynamic> data) async =>
      updated.add((id: id, data: data));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeInventoryRepository não implementa ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Auth (usado por AuthController)
// ---------------------------------------------------------------------------

/// Sessão falsa: o AuthController só verifica `session == null`, nunca lê seus
/// campos, então basta um objeto que satisfaça o tipo [Session].
class FakeSession implements Session {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeSession não implementa ${invocation.memberName}');
}

class FakeAuthRepository implements AuthRepository {
  Session? sessionValue;
  AppUser? profileValue;

  /// Quantas vezes fetchProfile foi realmente executado (prova de coalescing).
  int fetchProfileCalls = 0;

  /// Quando true, fetchProfile lança — simula erro transitório (ex.: rede).
  bool throwOnFetch = false;

  final StreamController<AuthState> _authChanges =
      StreamController<AuthState>.broadcast();

  @override
  Session? get session => sessionValue;

  @override
  Stream<AuthState> get onAuthStateChange => _authChanges.stream;

  @override
  Future<AppUser?> fetchProfile() async {
    fetchProfileCalls++;
    if (throwOnFetch) throw Exception('fetchProfile falhou (simulado)');
    return profileValue;
  }

  void dispose() => _authChanges.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeAuthRepository não implementa ${invocation.memberName}');
}

// ---------------------------------------------------------------------------
// Construtores auxiliares
// ---------------------------------------------------------------------------
DashboardKpis buildKpis({
  double totalBalance = 0,
  double billsPending = 0,
}) =>
    DashboardKpis(
      totalBalance: totalBalance,
      netWorth: totalBalance,
      billsPending: billsPending,
      billsOverdue: 0,
      monthExpenses: 0,
      monthRevenue: 0,
    );

FinancialAccount buildAccount({
  required double balance,
  AccountType type = AccountType.bankAccount,
  String id = 'acc-1',
}) =>
    FinancialAccount(
      id: id,
      familyId: 'fam-1',
      name: 'Conta',
      type: type,
      balance: balance,
    );

Bill buildBill({
  required double amount,
  required DateTime dueDate,
  BillStatus status = BillStatus.pending,
  String description = 'Conta',
}) =>
    Bill(
      familyId: 'fam-1',
      description: description,
      amount: amount,
      dueDate: dueDate,
      status: status,
    );

AppUser buildUser({String? familyId, UserRole role = UserRole.user}) => AppUser(
      id: 'user-1',
      familyId: familyId,
      name: 'Davi',
      email: 'davi@example.com',
      role: role,
      active2fa: false,
    );
