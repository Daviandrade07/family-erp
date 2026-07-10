import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

final supabaseProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

// ============================================================
// AUTH
// ============================================================
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  User? get authUser => _client.auth.currentUser;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signUp(String name, String email, String password) =>
      _client.auth
          .signUp(email: email, password: password, data: {'name': name});

  Future<void> signOut() => _client.auth.signOut();

  /// MFA (TOTP) enrollment — returns the QR/secret payload to display.
  ///
  /// Antes de criar um novo fator, remove os fatores TOTP ainda NÃO
  /// verificados de tentativas anteriores. Sem isso, cada abertura da tela de
  /// 2FA acumulava um fator pendente até estourar o limite do Supabase e
  /// passar a falhar.
  Future<({String factorId, String secret, String uri})> enrollTotp() async {
    try {
      final factors = await _client.auth.mfa.listFactors();
      for (final f in factors.all) {
        if (f.status == FactorStatus.unverified) {
          try {
            await _client.auth.mfa.unenroll(f.id);
          } catch (_) {/* segue tentando os demais */}
        }
      }
    } catch (_) {/* sem fatores ou API indisponível — segue para o enroll */}

    final res = await _client.auth.mfa.enroll(
      factorType: FactorType.totp,
      friendlyName:
          'Família ERP · ${DateTime.now().millisecondsSinceEpoch}',
    );
    return (
      factorId: res.id,
      secret: res.totp?.secret ?? '',
      uri: res.totp?.uri ?? '',
    );
  }

  Future<void> verifyTotp(String factorId, String code) async {
    final challenge =
        await _client.auth.mfa.challenge(factorId: factorId);
    await _client.auth.mfa.verify(
      factorId: factorId,
      challengeId: challenge.id,
      code: code,
    );
    final uid = authUser?.id;
    if (uid != null) {
      await _client.from('users').update({'active_2fa': true}).eq('id', uid);
    }
  }

  Future<AppUser?> fetchProfile() async {
    final uid = authUser?.id;
    if (uid == null) return null;
    final row =
        await _client.from('users').select().eq('id', uid).maybeSingle();
    return row == null ? null : AppUser.fromJson(row);
  }

  Future<String> createFamily(String name) async =>
      await _client.rpc('create_family', params: {'family_name': name})
          as String;

  Future<void> joinFamily(String familyId) =>
      _client.rpc('join_family', params: {'target_family': familyId});

  Future<void> updateMemberRole(String userId, UserRole role) => _client
      .from('users')
      .update({'role': role.name}).eq('id', userId);

  Future<List<AppUser>> familyMembers(String familyId) async {
    final rows =
        await _client.from('users').select().eq('family_id', familyId);
    return rows.map<AppUser>((r) => AppUser.fromJson(r)).toList();
  }
}

// ============================================================
// TRANSACTIONS — pagination + advanced filters
// ============================================================
class TransactionFilter {
  const TransactionFilter({
    this.type,
    this.category,
    this.userId,
    this.tag,
    this.from,
    this.to,
    this.search,
  });

  final TransactionType? type;
  final String? category;
  final String? userId;
  final String? tag;
  final DateTime? from;
  final DateTime? to;
  final String? search;

  bool get isEmpty =>
      type == null &&
      category == null &&
      userId == null &&
      tag == null &&
      from == null &&
      to == null &&
      (search == null || search!.isEmpty);

  TransactionFilter copyWith({
    TransactionType? Function()? type,
    String? Function()? category,
    String? Function()? userId,
    String? Function()? tag,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? search,
  }) =>
      TransactionFilter(
        type: type != null ? type() : this.type,
        category: category != null ? category() : this.category,
        userId: userId != null ? userId() : this.userId,
        tag: tag != null ? tag() : this.tag,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        search: search != null ? search() : this.search,
      );
}

class TransactionRepository {
  TransactionRepository(this._client);

  final SupabaseClient _client;
  static const pageSize = 25;

  Future<List<Transaction>> fetchPage({
    required int page,
    TransactionFilter filter = const TransactionFilter(),
  }) async {
    var query = _client.from('transactions').select('*, users(name)');

    if (filter.type != null) query = query.eq('type', filter.type!.name);
    if (filter.category != null) query = query.eq('category', filter.category!);
    if (filter.userId != null) query = query.eq('user_id', filter.userId!);
    if (filter.tag != null) query = query.contains('tags', [filter.tag!]);
    if (filter.from != null) {
      query = query.gte(
          'date', filter.from!.toIso8601String().substring(0, 10));
    }
    if (filter.to != null) {
      query =
          query.lte('date', filter.to!.toIso8601String().substring(0, 10));
    }
    if (filter.search != null && filter.search!.isNotEmpty) {
      query = query.or(
          'description.ilike.%${filter.search}%,beneficiary.ilike.%${filter.search}%');
    }

    final rows = await query
        .order('date', ascending: false)
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);
    return rows.map<Transaction>((r) => Transaction.fromJson(r)).toList();
  }

  Future<void> insert(Transaction tx) async {
    if (tx.totalInstallments != null && tx.totalInstallments! > 1) {
      // Split into N installment rows, one per month.
      final rows = List.generate(tx.totalInstallments!, (i) {
        final d = DateTime(tx.date.year, tx.date.month + i, tx.date.day);
        final map = tx.toInsert();
        map['date'] = d.toIso8601String().substring(0, 10);
        map['installment_number'] = i + 1;
        map['amount'] =
            (tx.amount / tx.totalInstallments!).toStringAsFixed(2);
        return map;
      });
      await _client.from('transactions').insert(rows);
    } else {
      await _client.from('transactions').insert(tx.toInsert());
    }
  }

  Future<void> delete(String id) =>
      _client.from('transactions').delete().eq('id', id);

  /// Parcelas ainda a vencer (installments de hoje em diante).
  Future<List<Transaction>> upcomingInstallments() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await _client
        .from('transactions')
        .select()
        .not('total_installments', 'is', null)
        .gte('date', today)
        .order('date');
    return rows.map<Transaction>((r) => Transaction.fromJson(r)).toList();
  }

  /// All expenses of the last [days] days (input for the AI prediction agent).
  Future<List<Transaction>> recentExpenses({int days = 120}) async {
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    final rows = await _client
        .from('transactions')
        .select()
        .eq('type', 'expense')
        .gte('date', since)
        .order('date');
    return rows.map<Transaction>((r) => Transaction.fromJson(r)).toList();
  }
}

// ============================================================
// ANALYTICS (server-side RPCs)
// ============================================================
class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardKpis> kpis() async {
    final res = await _client.rpc('dashboard_kpis');
    return DashboardKpis.fromJson(Map<String, dynamic>.from(res));
  }

  Future<List<DailyFlow>> dailyCashFlow({int daysBack = 30}) async {
    final rows = await _client
        .rpc('daily_cash_flow', params: {'days_back': daysBack});
    return (rows as List)
        .map((r) => DailyFlow.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<CategorySpend>> monthSpendByCategory() async {
    final rows = await _client.rpc('month_spend_by_category');
    return (rows as List)
        .map((r) => CategorySpend.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Total gasto hoje (para o semáforo "quanto posso gastar").
  Future<double> todayExpenses() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await _client
        .from('transactions')
        .select('amount')
        .eq('type', 'expense')
        .eq('date', today);
    return rows.fold<double>(
        0, (s, r) => s + (r['amount'] as num).toDouble());
  }

  /// Map isoWeekday (1..7) → total spend, last 90 days.
  Future<Map<int, double>> weekdayHeatmap() async {
    final rows = await _client.rpc('weekday_heatmap');
    return {
      for (final r in rows as List)
        (r['weekday'] as num).toInt(): (r['total'] as num).toDouble()
    };
  }

  Future<List<BudgetUsage>> budgetUsage() async {
    final rows = await _client.rpc('budget_usage');
    return (rows as List)
        .map((r) => BudgetUsage.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Resumo dos últimos 7 dias vs. os 7 anteriores (para o card semanal):
  /// gastos, receitas, saldo, categoria que mais pesou e variação.
  Future<WeekSummary> weekSummary() async {
    final now = DateTime.now();
    final start7 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6)); // hoje + 6 = 7 dias
    final startPrev = start7.subtract(const Duration(days: 7));

    final rows = await _client
        .from('transactions')
        .select('amount, type, category, date')
        .gte('date', startPrev.toIso8601String().substring(0, 10))
        .order('date');

    var expense = 0.0, revenue = 0.0, prevExpense = 0.0;
    final byCategory = <String, double>{};
    for (final r in rows) {
      final date = DateTime.parse(r['date'] as String);
      final amount = (r['amount'] as num).toDouble();
      final isExpense = r['type'] == 'expense';
      final inThisWeek = !date.isBefore(start7);
      if (inThisWeek) {
        if (isExpense) {
          expense += amount;
          final cat = (r['category'] as String?) ?? 'Outros';
          byCategory[cat] = (byCategory[cat] ?? 0) + amount;
        } else {
          revenue += amount;
        }
      } else if (isExpense) {
        prevExpense += amount;
      }
    }

    String? topCategory;
    var topCategoryTotal = 0.0;
    byCategory.forEach((cat, total) {
      if (total > topCategoryTotal) {
        topCategoryTotal = total;
        topCategory = cat;
      }
    });

    return WeekSummary(
      expenses: expense,
      revenue: revenue,
      previousExpenses: prevExpense,
      topCategory: topCategory,
      topCategoryTotal: topCategoryTotal,
    );
  }
}

// ============================================================
// Generic family-scoped CRUD base
// ============================================================
abstract class _FamilyCrud<T> {
  _FamilyCrud(this.client, this.table);

  final SupabaseClient client;
  final String table;

  T fromJson(Map<String, dynamic> json);

  Future<List<T>> all({String orderBy = 'created_at', bool asc = false}) async {
    final rows =
        await client.from(table).select().order(orderBy, ascending: asc);
    return rows.map<T>((r) => fromJson(r)).toList();
  }

  Future<void> insertRow(Map<String, dynamic> data) =>
      client.from(table).insert(data);

  Future<void> updateRow(String id, Map<String, dynamic> data) =>
      client.from(table).update(data).eq('id', id);

  Future<void> deleteRow(String id) =>
      client.from(table).delete().eq('id', id);
}

class BudgetRepository extends _FamilyCrud<Budget> {
  BudgetRepository(SupabaseClient c) : super(c, 'budgets');

  @override
  Budget fromJson(Map<String, dynamic> json) => Budget.fromJson(json);
}

class AccountRepository extends _FamilyCrud<FinancialAccount> {
  AccountRepository(SupabaseClient c) : super(c, 'accounts_and_cards');

  @override
  FinancialAccount fromJson(Map<String, dynamic> json) =>
      FinancialAccount.fromJson(json);
}

class InventoryRepository extends _FamilyCrud<InventoryItem> {
  InventoryRepository(SupabaseClient c) : super(c, 'inventory');

  @override
  InventoryItem fromJson(Map<String, dynamic> json) =>
      InventoryItem.fromJson(json);

  @override
  Future<List<InventoryItem>> all(
          {String orderBy = 'expiration_date', bool asc = true}) async {
    final rows = await client
        .from(table)
        .select()
        .order(orderBy, ascending: asc, nullsFirst: false);
    return rows.map<InventoryItem>((r) => fromJson(r)).toList();
  }

  /// Consume [amount] of an item (auto decrement). The low-stock DB trigger
  /// adds it to the shopping list when it crosses min_quantity.
  Future<void> consume(InventoryItem item, double amount) async {
    final next = (item.quantity - amount).clamp(0, double.infinity);
    await updateRow(item.id!, {'quantity': next});
  }
}

class ShoppingRepository extends _FamilyCrud<ShoppingItem> {
  ShoppingRepository(SupabaseClient c) : super(c, 'shopping_lists');

  @override
  ShoppingItem fromJson(Map<String, dynamic> json) =>
      ShoppingItem.fromJson(json);

  Future<void> markBought(ShoppingItem item,
      {double? unitPrice, String? market}) async {
    await updateRow(item.id!, {
      'status': 'bought',
      'execution_data': {
        ...item.executionData,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (market != null) 'market': market,
        'bought_at': DateTime.now().toIso8601String(),
      },
    });
  }
}

class MealRepository extends _FamilyCrud<MealPlan> {
  MealRepository(SupabaseClient c) : super(c, 'meal_plans');

  @override
  MealPlan fromJson(Map<String, dynamic> json) => MealPlan.fromJson(json);

  Future<MealPlan?> forWeek(DateTime weekStart) async {
    final row = await client
        .from(table)
        .select()
        .eq('week_start', weekStart.toIso8601String().substring(0, 10))
        .maybeSingle();
    return row == null ? null : MealPlan.fromJson(row);
  }

  Future<void> upsert(MealPlan plan) => client
      .from(table)
      .upsert(plan.toInsert(), onConflict: 'family_id,week_start');
}

class GoalRepository extends _FamilyCrud<FinancialGoal> {
  GoalRepository(SupabaseClient c) : super(c, 'financial_goals');

  @override
  FinancialGoal fromJson(Map<String, dynamic> json) =>
      FinancialGoal.fromJson(json);
}

class BillRepository extends _FamilyCrud<Bill> {
  BillRepository(SupabaseClient c) : super(c, 'bills_payable');

  @override
  Bill fromJson(Map<String, dynamic> json) => Bill.fromJson(json);

  @override
  Future<List<Bill>> all({String orderBy = 'due_date', bool asc = true}) =>
      super.all(orderBy: orderBy, asc: asc);

  Future<void> markPaid(Bill bill) =>
      updateRow(bill.id!, {'status': 'paid'});
}

class DebtRepository extends _FamilyCrud<Debt> {
  DebtRepository(SupabaseClient c) : super(c, 'debts');

  @override
  Debt fromJson(Map<String, dynamic> json) => Debt.fromJson(json);

  /// Abate um pagamento do saldo devedor (fiado/dívida).
  Future<void> registerPayment(Debt debt, double amount) {
    final next = (debt.remainingAmount - amount).clamp(0, double.infinity);
    return updateRow(debt.id!, {'remaining_amount': next});
  }
}

class MarketRepository {
  MarketRepository(this._client);

  final SupabaseClient _client;

  Future<List<Market>> all() async {
    final rows = await _client.from('markets').select();
    return rows.map<Market>((r) => Market.fromJson(r)).toList();
  }
}

// ============================================================
// Providers
// ============================================================
final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(supabaseProvider)));
final transactionRepositoryProvider =
    Provider((ref) => TransactionRepository(ref.watch(supabaseProvider)));
final analyticsRepositoryProvider =
    Provider((ref) => AnalyticsRepository(ref.watch(supabaseProvider)));
final budgetRepositoryProvider =
    Provider((ref) => BudgetRepository(ref.watch(supabaseProvider)));
final accountRepositoryProvider =
    Provider((ref) => AccountRepository(ref.watch(supabaseProvider)));
final inventoryRepositoryProvider =
    Provider((ref) => InventoryRepository(ref.watch(supabaseProvider)));
final shoppingRepositoryProvider =
    Provider((ref) => ShoppingRepository(ref.watch(supabaseProvider)));
final mealRepositoryProvider =
    Provider((ref) => MealRepository(ref.watch(supabaseProvider)));
final goalRepositoryProvider =
    Provider((ref) => GoalRepository(ref.watch(supabaseProvider)));
final billRepositoryProvider =
    Provider((ref) => BillRepository(ref.watch(supabaseProvider)));
final debtRepositoryProvider =
    Provider((ref) => DebtRepository(ref.watch(supabaseProvider)));
final marketRepositoryProvider =
    Provider((ref) => MarketRepository(ref.watch(supabaseProvider)));
