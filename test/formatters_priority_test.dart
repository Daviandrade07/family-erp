import 'package:kinfin/core/utils/formatters.dart';
import 'package:kinfin/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// T8 — Formatadores de exibição + mapeamento de prioridade (wire).
///
/// `brl`/`brlCompact` usam NumberFormat pt-BR (dados numéricos embutidos no
/// intl — não exige initializeDateFormatting). As asserções usam `contains`
/// para não depender de espaço normal vs. não-quebrável. `pct` é string pura.
void main() {
  group('MoneyFormat.brl', () {
    test('formats with pt-BR grouping (.) and decimal (,)', () {
      final s = 1234.56.brl;
      expect(s, contains(r'R$'));
      expect(s, contains('1.234,56'));
    });

    test('always shows two decimals, including zero', () {
      expect(0.brl, contains('0,00'));
    });
  });

  group('MoneyFormat.brlCompact', () {
    test('returns a non-empty currency string', () {
      final s = 1200.brlCompact;
      expect(s, contains(r'R$'));
      expect(s, isNotEmpty);
    });
  });

  group('MoneyFormat.pct', () {
    test('rounds a ratio to a whole percentage', () {
      expect(0.1234.pct, '12%');
      expect(0.5.pct, '50%');
      expect(1.pct, '100%');
      expect(0.pct, '0%');
    });

    test('keeps the sign for negative ratios', () {
      expect((-0.05).pct, '-5%');
    });
  });

  group('BillPriority.wire', () {
    test('maps every priority to its snake_case wire value', () {
      expect(BillPriority.muitoAlta.wire, 'muito_alta');
      expect(BillPriority.alta.wire, 'alta');
      expect(BillPriority.media.wire, 'media');
      expect(BillPriority.baixa.wire, 'baixa');
    });
  });

  group('priorityFromWire', () {
    test('is the inverse of wire for known values', () {
      expect(priorityFromWire('muito_alta'), BillPriority.muitoAlta);
      expect(priorityFromWire('alta'), BillPriority.alta);
      expect(priorityFromWire('media'), BillPriority.media);
      expect(priorityFromWire('baixa'), BillPriority.baixa);
    });

    test('defaults to media for unknown or null input', () {
      expect(priorityFromWire('inexistente'), BillPriority.media);
      expect(priorityFromWire(null), BillPriority.media);
    });
  });
}
