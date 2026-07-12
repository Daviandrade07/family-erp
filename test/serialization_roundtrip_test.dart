import 'package:kinfin/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// T7 — Round-trip de serialização dos modelos que espelham o banco.
///
/// Garante o contrato com o JSON do Supabase: `fromJson` interpreta o shape
/// vindo do banco (snake_case, enums como string, aninhados) e `toInsert`
/// devolve exatamente as chaves/valores que o banco espera. Puro: sem rede.
void main() {
  group('Transaction serialization', () {
    final dbJson = {
      'id': 'tx-1',
      'family_id': 'fam-1',
      'user_id': 'user-1',
      'type': 'expense',
      'amount': 12.5,
      'category': 'Mercado',
      'subcategory': 'Hortifruti',
      'description': 'Compra da semana',
      'receipt_url': null,
      'date': '2026-01-15',
      'payment_method': 'pix',
      'card_id': null,
      'account_id': 'acc-1',
      'installment_number': null,
      'total_installments': null,
      'lat': null,
      'lng': null,
      'beneficiary': 'GoodBom',
      'tags': ['essencial', 'mensal'],
      'users': {'name': 'Davi'},
    };

    test('fromJson parses type, amount, tags and joined user name', () {
      final tx = Transaction.fromJson(dbJson);
      expect(tx.type, TransactionType.expense);
      expect(tx.amount, 12.5);
      expect(tx.category, 'Mercado');
      expect(tx.tags, ['essencial', 'mensal']);
      expect(tx.userName, 'Davi');
      expect(tx.date, DateTime(2026, 1, 15));
    });

    test('toInsert emits wire keys and omits id', () {
      final ins = Transaction.fromJson(dbJson).toInsert();
      expect(ins['type'], 'expense');
      expect(ins['amount'], 12.5);
      expect(ins['date'], '2026-01-15');
      expect(ins['account_id'], 'acc-1');
      expect(ins['tags'], ['essencial', 'mensal']);
      expect(ins.containsKey('id'), isFalse);
    });

    test('revenue type round-trips to the "revenue" wire value', () {
      final ins = Transaction.fromJson({...dbJson, 'type': 'revenue'}).toInsert();
      expect(ins['type'], 'revenue');
    });
  });

  group('Bill serialization', () {
    final dbJson = {
      'id': 'bill-1',
      'family_id': 'fam-1',
      'description': 'Conta de luz',
      'amount': 120.0,
      'due_date': '2026-02-10',
      'status': 'pending',
      'recurrence': 'monthly',
      'priority': 'muito_alta',
      'category': 'Energia',
      'payment_method': null,
      'notes': null,
    };

    test('fromJson parses status, recurrence and priority enums', () {
      final bill = Bill.fromJson(dbJson);
      expect(bill.status, BillStatus.pending);
      expect(bill.recurrence, BillRecurrence.monthly);
      expect(bill.priority, BillPriority.muitoAlta);
      expect(bill.dueDate, DateTime(2026, 2, 10));
    });

    test('toInsert emits snake_case priority and date-only due_date', () {
      final ins = Bill.fromJson(dbJson).toInsert();
      expect(ins['status'], 'pending');
      expect(ins['recurrence'], 'monthly');
      expect(ins['priority'], 'muito_alta');
      expect(ins['due_date'], '2026-02-10');
    });
  });

  group('InventoryItem serialization (with nested price history)', () {
    final dbJson = {
      'id': 'inv-1',
      'family_id': 'fam-1',
      'product_name': 'Arroz 5kg',
      'quantity': 2.0,
      'min_quantity': 1.0,
      'unit': 'un',
      'expiration_date': '2026-03-01',
      'location': 'Despensa',
      'category': 'Grãos',
      'price_history': [
        {'price': 24.9, 'market': 'GoodBom', 'date': '2026-01-01'},
      ],
    };

    test('fromJson parses fields and nested price points', () {
      final item = InventoryItem.fromJson(dbJson);
      expect(item.productName, 'Arroz 5kg');
      expect(item.quantity, 2.0);
      expect(item.priceHistory, hasLength(1));
      expect(item.priceHistory.first.price, 24.9);
      expect(item.priceHistory.first.market, 'GoodBom');
    });

    test('toInsert serializes the nested price history back to JSON', () {
      final ins = InventoryItem.fromJson(dbJson).toInsert();
      expect(ins['expiration_date'], '2026-03-01');
      final history = ins['price_history'] as List;
      expect(history, hasLength(1));
      expect((history.first as Map)['price'], 24.9);
      expect((history.first as Map)['date'], '2026-01-01');
    });
  });

  group('AppUser role helpers from JSON', () {
    AppUser fromRole(String role) => AppUser.fromJson({
          'id': 'u-1',
          'family_id': 'fam-1',
          'name': 'Davi',
          'email': 'davi@example.com',
          'role': role,
          'active_2fa': false,
        });

    test('admin can write and is admin', () {
      final admin = fromRole('admin');
      expect(admin.isAdmin, isTrue);
      expect(admin.canWrite, isTrue);
    });

    test('user can write but is not admin', () {
      final user = fromRole('user');
      expect(user.isAdmin, isFalse);
      expect(user.canWrite, isTrue);
    });

    test('guest is read-only', () {
      final guest = fromRole('guest');
      expect(guest.isAdmin, isFalse);
      expect(guest.canWrite, isFalse);
    });
  });
}
