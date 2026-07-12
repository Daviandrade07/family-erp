/// Contrato de uma sugestão do mordomo + a lógica PURA de montagem do feed
/// (ranking, dedup, teto, limiar, escondidos). Sem Flutter, sem Supabase,
/// sem chamada ao modelo — 100% determinístico e testável.
enum SuggestionSeverity { info, attention, urgent }

class Suggestion {
  const Suggestion({
    required this.id,
    required this.dedupKey,
    required this.type,
    required this.title,
    required this.body,
    required this.confidence,
    required this.severity,
    this.impact = 0,
    this.route,
    this.actionLabel = 'Ver',
  });

  /// Estável (`tipo:alvo:período`) — chave de dedup no tempo, snooze e "ignorar".
  final String id;

  /// Chave de fusão: sugestões com o mesmo `dedupKey` (ex.: mesma categoria em
  /// risco vinda de fontes diferentes) viram um card só (mantém a de maior score).
  final String dedupKey;
  final String type;
  final String title;
  final String body;
  final double confidence; // 0..1
  final SuggestionSeverity severity;
  final double impact; // R$ em jogo (peso no ranking)
  final String? route; // navegação (F3: card só navega, não escreve)
  final String actionLabel;

  int get _sevWeight => switch (severity) {
        SuggestionSeverity.urgent => 3000,
        SuggestionSeverity.attention => 2000,
        SuggestionSeverity.info => 1000,
      };

  /// Severidade domina; depois o impacto em R$; depois a confiança. Assim um
  /// urgente sempre vem antes de um atenção, que vem antes de um info.
  double get score =>
      _sevWeight + impact.clamp(0, 100000) / 1000 + confidence * 10;
}

class FeedResult {
  const FeedResult(this.top, this.moreCount);

  /// Cards no topo (respeitando o teto).
  final List<Suggestion> top;

  /// Quantos passaram do teto (vão no "ver mais").
  final int moreCount;

  bool get isEmpty => top.isEmpty;
}

/// Monta o feed: limiar de confiança → remove escondidos → dedup por `dedupKey`
/// (mantém o de maior score) → ordena por score → aplica o teto.
FeedResult buildFeed(
  List<Suggestion> raw, {
  Set<String> hidden = const {},
  double minConfidence = 0.65,
  int cap = 3,
}) {
  final visible = raw
      .where((s) => s.confidence >= minConfidence && !hidden.contains(s.id))
      .toList();

  final byKey = <String, Suggestion>{};
  for (final s in visible) {
    final cur = byKey[s.dedupKey];
    if (cur == null || s.score > cur.score) byKey[s.dedupKey] = s;
  }

  final deduped = byKey.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  final top = deduped.take(cap).toList();
  return FeedResult(top, deduped.length - top.length);
}
