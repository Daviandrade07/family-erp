import 'package:flutter_test/flutter_test.dart';
import 'package:family_erp/services/mordomo/suggestion.dart';

Suggestion s(
  String id, {
  String? dedup,
  SuggestionSeverity sev = SuggestionSeverity.info,
  double conf = 0.9,
  double impact = 0,
}) =>
    Suggestion(
      id: id,
      dedupKey: dedup ?? id,
      type: 'test',
      title: id,
      body: '',
      confidence: conf,
      severity: sev,
      impact: impact,
    );

void main() {
  group('buildFeed — ranking', () {
    test('severidade domina a confiança (urgente > atenção > info)', () {
      final r = buildFeed([
        s('info', conf: 0.99),
        s('urgente', sev: SuggestionSeverity.urgent, conf: 0.70),
        s('atencao', sev: SuggestionSeverity.attention, conf: 0.99),
      ]);
      expect(r.top.map((x) => x.id).toList(), ['urgente', 'atencao', 'info']);
    });

    test('dentro da mesma severidade, maior impacto vem antes', () {
      final r = buildFeed([
        s('menor', sev: SuggestionSeverity.attention, impact: 100),
        s('maior', sev: SuggestionSeverity.attention, impact: 5000),
      ]);
      expect(r.top.first.id, 'maior');
    });
  });

  group('buildFeed — limiar de confiança', () {
    test('abaixo de 0.65 é descartado', () {
      final r = buildFeed([s('baixa', conf: 0.5), s('ok', conf: 0.65)]);
      expect(r.top.map((x) => x.id), ['ok']);
    });
  });

  group('buildFeed — dedup', () {
    test('mesmo dedupKey vira um card só (mantém o de maior score)', () {
      final r = buildFeed([
        s('a1', dedup: 'cat:Lazer'),
        s('a2', dedup: 'cat:Lazer', sev: SuggestionSeverity.urgent),
      ]);
      expect(r.top.length, 1);
      expect(r.top.first.id, 'a2'); // urgente (score maior) sobrevive
    });
  });

  group('buildFeed — teto e "ver mais"', () {
    test('teto 3: os extras contam no moreCount', () {
      final r = buildFeed([
        for (var i = 0; i < 5; i++) s('s$i', dedup: 'k$i'),
      ]);
      expect(r.top.length, 3);
      expect(r.moreCount, 2);
    });
  });

  group('buildFeed — escondidos (ignorar / agora não)', () {
    test('id escondido não aparece', () {
      final r = buildFeed([s('a'), s('b')], hidden: {'a'});
      expect(r.top.map((x) => x.id), ['b']);
    });
  });

  group('buildFeed — estado vazio', () {
    test('sem sugestões → vazio', () {
      expect(buildFeed(const []).isEmpty, isTrue);
    });

    test('tudo escondido → vazio', () {
      final r = buildFeed([s('a'), s('b')], hidden: {'a', 'b'});
      expect(r.isEmpty, isTrue);
    });

    test('tudo abaixo do limiar → vazio', () {
      final r = buildFeed([s('a', conf: 0.4), s('b', conf: 0.6)]);
      expect(r.isEmpty, isTrue);
    });
  });
}
