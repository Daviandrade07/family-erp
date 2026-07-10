/// Domain models mirroring the Supabase schema.
library models;

double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String);

enum UserRole { admin, user, guest }

enum TransactionType { revenue, expense }

enum AccountType { bankAccount, creditCard, investment }

enum BillStatus { paid, pending }

enum BillRecurrence { none, monthly, yearly }

class Family {
  const Family({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final DateTime createdAt;

  factory Family.fromJson(Map<String, dynamic> j) => Family(
        id: j['id'],
        name: j['name'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

class AppUser {
  const AppUser({
    required this.id,
    this.familyId,
    required this.name,
    required this.email,
    required this.role,
    required this.active2fa,
    this.avatarUrl,
  });

  final String id;
  final String? familyId;
  final String name;
  final String email;
  final UserRole role;
  final bool active2fa;
  final String? avatarUrl;

  bool get isAdmin => role == UserRole.admin;
  bool get canWrite => role != UserRole.guest;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'],
        familyId: j['family_id'],
        name: j['name'],
        email: j['email'],
        role: UserRole.values.byName(j['role']),
        active2fa: j['active_2fa'] ?? false,
        avatarUrl: j['avatar_url'],
      );
}

class FinancialAccount {
  const FinancialAccount({
    required this.id,
    required this.familyId,
    required this.name,
    required this.type,
    required this.balance,
    this.creditLimit,
  });

  final String id;
  final String familyId;
  final String name;
  final AccountType type;
  final double balance;
  final double? creditLimit;

  factory FinancialAccount.fromJson(Map<String, dynamic> j) => FinancialAccount(
        id: j['id'],
        familyId: j['family_id'],
        name: j['name'],
        type: switch (j['type'] as String) {
          'bank_account' => AccountType.bankAccount,
          'credit_card' => AccountType.creditCard,
          _ => AccountType.investment,
        },
        balance: _num(j['balance']),
        creditLimit: j['credit_limit'] == null ? null : _num(j['credit_limit']),
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'name': name,
        'type': switch (type) {
          AccountType.bankAccount => 'bank_account',
          AccountType.creditCard => 'credit_card',
          AccountType.investment => 'investment',
        },
        'balance': balance,
        'credit_limit': creditLimit,
      };
}

class Transaction {
  const Transaction({
    this.id,
    required this.familyId,
    required this.userId,
    required this.type,
    required this.amount,
    required this.category,
    this.subcategory,
    this.description,
    this.receiptUrl,
    required this.date,
    this.paymentMethod,
    this.cardId,
    this.accountId,
    this.installmentNumber,
    this.totalInstallments,
    this.lat,
    this.lng,
    this.beneficiary,
    this.tags = const [],
    this.userName,
  });

  final String? id;
  final String familyId;
  final String userId;
  final TransactionType type;
  final double amount;
  final String category;
  final String? subcategory;
  final String? description;
  final String? receiptUrl;
  final DateTime date;
  final String? paymentMethod;
  final String? cardId;
  final String? accountId;
  final int? installmentNumber;
  final int? totalInstallments;
  final double? lat;
  final double? lng;
  final String? beneficiary;
  final List<String> tags;

  /// Joined from users table for display.
  final String? userName;

  bool get isExpense => type == TransactionType.expense;
  double get signedAmount => isExpense ? -amount : amount;

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'],
        familyId: j['family_id'],
        userId: j['user_id'],
        type: TransactionType.values.byName(j['type']),
        amount: _num(j['amount']),
        category: j['category'],
        subcategory: j['subcategory'],
        description: j['description'],
        receiptUrl: j['receipt_url'],
        date: DateTime.parse(j['date']),
        paymentMethod: j['payment_method'],
        cardId: j['card_id'],
        accountId: j['account_id'],
        installmentNumber: j['installment_number'],
        totalInstallments: j['total_installments'],
        lat: j['lat'] == null ? null : _num(j['lat']),
        lng: j['lng'] == null ? null : _num(j['lng']),
        beneficiary: j['beneficiary'],
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
        userName: (j['users'] as Map<String, dynamic>?)?['name'],
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'user_id': userId,
        'type': type.name,
        'amount': amount,
        'category': category,
        'subcategory': subcategory,
        'description': description,
        'receipt_url': receiptUrl,
        'date': date.toIso8601String().substring(0, 10),
        'payment_method': paymentMethod,
        'card_id': cardId,
        'account_id': accountId,
        'installment_number': installmentNumber,
        'total_installments': totalInstallments,
        'lat': lat,
        'lng': lng,
        'beneficiary': beneficiary,
        'tags': tags,
      };
}

class Budget {
  const Budget({
    this.id,
    required this.familyId,
    required this.category,
    required this.limitAmount,
    this.period = 'monthly',
  });

  final String? id;
  final String familyId;
  final String category;
  final double limitAmount;
  final String period;

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'],
        familyId: j['family_id'],
        category: j['category'],
        limitAmount: _num(j['limit_amount']),
        period: j['period'],
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'category': category,
        'limit_amount': limitAmount,
        'period': period,
      };
}

/// Server-computed budget usage row + client-side AI prediction.
class BudgetUsage {
  const BudgetUsage({
    required this.budgetId,
    required this.category,
    required this.limitAmount,
    required this.spent,
    required this.avgDailyHistory,
  });

  final String budgetId;
  final String category;
  final double limitAmount;
  final double spent;
  final double avgDailyHistory;

  double get usedRatio => limitAmount == 0 ? 0 : spent / limitAmount;

  factory BudgetUsage.fromJson(Map<String, dynamic> j) => BudgetUsage(
        budgetId: j['budget_id'],
        category: j['category'],
        limitAmount: _num(j['limit_amount']),
        spent: _num(j['spent']),
        avgDailyHistory: _num(j['avg_daily_history']),
      );
}

class PricePoint {
  const PricePoint({required this.price, required this.market, required this.date});

  final double price;
  final String market;
  final DateTime date;

  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
        price: _num(j['price']),
        market: j['market'] ?? 'unknown',
        date: _date(j['date']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'price': price,
        'market': market,
        'date': date.toIso8601String().substring(0, 10),
      };
}

class InventoryItem {
  const InventoryItem({
    this.id,
    required this.familyId,
    required this.productName,
    required this.quantity,
    required this.minQuantity,
    this.unit = 'un',
    this.expirationDate,
    this.location,
    this.category,
    this.priceHistory = const [],
  });

  final String? id;
  final String familyId;
  final String productName;
  final double quantity;
  final double minQuantity;
  final String unit;
  final DateTime? expirationDate;
  final String? location;
  final String? category;
  final List<PricePoint> priceHistory;

  bool get isLowStock => quantity <= minQuantity;

  /// null = no expiration; otherwise days remaining (negative = expired).
  int? get daysToExpire => expirationDate == null
      ? null
      : expirationDate!
          .difference(DateTime(DateTime.now().year, DateTime.now().month,
              DateTime.now().day))
          .inDays;

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'],
        familyId: j['family_id'],
        productName: j['product_name'],
        quantity: _num(j['quantity']),
        minQuantity: _num(j['min_quantity']),
        unit: j['unit'] ?? 'un',
        expirationDate: _date(j['expiration_date']),
        location: j['location'],
        category: j['category'],
        priceHistory: (j['price_history'] as List? ?? [])
            .map((e) => PricePoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'product_name': productName,
        'quantity': quantity,
        'min_quantity': minQuantity,
        'unit': unit,
        'expiration_date':
            expirationDate?.toIso8601String().substring(0, 10),
        'location': location,
        'category': category,
        'price_history': priceHistory.map((p) => p.toJson()).toList(),
      };
}

class ShoppingItem {
  const ShoppingItem({
    this.id,
    required this.familyId,
    required this.itemName,
    required this.quantity,
    this.status = 'pending',
    this.executionData = const {},
    this.inventoryId,
  });

  final String? id;
  final String familyId;
  final String itemName;
  final double quantity;
  final String status;
  final Map<String, dynamic> executionData;
  final String? inventoryId;

  bool get isBought => status == 'bought';
  bool get isAutoGenerated => executionData['auto_generated'] == true;

  factory ShoppingItem.fromJson(Map<String, dynamic> j) => ShoppingItem(
        id: j['id'],
        familyId: j['family_id'],
        itemName: j['item_name'],
        quantity: _num(j['quantity']),
        status: j['status'],
        executionData:
            Map<String, dynamic>.from(j['execution_data'] ?? const {}),
        inventoryId: j['inventory_id'],
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'item_name': itemName,
        'quantity': quantity,
        'status': status,
        'execution_data': executionData,
        'inventory_id': inventoryId,
      };
}

class MealPlan {
  const MealPlan({
    this.id,
    required this.familyId,
    required this.weekStart,
    required this.menuData,
  });

  final String? id;
  final String familyId;
  final DateTime weekStart;

  /// `{ "monday": {"lunch": "...", "dinner": "..."}, ... }`
  final Map<String, dynamic> menuData;

  factory MealPlan.fromJson(Map<String, dynamic> j) => MealPlan(
        id: j['id'],
        familyId: j['family_id'],
        weekStart: DateTime.parse(j['week_start']),
        menuData: Map<String, dynamic>.from(j['menu_data'] ?? const {}),
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'week_start': weekStart.toIso8601String().substring(0, 10),
        'menu_data': menuData,
      };
}

class FinancialGoal {
  const FinancialGoal({
    this.id,
    required this.familyId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    this.deadline,
  });

  final String? id;
  final String familyId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? deadline;

  double get progress =>
      targetAmount == 0 ? 0 : (currentAmount / targetAmount).clamp(0, 1);

  factory FinancialGoal.fromJson(Map<String, dynamic> j) => FinancialGoal(
        id: j['id'],
        familyId: j['family_id'],
        name: j['name'],
        targetAmount: _num(j['target_amount']),
        currentAmount: _num(j['current_amount']),
        deadline: _date(j['deadline']),
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'name': name,
        'target_amount': targetAmount,
        'current_amount': currentAmount,
        'deadline': deadline?.toIso8601String().substring(0, 10),
      };
}

/// Prioridade de contas e dívidas — definida pelo usuário, nunca alterada
/// automaticamente pela IA.
enum BillPriority { muitoAlta, alta, media, baixa }

const _priorityWire = {
  BillPriority.muitoAlta: 'muito_alta',
  BillPriority.alta: 'alta',
  BillPriority.media: 'media',
  BillPriority.baixa: 'baixa',
};

BillPriority priorityFromWire(String? v) => _priorityWire.entries
    .firstWhere((e) => e.value == v,
        orElse: () => const MapEntry(BillPriority.media, 'media'))
    .key;

extension BillPriorityX on BillPriority {
  String get wire => _priorityWire[this]!;
  String get labelPt => switch (this) {
        BillPriority.muitoAlta => 'Muito alta',
        BillPriority.alta => 'Alta',
        BillPriority.media => 'Média',
        BillPriority.baixa => 'Baixa',
      };
}

class Bill {
  const Bill({
    this.id,
    required this.familyId,
    required this.description,
    required this.amount,
    required this.dueDate,
    this.status = BillStatus.pending,
    this.recurrence = BillRecurrence.none,
    this.priority = BillPriority.media,
    this.category,
    this.paymentMethod,
    this.notes,
  });

  final String? id;
  final String familyId;
  final String description;
  final double amount;
  final DateTime dueDate;
  final BillStatus status;
  final BillRecurrence recurrence;
  final BillPriority priority;
  final String? category;
  final String? paymentMethod;
  final String? notes;

  bool get isOverdue =>
      status == BillStatus.pending &&
      dueDate.isBefore(DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day));

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: j['id'],
        familyId: j['family_id'],
        description: j['description'],
        amount: _num(j['amount']),
        dueDate: DateTime.parse(j['due_date']),
        status: BillStatus.values.byName(j['status']),
        recurrence: BillRecurrence.values.byName(j['recurrence']),
        priority: priorityFromWire(j['priority'] as String?),
        category: j['category'],
        paymentMethod: j['payment_method'],
        notes: j['notes'],
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'description': description,
        'amount': amount,
        'due_date': dueDate.toIso8601String().substring(0, 10),
        'status': status.name,
        'recurrence': recurrence.name,
        'priority': priority.wire,
        'category': category,
        'payment_method': paymentMethod,
        'notes': notes,
      };
}

class Debt {
  const Debt({
    this.id,
    required this.familyId,
    required this.creditor,
    this.description,
    required this.originalAmount,
    required this.remainingAmount,
    this.installments,
    this.interestRate,
    this.priority = BillPriority.media,
  });

  final String? id;
  final String familyId;
  final String creditor;
  final String? description;
  final double originalAmount;
  final double remainingAmount;
  final int? installments;

  /// Juros em % ao mês.
  final double? interestRate;
  final BillPriority priority;

  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
        id: j['id'],
        familyId: j['family_id'],
        creditor: j['creditor'],
        description: j['description'],
        originalAmount: _num(j['original_amount']),
        remainingAmount: _num(j['remaining_amount']),
        installments: j['installments'],
        interestRate:
            j['interest_rate'] == null ? null : _num(j['interest_rate']),
        priority: priorityFromWire(j['priority'] as String?),
      );

  Map<String, dynamic> toInsert() => {
        'family_id': familyId,
        'creditor': creditor,
        'description': description,
        'original_amount': originalAmount,
        'remaining_amount': remainingAmount,
        'installments': installments,
        'interest_rate': interestRate,
        'priority': priority.wire,
      };
}

/// Categorias de contas da casa.
class BillCategories {
  static const all = [
    'Água', 'Energia', 'Internet', 'Telefone', 'Mercado', 'Combustível',
    'Farmácia', 'Saúde', 'Educação', 'Moradia', 'Aluguel', 'Financiamentos',
    'Cartão', 'Empréstimos', 'Lazer', 'Outros',
  ];
}

class Market {
  const Market({
    required this.id,
    required this.name,
    this.cnpj,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final String? cnpj;
  final double lat;
  final double lng;

  factory Market.fromJson(Map<String, dynamic> j) => Market(
        id: j['id'],
        name: j['name'],
        cnpj: j['cnpj'],
        lat: _num(j['lat']),
        lng: _num(j['lng']),
      );
}

class DashboardKpis {
  const DashboardKpis({
    required this.totalBalance,
    required this.netWorth,
    required this.billsPending,
    required this.billsOverdue,
    required this.monthExpenses,
    required this.monthRevenue,
  });

  final double totalBalance;
  final double netWorth;
  final double billsPending;
  final double billsOverdue;
  final double monthExpenses;
  final double monthRevenue;

  factory DashboardKpis.fromJson(Map<String, dynamic> j) => DashboardKpis(
        totalBalance: _num(j['total_balance']),
        netWorth: _num(j['net_worth']),
        billsPending: _num(j['bills_pending']),
        billsOverdue: _num(j['bills_overdue']),
        monthExpenses: _num(j['month_expenses']),
        monthRevenue: _num(j['month_revenue']),
      );

  static const empty = DashboardKpis(
    totalBalance: 0,
    netWorth: 0,
    billsPending: 0,
    billsOverdue: 0,
    monthExpenses: 0,
    monthRevenue: 0,
  );
}

/// Resumo dos últimos 7 dias (card "sua semana em números").
class WeekSummary {
  const WeekSummary({
    required this.expenses,
    required this.revenue,
    required this.previousExpenses,
    required this.topCategory,
    required this.topCategoryTotal,
  });

  final double expenses;
  final double revenue;
  final double previousExpenses;
  final String? topCategory;
  final double topCategoryTotal;

  double get balance => revenue - expenses;

  /// Variação % dos gastos vs. a semana anterior (null se não há base).
  double? get expenseChange {
    if (previousExpenses <= 0) return null;
    return (expenses - previousExpenses) / previousExpenses;
  }

  bool get isEmpty => expenses == 0 && revenue == 0;
}

class DailyFlow {
  const DailyFlow({required this.day, required this.revenue, required this.expense});

  final DateTime day;
  final double revenue;
  final double expense;

  factory DailyFlow.fromJson(Map<String, dynamic> j) => DailyFlow(
        day: DateTime.parse(j['day']),
        revenue: _num(j['revenue']),
        expense: _num(j['expense']),
      );
}

class CategorySpend {
  const CategorySpend({required this.category, required this.total});

  final String category;
  final double total;

  factory CategorySpend.fromJson(Map<String, dynamic> j) =>
      CategorySpend(category: j['category'], total: _num(j['total']));
}

/// Default expense/revenue categories used across the app.
class Categories {
  static const expense = [
    'Alimentação', 'Mercado', 'Moradia', 'Transporte', 'Saúde',
    'Educação', 'Lazer', 'Vestuário', 'Assinaturas', 'Pets', 'Outros',
  ];

  static const revenue = [
    'Salário', 'Freelance', 'Investimentos', 'Aluguel', 'Outros',
  ];
}
