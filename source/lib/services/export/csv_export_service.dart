import '../../data/models/models.dart';

/// Gera arquivos CSV a partir dos dados da família (transações e contas).
///
/// Mata a maior trava dos concorrentes (ex.: Cozi), onde o usuário "não
/// consegue levar seus dados embora". Aqui os dados são sempre exportáveis.
class CsvExportService {
  /// Escapa um campo para CSV (aspas, vírgulas e quebras de linha).
  static String _cell(Object? value) {
    final s = (value ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> cells) =>
      cells.map(_cell).join(',');

  static String _date(DateTime d) => d.toIso8601String().substring(0, 10);

  static String _amount(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  /// Planilha de transações (receitas e despesas).
  String transactions(List<Transaction> txs) {
    final buffer = StringBuffer()
      ..writeln(_row([
        'Data',
        'Tipo',
        'Valor',
        'Categoria',
        'Subcategoria',
        'Descrição',
        'Beneficiário',
        'Forma de pagamento',
        'Responsável',
      ]));
    for (final t in txs) {
      buffer.writeln(_row([
        _date(t.date),
        t.isExpense ? 'Despesa' : 'Receita',
        _amount(t.amount),
        t.category,
        t.subcategory ?? '',
        t.description ?? '',
        t.beneficiary ?? '',
        t.paymentMethod ?? '',
        t.userName ?? '',
      ]));
    }
    return buffer.toString();
  }

  /// Planilha de contas a pagar.
  String bills(List<Bill> bills) {
    final buffer = StringBuffer()
      ..writeln(_row([
        'Descrição',
        'Valor',
        'Vencimento',
        'Situação',
        'Prioridade',
        'Categoria',
        'Recorrência',
      ]));
    for (final b in bills) {
      buffer.writeln(_row([
        b.description,
        _amount(b.amount),
        _date(b.dueDate),
        b.status == BillStatus.paid ? 'Paga' : 'Pendente',
        b.priority.wire,
        b.category ?? '',
        b.recurrence.name,
      ]));
    }
    return buffer.toString();
  }
}

final csvExportService = CsvExportService();
