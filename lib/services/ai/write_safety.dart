import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';

/// Camada de SEGURANÇA das gravações da IA (Sprint Fundação da Confiança).
///
/// Tudo aqui é PURO e determinístico — sem I/O, sem LLM — para poder ser
/// coberto por testes permanentes (Bloco F). Garante que a IA nunca grave
/// dado inventado: datas viram parse tolerante (nunca crash), preço sem
/// mercado real é descartado, e ações com inferência/ambiguidade/risco pedem
/// confirmação humana antes de tocar no banco.

/// Parser tolerante de datas vindas do modelo. NUNCA lança: retorna null quando
/// não entende (o chamador decide o fallback humano). Aceita ISO (YYYY-MM-DD),
/// dd/MM/yyyy e dd-MM-yyyy.
DateTime? flexibleDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;

  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      final d = DateTime(year, month, day);
      if (d.year == year && d.month == month && d.day == day) return d;
    }
  }
  return null;
}

/// Coerção numérica tolerante (modelos abertos mandam "45,80" como texto).
double? asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

/// Um mercado "real" é uma string preenchida e diferente de placeholders.
/// Preço sem mercado real = provavelmente inventado pelo modelo → não vira
/// histórico de preço.
bool realMarket(dynamic market) {
  final s = (market is String) ? market.trim().toLowerCase() : '';
  return s.isNotEmpty && s != 'unknown' && s != 'desconhecido' && s != 'n/a';
}

/// Categoria de despesa/receita dentro da taxonomia canônica do app?
bool isKnownCategory(String? category, {required bool expense}) {
  if (category == null) return false;
  final list = expense ? Categories.expense : Categories.revenue;
  return list.contains(category);
}

// ==========================================================
// Confirmação inteligente
// ==========================================================

/// Tipo de editor do campo no card — para permitir CORREÇÃO direta (o usuário
/// ajusta o que a IA entendeu, sem uma interação a mais).
enum ConfirmFieldKind { text, money, integer, date, choice }

class ConfirmField {
  const ConfirmField({
    required this.key,
    required this.label,
    required this.kind,
    this.value = '',
    this.options,
    this.hint,
  });

  /// Chave do input da ferramenta que este campo corrige (ex.: 'amount').
  final String key;
  final String label;
  final ConfirmFieldKind kind;

  /// Valor inicial em texto (money: "80.00"; date: "2026-08-15"; choice: opção).
  final String value;

  /// Opções para [ConfirmFieldKind.choice] (ex.: categorias).
  final List<String>? options;

  /// Pergunta/placeholder natural quando o campo está vazio — SEM jargão
  /// interno (ex.: "Em qual categoria você quer colocar essa compra?").
  final String? hint;
}

/// Resumo editável que o card de confirmação mostra: o que a IA ENTENDEU +
/// campos corrigíveis. O usuário ajusta e confirma antes de qualquer gravação.
class WriteConfirmation {
  const WriteConfirmation({
    required this.tool,
    required this.understood,
    required this.title,
    required this.fields,
  });

  final String tool;
  final String understood;
  final String title;
  final List<ConfirmField> fields;
}

/// Decide se uma gravação precisa de confirmação humana. Retorna null quando a
/// ação é CLARA (sem inferência nem ambiguidade) e pode ser executada direto —
/// confirmação inteligente, nunca por limite de valor. Puro e testável.
WriteConfirmation? confirmationFor(String tool, Map<String, dynamic> input) {
  switch (tool) {
    case 'add_transaction':
      return _confirmTransaction(input);
    case 'add_bill':
      return _confirmBill(input);
    case 'add_debt':
      return _confirmDebt(input);
    default:
      return null; // leituras e ações reversíveis não pedem confirmação
  }
}

String _money(double? v) => v == null ? '' : v.toStringAsFixed(2);
String _iso(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);

WriteConfirmation? _confirmTransaction(Map<String, dynamic> input) {
  final expense = (input['type'] ?? 'expense') != 'revenue';
  final amount = asNum(input['amount']);
  final category = input['category'] as String?;
  final desc = (input['description'] as String?)?.trim();
  final rawDate = input['date'];
  final categoryOk = isKnownCategory(category, expense: expense);
  final dateOk = rawDate == null || flexibleDate(rawDate) != null;

  // Só confirma quando há INFERÊNCIA (categoria que a IA não tem certeza) ou
  // AMBIGUIDADE (data que não deu para entender). Nada de limite de valor.
  if (categoryOk && dateOk) return null;

  return WriteConfirmation(
    tool: 'add_transaction',
    understood: 'Entendi que você quer registrar '
        '${expense ? 'um gasto' : 'uma entrada'}'
        '${amount != null ? ' de ${amount.brl}' : ''}'
        '${desc != null && desc.isNotEmpty ? ' com "$desc"' : ''}.',
    title: expense ? 'Confirma este gasto?' : 'Confirma esta entrada?',
    fields: [
      ConfirmField(
          key: 'amount', label: 'Valor', kind: ConfirmFieldKind.money,
          value: _money(amount)),
      ConfirmField(
          key: 'category',
          label: 'Categoria',
          kind: ConfirmFieldKind.choice,
          value: categoryOk ? category! : '',
          options: expense ? Categories.expense : Categories.revenue,
          hint: 'Em qual categoria você quer colocar?'),
      ConfirmField(
          key: 'description',
          label: 'Descrição',
          kind: ConfirmFieldKind.text,
          value: desc ?? '',
          hint: 'Opcional'),
      ConfirmField(
          key: 'date',
          label: 'Data',
          kind: ConfirmFieldKind.date,
          value: _iso(flexibleDate(rawDate)),
          hint: 'Deixe em branco para hoje'),
    ],
  );
}

WriteConfirmation? _confirmBill(Map<String, dynamic> input) {
  final amount = asNum(input['amount']);
  final desc = (input['description'] as String?)?.trim();
  final category = input['category'] as String?;
  final date = flexibleDate(input['due_date']);
  return WriteConfirmation(
    tool: 'add_bill',
    understood: 'Entendi que você quer cadastrar uma conta a pagar'
        '${amount != null ? ' de ${amount.brl}' : ''}'
        '${desc != null && desc.isNotEmpty ? ' ($desc)' : ''}.',
    title: 'Confirma esta conta a pagar?',
    fields: [
      ConfirmField(
          key: 'description', label: 'Conta', kind: ConfirmFieldKind.text,
          value: desc ?? '', hint: 'Ex.: Conta de luz'),
      ConfirmField(
          key: 'amount', label: 'Valor', kind: ConfirmFieldKind.money,
          value: _money(amount)),
      ConfirmField(
          key: 'due_date', label: 'Vencimento', kind: ConfirmFieldKind.date,
          value: _iso(date), hint: 'Quando vence?'),
      ConfirmField(
          key: 'category',
          label: 'Categoria',
          kind: ConfirmFieldKind.choice,
          value: (category != null && BillCategories.all.contains(category))
              ? category
              : '',
          options: BillCategories.all,
          hint: 'Opcional'),
    ],
  );
}

WriteConfirmation? _confirmDebt(Map<String, dynamic> input) {
  final creditor = (input['creditor'] as String?)?.trim();
  final original = asNum(input['original_amount']);
  final remaining = asNum(input['remaining_amount']);
  final installments = asNum(input['installments'])?.round();
  return WriteConfirmation(
    tool: 'add_debt',
    understood: 'Entendi que você quer registrar uma dívida'
        '${original != null ? ' de ${original.brl}' : ''}'
        '${creditor != null && creditor.isNotEmpty ? ' com $creditor' : ''}.',
    title: 'Confirma esta dívida?',
    fields: [
      ConfirmField(
          key: 'creditor', label: 'Para quem', kind: ConfirmFieldKind.text,
          value: creditor ?? '', hint: 'Loja ou pessoa'),
      ConfirmField(
          key: 'original_amount', label: 'Valor', kind: ConfirmFieldKind.money,
          value: _money(original)),
      ConfirmField(
          key: 'remaining_amount', label: 'Ainda deve',
          kind: ConfirmFieldKind.money, value: _money(remaining),
          hint: 'Deixe em branco se for o valor total'),
      ConfirmField(
          key: 'installments', label: 'Parcelas',
          kind: ConfirmFieldKind.integer,
          value: installments?.toString() ?? '', hint: 'Opcional'),
    ],
  );
}

// ==========================================================
// Humanização de erros
// ==========================================================

/// Converte qualquer exceção numa frase humana. NUNCA expõe detalhe técnico
/// (FormatException, DateTime, JSON, stack, nome de ferramenta) — isso vai só
/// para o log. Use no limite entre serviço e UI.
String humanizeError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('socket') ||
      s.contains('connection') ||
      s.contains('timeout') ||
      s.contains('failed host') ||
      s.contains('network')) {
    return 'A conexão parece instável. Verifique a internet e tente de novo.';
  }
  if (s.contains('429') || s.contains('rate') || s.contains('limite')) {
    return 'Recebi muitos pedidos em pouco tempo. Aguarde alguns segundos e tente de novo.';
  }
  if (s.contains('família') || s.contains('familia')) {
    return 'Preciso que sua família esteja configurada para registrar isso.';
  }
  return 'Algo não saiu como esperado agora. Pode tentar de novo em instantes?';
}
