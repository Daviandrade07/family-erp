import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _compactCurrency =
    NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$');
final _date = DateFormat('dd/MM/yyyy', 'pt_BR');
final _dayMonth = DateFormat('dd MMM', 'pt_BR');
final _monthYear = DateFormat('MMMM yyyy', 'pt_BR');

extension MoneyFormat on num {
  String get brl => _currency.format(this);
  String get brlCompact => _compactCurrency.format(this);
  String get pct => '${(this * 100).toStringAsFixed(0)}%';
}

extension DateFormatX on DateTime {
  String get br => _date.format(this);
  String get dayMonth => _dayMonth.format(this);
  String get monthYear => _monthYear.format(this);

  DateTime get dateOnly => DateTime(year, month, day);

  int get daysUntil => dateOnly.difference(DateTime.now().dateOnly).inDays;

  DateTime get startOfMonth => DateTime(year, month, 1);
  DateTime get endOfMonth => DateTime(year, month + 1, 0);
  DateTime get startOfWeek => dateOnly.subtract(Duration(days: weekday - 1));
}

const weekdayLabelsPt = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
