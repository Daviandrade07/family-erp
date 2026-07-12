import 'package:flutter_test/flutter_test.dart';
import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/services/categories/category_rules.dart';

Category cat(String name, TransactionType type,
        {String? id, bool archived = false, bool isDefault = false}) =>
    Category(
        id: id ?? name,
        name: name,
        type: type,
        archived: archived,
        isDefault: isDefault);

void main() {
  final base = [
    cat('Mercado', TransactionType.expense, isDefault: true),
    cat('Salário', TransactionType.revenue, isDefault: true),
    cat('Padaria', TransactionType.expense, id: 'p1'),
    cat('Antiga', TransactionType.expense, id: 'a1', archived: true),
  ];

  group('categoryNameAvailable', () {
    test('nome novo é disponível', () {
      expect(
          categoryNameAvailable('Farmácia', TransactionType.expense, base),
          isTrue);
    });

    test('duplicado ATIVO (case-insensitive) não é disponível', () {
      expect(categoryNameAvailable('mercado', TransactionType.expense, base),
          isFalse);
    });

    test('mesmo nome em TIPO diferente é disponível', () {
      expect(categoryNameAvailable('Mercado', TransactionType.revenue, base),
          isTrue);
    });

    test('nome de categoria ARQUIVADA pode ser reutilizado', () {
      expect(
          categoryNameAvailable('Antiga', TransactionType.expense, base)
              // 'Antiga' arquivada não bloqueia (case-insensitive test):
              ,
          isTrue);
    });

    test('editar a própria não conflita consigo mesma', () {
      expect(
          categoryNameAvailable('Padaria', TransactionType.expense, base,
              excludingId: 'p1'),
          isTrue);
    });

    test('nome vazio nunca é válido', () {
      expect(categoryNameAvailable('   ', TransactionType.expense, base),
          isFalse);
    });
  });

  group('canDeleteCategory', () {
    test('padrão não pode ser apagada', () {
      final c = cat('Mercado', TransactionType.expense, isDefault: true);
      expect(canDeleteCategory(c, inUse: false), isFalse);
    });

    test('customizada em uso não pode ser apagada (arquive)', () {
      final c = cat('Padaria', TransactionType.expense);
      expect(canDeleteCategory(c, inUse: true), isFalse);
    });

    test('customizada sem uso pode ser apagada', () {
      final c = cat('Padaria', TransactionType.expense);
      expect(canDeleteCategory(c, inUse: false), isTrue);
    });
  });

  group('canArchiveCategory', () {
    test('padrão não pode ser arquivada', () {
      expect(
          canArchiveCategory(
              cat('Mercado', TransactionType.expense, isDefault: true)),
          isFalse);
    });

    test('customizada pode ser arquivada', () {
      expect(canArchiveCategory(cat('Padaria', TransactionType.expense)),
          isTrue);
    });
  });
}
