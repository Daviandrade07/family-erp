import 'package:family_erp/services/ai/write_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Bloco F — suíte permanente da SEGURANÇA da IA (Sprint Fundação da Confiança).
/// Trava as garantias: nunca inventar (guardas), confirmar quando há
/// inferência/ambiguidade/risco, e nunca vazar erro técnico.
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('flexibleDate — nunca lança', () {
    test('aceita ISO', () {
      expect(flexibleDate('2026-08-15'), DateTime(2026, 8, 15));
    });
    test('aceita dd/MM/yyyy e dd-MM-yyyy', () {
      expect(flexibleDate('15/08/2026'), DateTime(2026, 8, 15));
      expect(flexibleDate('15-08-2026'), DateTime(2026, 8, 15));
    });
    test('data inválida vira null, não exceção', () {
      expect(flexibleDate('ontem'), isNull);
      expect(flexibleDate('35/13/2026'), isNull);
      expect(flexibleDate(''), isNull);
      expect(flexibleDate(null), isNull);
    });
  });

  group('realMarket — guarda anti-preço-inventado', () {
    test('mercado real é aceito', () {
      expect(realMarket('GoodBom'), isTrue);
    });
    test('vazio/unknown/n-a são rejeitados', () {
      expect(realMarket(null), isFalse);
      expect(realMarket(''), isFalse);
      expect(realMarket('unknown'), isFalse);
      expect(realMarket('desconhecido'), isFalse);
    });
  });

  group('isKnownCategory', () {
    test('reconhece a taxonomia canônica', () {
      expect(isKnownCategory('Mercado', expense: true), isTrue);
      expect(isKnownCategory('Salário', expense: false), isTrue);
    });
    test('rejeita categoria inventada', () {
      expect(isKnownCategory('Churrasco', expense: true), isFalse);
      expect(isKnownCategory(null, expense: true), isFalse);
    });
  });

  group('confirmationFor — só inferência ou ambiguidade (sem limite de valor)',
      () {
    test('gasto claro NÃO confirma', () {
      final c = confirmationFor('add_transaction', {
        'type': 'expense',
        'amount': 50,
        'description': 'pão',
        'category': 'Mercado',
      });
      expect(c, isNull);
    });

    test('valor alto sozinho NÃO confirma (sem limite arbitrário)', () {
      final c = confirmationFor('add_transaction', {
        'type': 'expense',
        'amount': 5000,
        'category': 'Mercado',
      });
      expect(c, isNull);
    });

    test('categoria não reconhecida confirma, com campo escolha vazio + hint',
        () {
      final c = confirmationFor('add_transaction', {
        'type': 'expense',
        'amount': 50,
        'category': 'Churrasco',
      });
      expect(c, isNotNull);
      final cat = c!.fields.firstWhere((f) => f.key == 'category');
      expect(cat.kind, ConfirmFieldKind.choice);
      expect(cat.value, isEmpty); // não pré-seleciona palpite
      expect(cat.hint, isNotNull); // pergunta natural, sem jargão
    });

    test('data ambígua confirma, com campo de data vazio', () {
      final c = confirmationFor('add_transaction', {
        'type': 'expense',
        'amount': 30,
        'category': 'Mercado',
        'date': 'semana passada',
      });
      expect(c, isNotNull);
      final date = c!.fields.firstWhere((f) => f.key == 'date');
      expect(date.value, isEmpty);
    });

    test('conta a pagar sempre confirma; campos editáveis presentes', () {
      final c = confirmationFor('add_bill', {
        'description': 'Luz',
        'amount': 120,
        'due_date': 'qualquer coisa',
      });
      expect(c, isNotNull);
      final due = c!.fields.firstWhere((f) => f.key == 'due_date');
      expect(due.kind, ConfirmFieldKind.date);
      expect(due.value, isEmpty); // data que não deu para entender fica vazia
    });

    test('dívida sempre confirma', () {
      final c = confirmationFor('add_debt', {
        'creditor': 'Loja X',
        'original_amount': 300,
      });
      expect(c, isNotNull);
      expect(c!.understood, contains('Loja X'));
    });

    test('leitura e despensa não pedem confirmação', () {
      expect(confirmationFor('get_financial_overview', {}), isNull);
      expect(
          confirmationFor('add_pantry_items', {
            'items': [
              {'name': 'arroz'}
            ]
          }),
          isNull);
    });

    test('nenhum campo do card expõe jargão interno', () {
      final c = confirmationFor('add_transaction', {
        'type': 'expense',
        'amount': 50,
        'category': 'Churrasco',
      })!;
      final blob = (c.understood +
              c.title +
              c.fields.map((f) => '${f.label} ${f.hint ?? ''}').join(' '))
          .toLowerCase();
      expect(blob, isNot(contains('taxonomia')));
      expect(blob, isNot(contains('categoria fora')));
      expect(blob, isNot(contains('inferência')));
    });
  });

  group('humanizeError — nunca vaza técnico', () {
    test('erro de rede vira mensagem de conexão', () {
      final msg = humanizeError(Exception('SocketException: failed host lookup'));
      expect(msg.toLowerCase(), contains('conexão'));
    });

    test('erro genérico não expõe detalhe técnico', () {
      final msg = humanizeError(const FormatException('Invalid date 2026-13-40'));
      expect(msg, isNot(contains('FormatException')));
      expect(msg, isNot(contains('2026-13-40')));
      expect(msg.trim(), isNotEmpty);
    });
  });
}
