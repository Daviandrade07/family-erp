import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import 'budget_prediction_agent.dart';
import 'shopping_recommender.dart';

/// Structured payloads the chat can render inline.
class ChatTable {
  const ChatTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

class ChatChartPoint {
  const ChatChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

class ChatMessage {
  const ChatMessage({
    required this.fromUser,
    required this.text,
    this.table,
    this.chart,
    this.chartIsPie = false,
  });

  final bool fromUser;
  final String text;
  final ChatTable? table;
  final List<ChatChartPoint>? chart;
  final bool chartIsPie;
}

/// Conversational assistant: parses Brazilian-Portuguese natural language
/// into analytical intents, queries the family data and answers with text +
/// structured tables / mini-charts.
///
/// The intent layer is deterministic (keyword/regex NLU) so the whole app
/// works offline; swapping [interpret] for an LLM call keeps the same
/// [ChatMessage] contract.
class ChatAssistantService {
  ChatAssistantService(
    this._analytics,
    this._transactions,
    this._bills,
    this._inventory,
    this._predictionAgent,
    this._recommender,
  );

  final AnalyticsRepository _analytics;
  final TransactionRepository _transactions;
  final BillRepository _bills;
  final InventoryRepository _inventory;
  final BudgetPredictionAgent _predictionAgent;
  final ShoppingRecommender _recommender;

  static final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  Future<ChatMessage> interpret(String input) async {
    final q = _normalize(input);
    try {
      if (_hasAny(q, ['mercado', 'compensa', 'onde comprar', 'compras'])) {
        return _marketRecommendation();
      }
      if (_hasAny(q, ['estourar', 'estouro', 'orcamento', 'risco'])) {
        return _budgetRisk();
      }
      if (_hasAny(q, ['vencer', 'vencendo', 'validade', 'despensa', 'estoque'])) {
        return _pantryStatus();
      }
      if (_hasAny(q, ['conta', 'boleto', 'pagar', 'atrasad'])) {
        return _billsDue();
      }
      if (_hasAny(q, ['saldo', 'patrimonio', 'quanto tenho', 'quanto temos'])) {
        return _balance();
      }
      if (_hasAny(q, ['quanto gast', 'gastamos', 'gastei', 'gasto com'])) {
        return _spendQuery(q);
      }
      if (_hasAny(q, ['maiores', 'top', 'principais despesas'])) {
        return _topExpenses();
      }
      return _help();
    } catch (e) {
      return ChatMessage(
        fromUser: false,
        text: 'Não consegui consultar os dados agora ($e). '
            'Verifique a conexão e tente de novo.',
      );
    }
  }

  // -------------------- intents --------------------

  Future<ChatMessage> _spendQuery(String q) async {
    final byCategory = await _analytics.monthSpendByCategory();
    if (byCategory.isEmpty) {
      return const ChatMessage(
        fromUser: false,
        text: 'Ainda não há despesas registradas este mês.',
      );
    }

    // Category asked explicitly? e.g. "quanto gastamos com lazer esse mês"
    final match = byCategory.where(
        (c) => q.contains(_normalize(c.category)));
    if (match.isNotEmpty) {
      final c = match.first;
      final total =
          byCategory.fold<double>(0, (s, e) => s + e.total);
      final share = total == 0 ? 0.0 : c.total / total;
      return ChatMessage(
        fromUser: false,
        text:
            'Este mês vocês gastaram ${_brl.format(c.total)} com ${c.category} '
            '— ${(share * 100).toStringAsFixed(0)}% de todas as despesas.',
        chart: byCategory
            .take(6)
            .map((e) => ChatChartPoint(label: e.category, value: e.total))
            .toList(),
        chartIsPie: true,
      );
    }

    final total = byCategory.fold<double>(0, (s, e) => s + e.total);
    return ChatMessage(
      fromUser: false,
      text: 'O total de despesas do mês é ${_brl.format(total)}. '
          'Distribuição por categoria:',
      table: ChatTable(
        headers: const ['Categoria', 'Total'],
        rows: byCategory
            .map((c) => [c.category, _brl.format(c.total)])
            .toList(),
      ),
      chart: byCategory
          .take(6)
          .map((e) => ChatChartPoint(label: e.category, value: e.total))
          .toList(),
      chartIsPie: true,
    );
  }

  Future<ChatMessage> _balance() async {
    final kpis = await _analytics.kpis();
    return ChatMessage(
      fromUser: false,
      text: 'Situação consolidada da família:',
      table: ChatTable(
        headers: const ['Indicador', 'Valor'],
        rows: [
          ['Saldo em contas', _brl.format(kpis.totalBalance)],
          ['Patrimônio líquido', _brl.format(kpis.netWorth)],
          ['Receitas do mês', _brl.format(kpis.monthRevenue)],
          ['Despesas do mês', _brl.format(kpis.monthExpenses)],
          [
            'Resultado do mês',
            _brl.format(kpis.monthRevenue - kpis.monthExpenses)
          ],
        ],
      ),
    );
  }

  Future<ChatMessage> _billsDue() async {
    final bills = (await _bills.all())
        .where((b) => b.status == BillStatus.pending)
        .toList();
    if (bills.isEmpty) {
      return const ChatMessage(
        fromUser: false,
        text: 'Nenhuma conta pendente. Tudo em dia! ✅',
      );
    }
    final overdue = bills.where((b) => b.isOverdue).length;
    final total = bills.fold<double>(0, (s, b) => s + b.amount);
    return ChatMessage(
      fromUser: false,
      text:
          'Há ${bills.length} conta(s) pendente(s) somando ${_brl.format(total)}'
          '${overdue > 0 ? ' — $overdue já vencida(s)! ⚠️' : '.'}',
      table: ChatTable(
        headers: const ['Descrição', 'Vencimento', 'Valor'],
        rows: bills
            .take(8)
            .map((b) => [
                  b.description,
                  DateFormat('dd/MM').format(b.dueDate),
                  _brl.format(b.amount),
                ])
            .toList(),
      ),
    );
  }

  Future<ChatMessage> _budgetRisk() async {
    final predictions = await _predictionAgent.run();
    if (predictions.isEmpty) {
      return const ChatMessage(
        fromUser: false,
        text: 'Nenhum orçamento configurado ainda. Crie limites por '
            'categoria no módulo Orçamentos para eu monitorar.',
      );
    }
    final risky = predictions.where((p) => p.isAtRisk).toList();
    return ChatMessage(
      fromUser: false,
      text: risky.isEmpty
          ? 'Bom cenário: nenhuma categoria com risco relevante de estouro '
              'este mês.'
          : '${risky.length} categoria(s) com risco de estourar o orçamento '
              'antes do fim do mês:',
      table: ChatTable(
        headers: const ['Categoria', 'Gasto', 'Projeção', 'Prob. estouro'],
        rows: predictions
            .map((p) => [
                  p.category,
                  _brl.format(p.spent),
                  _brl.format(p.projectedTotal),
                  '${(p.overflowProbability * 100).toStringAsFixed(0)}%',
                ])
            .toList(),
      ),
      chart: predictions
          .map((p) => ChatChartPoint(
              label: p.category, value: p.overflowProbability * 100))
          .toList(),
    );
  }

  Future<ChatMessage> _pantryStatus() async {
    final items = await _inventory.all();
    final expiring = items
        .where((i) => i.daysToExpire != null && i.daysToExpire! <= 7)
        .toList()
      ..sort((a, b) => a.daysToExpire!.compareTo(b.daysToExpire!));
    final low = items.where((i) => i.isLowStock).toList();

    if (expiring.isEmpty && low.isEmpty) {
      return const ChatMessage(
        fromUser: false,
        text: 'Despensa saudável: nada vencendo nos próximos 7 dias e '
            'nenhum item abaixo do estoque mínimo.',
      );
    }
    return ChatMessage(
      fromUser: false,
      text: '${expiring.length} item(ns) vencendo em até 7 dias e '
          '${low.length} abaixo do estoque mínimo:',
      table: ChatTable(
        headers: const ['Produto', 'Situação'],
        rows: [
          ...expiring.map((i) => [
                i.productName,
                i.daysToExpire! < 0
                    ? 'VENCIDO há ${-i.daysToExpire!}d'
                    : 'vence em ${i.daysToExpire}d',
              ]),
          ...low.map((i) => [
                i.productName,
                'estoque ${i.quantity.toStringAsFixed(0)}/${i.minQuantity.toStringAsFixed(0)} ${i.unit}',
              ]),
        ],
      ),
    );
  }

  Future<ChatMessage> _marketRecommendation() async {
    final rec = await _recommender.run();
    if (rec == null) {
      return const ChatMessage(
        fromUser: false,
        text: 'A lista de compras está vazia — adicione itens para eu '
            'calcular onde comprar mais barato.',
      );
    }
    return ChatMessage(
      fromUser: false,
      text: rec.summary,
      table: ChatTable(
        headers: const ['Estratégia', 'Itens', 'Deslocamento', 'Total'],
        rows: [
          [
            'Tudo no ${rec.singleStoreName}',
            _brl.format(rec.singleStoreTotal),
            _brl.format(rec.travelCostSingle),
            _brl.format(rec.singleStoreTotal + rec.travelCostSingle),
          ],
          [
            'Dividir (${rec.splitPlan.length} paradas)',
            _brl.format(rec.splitTotal),
            _brl.format(rec.travelCostSplit),
            _brl.format(rec.splitTotal + rec.travelCostSplit),
          ],
        ],
      ),
    );
  }

  Future<ChatMessage> _topExpenses() async {
    final txs = await _transactions.fetchPage(
      page: 0,
      filter: TransactionFilter(
        type: TransactionType.expense,
        from: DateTime(DateTime.now().year, DateTime.now().month, 1),
      ),
    );
    final top = txs.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    if (top.isEmpty) {
      return const ChatMessage(
          fromUser: false, text: 'Sem despesas registradas este mês.');
    }
    return ChatMessage(
      fromUser: false,
      text: 'Maiores despesas do mês:',
      table: ChatTable(
        headers: const ['Descrição', 'Categoria', 'Valor'],
        rows: top
            .take(5)
            .map((t) => [
                  t.description ?? t.beneficiary ?? t.category,
                  t.category,
                  _brl.format(t.amount),
                ])
            .toList(),
      ),
    );
  }

  ChatMessage _help() => const ChatMessage(
        fromUser: false,
        text: 'Posso ajudar com perguntas como:\n\n'
            '• "Quanto gastamos com lazer esse mês?"\n'
            '• "Qual mercado compensa mais ir hoje?"\n'
            '• "Qual o risco de estourar o orçamento?"\n'
            '• "O que está vencendo na despensa?"\n'
            '• "Quais contas temos para pagar?"\n'
            '• "Qual nosso saldo e patrimônio?"',
      );

  // -------------------- helpers --------------------

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll(RegExp('[í]'), 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll(RegExp('[ú]'), 'u')
      .replaceAll('ç', 'c');

  static bool _hasAny(String q, List<String> keys) =>
      keys.any((k) => q.contains(_normalize(k)));
}

final chatAssistantProvider = Provider(
  (ref) => ChatAssistantService(
    ref.watch(analyticsRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(billRepositoryProvider),
    ref.watch(inventoryRepositoryProvider),
    ref.watch(budgetPredictionAgentProvider),
    ref.watch(shoppingRecommenderProvider),
  ),
);
