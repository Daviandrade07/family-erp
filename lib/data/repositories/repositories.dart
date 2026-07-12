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

  /// Returns true when Supabase created the account but requires e-mail
  /// confirmation before it can create a session.
  Future<bool> signUp(String name, String email, String password) async {
    final response = await _client.auth
        .signUp(email: email, password: password, data: {'name': name});
    return response.session == null;
  }

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
      friendlyName: 'Kinfin · ${DateTime.now().millisecondsSinceEpoch}',
    );
    return (
      factorId: res.id,
      secret: res.totp?.secret ?? '',
      uri: res.totp?.uri ?? '',
    );
  }

  Future<void> verifyTotp(String factorId, String code) async {
    final challenge = await _client.auth.mfa.challenge(factorId: factorId);
    await _client.auth.mfa.verify(
      factorId: factorId,
      challengeId: challenge.id,
      code: code,
    );
    // NÃO gravamos mais um "selo" de 2FA no banco (era falsificável pelo app).
    // A fonte da verdade é o nível REAL da sessão (AAL) e os fatores TOTP
    // verificados — lidos direto do Supabase. Ver [hasAal2] e [hasVerifiedTotp].
  }

  /// Confirma a POSSE do e-mail com o código de 6 dígitos enviado no cadastro
  /// (fluxo oficial signUp → verifyOTP). Cria a sessão quando o código confere.
  /// Isto confirma o endereço; **não** é um segundo fator (2FA real = TOTP/AAL2).
  Future<void> verifyEmailOtp(String email, String token) async {
    await _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email.trim(),
      token: token.trim(),
    );
  }

  /// Reenvia o código de confirmação de cadastro para o e-mail.
  Future<void> resendSignupCode(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email.trim());

  /// Nível REAL de garantia da sessão (fonte da verdade para ações sensíveis).
  /// `aal2` = a pessoa passou pelo segundo fator (TOTP) nesta sessão.
  bool get hasAal2 {
    try {
      return _client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
          AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      return false;
    }
  }

  /// A conta tem um fator TOTP verificado? (para exibir o estado real do 2FA,
  /// sem depender de nenhuma coluna gravável pelo app).
  Future<bool> hasVerifiedTotp() async {
    try {
      final factors = await _client.auth.mfa.listFactors();
      return factors.totp.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Eleva a sessão atual para **AAL2** pedindo um código do app autenticador.
  /// Usado antes de ações sensíveis quando a pessoa tem 2FA. Sem fator TOTP
  /// verificado não há o que elevar (retorna sem erro).
  Future<void> elevateToAal2(String code) async {
    final factors = await _client.auth.mfa.listFactors();
    final totp = factors.totp;
    if (totp.isEmpty) return;
    await verifyTotp(totp.first.id, code.trim());
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

  /// Entra numa família existente mesmo já tendo conta/espaço próprio
  /// (para quem começou sozinho e depois quer se juntar à família).
  Future<void> switchToFamily(String familyId) =>
      _client.rpc('switch_to_family', params: {'target_family': familyId});

  Future<void> updateMemberRole(String userId, UserRole role) => _client.rpc(
        'update_family_member_role',
        params: {'target_user': userId, 'next_role': role.name},
      );

  Future<List<AppUser>> familyMembers(String familyId) async {
    final rows = await _client.from('users').select().eq('family_id', familyId);
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
      query =
          query.gte('date', filter.from!.toIso8601String().substring(0, 10));
    }
    if (filter.to != null) {
      query = query.lte('date', filter.to!.toIso8601String().substring(0, 10));
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
    // F-1: lançamento SEM conta e SEM cartão cai numa conta default, para o
    // saldo não ficar divergente. Resolução determinística; não altera o
    // parcelamento nem toca em trigger/saldo. (Só resolve quando necessário.)
    final defaultAccountId = (tx.accountId == null && tx.cardId == null)
        ? await _defaultAccountId()
        : null;
    final rows = buildInstallmentRows(tx, defaultAccountId: defaultAccountId);
    await _client.from('transactions').insert(rows);
  }

  /// F-3A: monta as linhas a inserir. Puro e testável (sem Supabase).
  ///
  /// - Sem parcelamento (`totalInstallments` null ou ≤ 1): 1 linha com o valor
  ///   cheio (comportamento atual preservado).
  /// - Parcelado (N > 1): N linhas, uma por mês. Split com **soma exata** — as
  ///   N-1 primeiras recebem o valor base (centavos truncados) e a **última
  ///   absorve o resto** para fechar o total (ex.: 100/3 → 33,33 + 33,33 +
  ///   33,34). Datas/campos inalterados; não toca trigger/saldo/cartão.
  static List<Map<String, dynamic>> buildInstallmentRows(
    Transaction tx, {
    String? defaultAccountId,
  }) {
    final n = tx.totalInstallments ?? 1;
    if (n <= 1) {
      return [
        withDefaultAccount(tx.toInsert(), defaultAccountId: defaultAccountId),
      ];
    }
    // Centavos inteiros evitam drift de float; a última parcela leva o resto.
    final totalCents = (tx.amount * 100).round();
    final baseCents = totalCents ~/ n;
    return List.generate(n, (i) {
      final cents = (i == n - 1) ? totalCents - baseCents * (n - 1) : baseCents;
      final d = DateTime(tx.date.year, tx.date.month + i, tx.date.day);
      final map = tx.toInsert();
      map['date'] = d.toIso8601String().substring(0, 10);
      map['installment_number'] = i + 1;
      map['amount'] = (cents / 100).toStringAsFixed(2);
      return withDefaultAccount(map, defaultAccountId: defaultAccountId);
    });
  }

  /// Conta default determinística para lançamentos sem conta/cartão: a conta
  /// BANCÁRIA mais antiga da família (menor `created_at`). Retorna null quando
  /// não há nenhuma conta bancária — nesse caso o lançamento fica sem conta,
  /// exatamente como antes (não quebra).
  Future<String?> _defaultAccountId() async {
    final rows = await _client
        .from('accounts_and_cards')
        .select('id')
        .eq('type', 'bank_account')
        .order('created_at', ascending: true)
        .limit(1);
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  /// Injeta a conta default no mapa de inserção quando a transação não tem
  /// conta nem cartão. Puro e testável: não altera nada se já houver
  /// `account_id`/`card_id`, ou se não houver default.
  static Map<String, dynamic> withDefaultAccount(
    Map<String, dynamic> row, {
    required String? defaultAccountId,
  }) {
    if (defaultAccountId != null &&
        row['account_id'] == null &&
        row['card_id'] == null) {
      return {...row, 'account_id': defaultAccountId};
    }
    return row;
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

  /// Transações de um cartão específico num período — insumo da tela de
  /// Faturas. Traz o nome do autor (users(name)) para exibir na linha.
  Future<List<Transaction>> byCard(
    String cardId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from('transactions')
        .select('*, users(name)')
        .eq('card_id', cardId)
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10))
        .order('date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map<Transaction>((r) => Transaction.fromJson(r)).toList();
  }

  /// Totais (receitas/despesas) de um mês qualquer — alimenta o resumo do topo
  /// das Movimentações quando a pessoa navega entre meses. RLS por family_id.
  Future<({double revenue, double expenses})> monthTotals(DateTime month) async {
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1, 0);
    final rows = await _client
        .from('transactions')
        .select('type, amount')
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10));
    double revenue = 0, expenses = 0;
    for (final r in rows) {
      final amount = (r['amount'] as num).toDouble();
      if (r['type'] == 'expense') {
        expenses += amount;
      } else {
        revenue += amount;
      }
    }
    return (revenue: revenue, expenses: expenses);
  }

  /// Gasto (despesa) do mês por autor — insumo da EQUIDADE no modo
  /// Compartilhado (quem pagou o quê). RLS por family_id. user_id → total.
  Future<Map<String, double>> monthExpenseByUser(DateTime month) async {
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1, 0);
    final rows = await _client
        .from('transactions')
        .select('user_id, amount')
        .eq('type', 'expense')
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10));
    final out = <String, double>{};
    for (final r in rows) {
      final uid = r['user_id'] as String?;
      if (uid == null) continue;
      out[uid] = (out[uid] ?? 0) + (r['amount'] as num).toDouble();
    }
    return out;
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
    final rows =
        await _client.rpc('daily_cash_flow', params: {'days_back': daysBack});
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
    return rows.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());
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

  Future<void> deleteRow(String id) => client.from(table).delete().eq('id', id);
}

class BudgetRepository extends _FamilyCrud<Budget> {
  BudgetRepository(SupabaseClient c) : super(c, 'budgets');

  @override
  Budget fromJson(Map<String, dynamic> json) => Budget.fromJson(json);
}

class RecurringRepository extends _FamilyCrud<RecurringTransaction> {
  RecurringRepository(SupabaseClient c) : super(c, 'recurring_transactions');

  @override
  RecurringTransaction fromJson(Map<String, dynamic> json) =>
      RecurringTransaction.fromJson(json);

  /// Ativa/desativa uma recorrência sem apagá-la (pausar sem perder histórico).
  Future<void> setActive(String id, bool active) =>
      updateRow(id, {'active': active});
}

class CategoryRepository extends _FamilyCrud<Category> {
  CategoryRepository(SupabaseClient c) : super(c, 'categories');

  @override
  Category fromJson(Map<String, dynamic> json) => Category.fromJson(json);

  Future<void> setArchived(String id, bool archived) =>
      updateRow(id, {'archived': archived});

  /// A categoria (por nome) está em uso em transações ou recorrentes? Usado
  /// para decidir apagar vs. arquivar.
  Future<bool> isInUse(String name) async {
    final tx = await client
        .from('transactions')
        .select('id')
        .eq('category', name)
        .limit(1);
    if ((tx as List).isNotEmpty) return true;
    final rec = await client
        .from('recurring_transactions')
        .select('id')
        .eq('category', name)
        .limit(1);
    return (rec as List).isNotEmpty;
  }

  /// Renomeia mantendo o histórico coerente: atualiza o NOME nas transações e
  /// recorrentes da família (o mordomo agrupa por nome). RLS escopa à família.
  Future<void> rename(String id, String oldName, String newName) async {
    await updateRow(id, {'name': newName});
    await client
        .from('transactions')
        .update({'category': newName}).eq('category', oldName);
    await client
        .from('recurring_transactions')
        .update({'category': newName}).eq('category', oldName);
  }
}

class AccountRepository extends _FamilyCrud<FinancialAccount> {
  AccountRepository(SupabaseClient c) : super(c, 'accounts_and_cards');

  @override
  FinancialAccount fromJson(Map<String, dynamic> json) =>
      FinancialAccount.fromJson(json);

  /// F-3B (Passo 2): as leituras de conta passam a usar o SALDO LIQUIDADO por
  /// data (`available`, da view `accounts_with_available` da migration 0006) em
  /// vez do saldo shadow imediato (`accounts_and_cards.balance`). As escritas
  /// (insert/update/delete) seguem na tabela base, herdadas de _FamilyCrud.
  @override
  Future<List<FinancialAccount>> all(
      {String orderBy = 'created_at', bool asc = false}) async {
    final rows = await client
        .from('accounts_with_available')
        .select()
        .order(orderBy, ascending: asc);
    return rows
        .map<FinancialAccount>(
            (r) => FinancialAccount.fromJson({...r, 'balance': r['available']}))
        .toList();
  }
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

  /// F-2: paga a bill. Se ela estiver vinculada a uma conta, gera uma despesa
  /// real nessa conta (o trigger de saldo age normalmente sobre a transação).
  /// Idempotente: o status só é transicionado de `pending`→`paid` uma vez, e a
  /// transação só é criada quando essa transição realmente acontece — pagar
  /// uma bill já paga é no-op (não duplica transação nem saldo).
  Future<void> markPaid(Bill bill) async {
    final flipped = await client
        .from(table)
        .update({'status': 'paid'})
        .eq('id', bill.id!)
        .eq('status', 'pending') // guard de idempotência (atômico)
        .select('id');
    if (flipped.isEmpty) return; // já estava paga

    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    final tx = billPaymentTransaction(bill, userId: userId);
    if (tx != null) {
      await client.from('transactions').insert(tx.toInsert());
    }
  }

  /// Constrói a despesa de uma bill paga vinculada a conta. Retorna null quando
  /// a bill não tem conta (nesse caso ela é só lembrete e nada é gravado).
  /// Puro e testável.
  static Transaction? billPaymentTransaction(
    Bill bill, {
    required String userId,
    DateTime? on,
  }) {
    if (bill.accountId == null) return null;
    return Transaction(
      familyId: bill.familyId,
      userId: userId,
      type: TransactionType.expense,
      amount: bill.amount,
      category: bill.category ?? 'Outros',
      description: bill.description,
      date: on ?? DateTime.now(),
      accountId: bill.accountId,
      tags: const ['conta-paga'],
    );
  }
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
final recurringRepositoryProvider =
    Provider((ref) => RecurringRepository(ref.watch(supabaseProvider)));
final categoryRepositoryProvider =
    Provider((ref) => CategoryRepository(ref.watch(supabaseProvider)));
final billRepositoryProvider =
    Provider((ref) => BillRepository(ref.watch(supabaseProvider)));
final debtRepositoryProvider =
    Provider((ref) => DebtRepository(ref.watch(supabaseProvider)));
final marketRepositoryProvider =
    Provider((ref) => MarketRepository(ref.watch(supabaseProvider)));
