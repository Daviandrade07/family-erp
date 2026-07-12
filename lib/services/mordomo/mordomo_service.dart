import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/formatters.dart';
import '../ai/ai_write_tick.dart';
import '../ai/budget_prediction_agent.dart';
import '../alerts_service.dart';
import '../dream_outlook_service.dart';
import 'suggestion.dart';

/// Fontes → Suggestion. Cada função é PURA (recebe a saída de um motor que já
/// existe) e não chama o modelo. O mordomo ORQUESTRA o que já temos.

List<Suggestion> budgetSuggestions(List<BudgetPrediction> preds) {
  final out = <Suggestion>[];
  for (final p in preds) {
    if (p.projectedTotal <= p.limitAmount) continue; // sem risco de estouro
    out.add(Suggestion(
      id: 'budget_overflow:${p.category}',
      dedupKey: 'cat:${p.category}',
      type: 'budget_overflow',
      title: '${p.category} acima do ritmo',
      body: 'No ritmo atual, ${p.category} fecha o mês em ${p.projectedTotal.brl}'
          ' (limite ${p.limitAmount.brl}). Dá pra ajustar.',
      confidence: p.overflowProbability,
      severity: SuggestionSeverity.attention,
      impact: p.projectedTotal - p.limitAmount,
      route: '/budgets',
    ));
  }
  return out;
}

List<Suggestion> goalSuggestions(DreamOutlook d) {
  final g = d.goal;
  if (g == null) return const [];
  final remaining = g.targetAmount - g.currentAmount;
  if (remaining <= 0) return const [];
  return [
    Suggestion(
      id: 'goal_gap:${g.id ?? g.name}',
      dedupKey: 'goal:${g.id ?? g.name}',
      type: 'goal_gap',
      title: 'Faltam ${remaining.brl} pra ${g.name}',
      body: d.subline.isNotEmpty
          ? d.subline
          : 'Vocês estão a caminho — cada aporte aproxima.',
      confidence: 0.9,
      severity: SuggestionSeverity.info,
      route: '/goals',
    ),
  ];
}

List<Suggestion> alertSuggestions(List<AppAlert> alerts) {
  return alerts.map((a) {
    final severity = switch (a.severity) {
      AlertSeverity.critico => SuggestionSeverity.urgent,
      AlertSeverity.atencao => SuggestionSeverity.attention,
      AlertSeverity.info => SuggestionSeverity.info,
    };
    final confidence = switch (a.severity) {
      AlertSeverity.critico => 0.95,
      AlertSeverity.atencao => 0.85,
      AlertSeverity.info => 0.70,
    };
    return Suggestion(
      id: 'alert:${a.route ?? ''}:${a.title}',
      dedupKey: 'alert:${a.route ?? ''}:${a.title}',
      type: 'alert',
      title: a.title,
      body: a.subtitle,
      confidence: confidence,
      severity: severity,
      route: a.route,
    );
  }).toList();
}

/// "Ignorar" — persiste (não mostrar de novo). Adição apenas.
class FeedDismissedController extends StateNotifier<Set<String>> {
  FeedDismissedController() : super(const {}) {
    _load();
  }
  static const _key = 'feed_dismissed';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getStringList(_key) ?? const []).toSet();
  }

  Future<void> add(String id) async {
    state = {...state, id};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }
}

final feedDismissedProvider =
    StateNotifierProvider<FeedDismissedController, Set<String>>(
        (ref) => FeedDismissedController());

/// "Agora não" — some pela sessão (volta ao reabrir o app).
final feedSnoozedProvider = StateProvider<Set<String>>((ref) => const {});

/// Ids escondidos = ignorados (persistidos) ∪ adiados (sessão).
final feedHiddenProvider = Provider<Set<String>>((ref) => {
      ...ref.watch(feedDismissedProvider),
      ...ref.watch(feedSnoozedProvider),
    });

/// O feed do mordomo, orquestrado: junta as fontes puras e monta com
/// [buildFeed] (ranking, dedup, teto, limiar 0.65, escondidos). Reage a
/// gravações da IA.
final mordomoFeedProvider = FutureProvider.autoDispose<FeedResult>((ref) async {
  ref.watch(aiWriteTickProvider);
  final hidden = ref.watch(feedHiddenProvider);
  final budgets = await ref.watch(budgetPredictionsProvider.future);
  final dream = await ref.watch(dreamOutlookProvider.future);
  final alerts = await ref.watch(alertsProvider.future);
  final raw = [
    ...budgetSuggestions(budgets),
    ...goalSuggestions(dream),
    ...alertSuggestions(alerts),
  ];
  return buildFeed(raw, hidden: hidden);
});
