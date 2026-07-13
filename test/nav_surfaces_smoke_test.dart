import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kinfin/data/models/models.dart';
import 'package:kinfin/data/repositories/repositories.dart';
import 'package:kinfin/features/auth/auth_controller.dart';
import 'package:kinfin/features/casa/casa_screen.dart';
import 'package:kinfin/features/chat/chat_controller.dart';
import 'package:kinfin/features/chat/chat_screen.dart';
import 'package:kinfin/features/finance/finance_hub_screen.dart';
import 'package:kinfin/features/mode/mode_switch.dart';
import 'package:kinfin/features/settings/usage_mode_controller.dart';
import 'package:kinfin/services/ai/chat_assistant_service.dart';
import 'package:kinfin/services/alerts_service.dart';
import 'package:kinfin/services/insights_engine.dart';

import 'fakes.dart';

/// Smoke tests das 4 superfícies novas da navegação de 5 abas:
///   1. [ModeChip]           (features/mode/mode_switch.dart)
///   2. Card "Avaliação"     (features/finance/finance_hub_screen.dart)
///   3. Barra `_AlertsBar`   (features/chat/chat_screen.dart)
///   4. Card "Dividir despesa" (features/casa/casa_screen.dart)
///
/// Nível SMOKE: renderiza sem crashar, mostra o texto/elemento certo nos casos
/// básicos (com dado / sem dado / loading / erro, quando faz sentido) e, para
/// as superfícies interativas, o toque leva à ação esperada. Não reexercita
/// lógica de negócio (validação de 100%, motor de insights) — isso já tem
/// cobertura própria.

/// O plugin `record` não existe no ambiente de teste — este fake substitui a
/// plataforma para o ChatScreen poder criar/descartar o gravador de voz sem
/// canal nativo. (Mesmo padrão de p2_registro_rapido_test.dart.)
class _FakeRecordPlatform extends RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_FakeRecordPlatform não implementa ${invocation.memberName}');
}

/// TransactionRepository fake: só os dois métodos que as telas de Finanças/Casa
/// leem (transações recentes + parcelas a vencer). Qualquer outro uso falha alto.
class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository({this.recent = const []});

  final List<Transaction> recent;

  @override
  Future<List<Transaction>> recentExpenses({int days = 120}) async => recent;

  @override
  Future<List<Transaction>> upcomingInstallments() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_FakeTransactionRepository não implementa ${invocation.memberName}');
}

class _FakeDebtRepository implements DebtRepository {
  @override
  Future<List<Debt>> all({String orderBy = 'created_at', bool asc = false}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_FakeDebtRepository não implementa ${invocation.memberName}');
}

Future<ChatMessage> _echoBackend(String input) async =>
    const ChatMessage(fromUser: false, text: 'Anotado.');

Transaction _expense({
  required String description,
  double amount = 80,
  String category = 'Mercado',
}) =>
    Transaction(
      familyId: 'fam-1',
      userId: 'user-1',
      type: TransactionType.expense,
      amount: amount,
      category: category,
      description: description,
      date: DateTime(2026, 7, 10),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    RecordPlatform.instance = _FakeRecordPlatform();
    // Sem busca de fonte em runtime: evita timers pendentes que travariam o
    // pumpAndSettle das telas que usam o tema KinFin (google_fonts).
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // 1 · ModeChip — pílula que só INDICA o modo atual
  // ---------------------------------------------------------------------------
  group('ModeChip', () {
    Future<void> pumpChip(WidgetTester tester, UsageMode mode) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            usageModeProvider
                .overrideWith((ref) => UsageModeController()..set(mode)),
          ],
          child: const MaterialApp(home: Scaffold(body: Center(child: ModeChip()))),
        ),
      );
      await tester.pump();
    }

    testWidgets('modo Solo mostra "Modo Solo"', (tester) async {
      await pumpChip(tester, UsageMode.solo);
      expect(find.text('Modo Solo'), findsOneWidget);
      expect(find.text('Modo Compartilhado'), findsNothing);
    });

    testWidgets('modo Compartilhado mostra "Modo Compartilhado"', (tester) async {
      await pumpChip(tester, UsageMode.grupo);
      expect(find.text('Modo Compartilhado'), findsOneWidget);
      expect(find.text('Modo Solo'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 2 · Card "Avaliação" (FinanceHubScreen)
  // ---------------------------------------------------------------------------
  group('Card Avaliação (Finanças)', () {
    Future<FakeAuthRepository> pumpFinance(
      WidgetTester tester, {
      required Override storyOverride,
    }) async {
      final authRepo = FakeAuthRepository()
        ..sessionValue = FakeSession()
        ..profileValue = buildUser(familyId: 'fam-1', role: UserRole.admin);
      addTearDown(authRepo.dispose);

      // Viewport alto: o card "Avaliação" fica abaixo da dobra numa tela de
      // teste padrão (600px) e o ListView, sendo preguiçoso, não o construiria.
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsRepositoryProvider.overrideWithValue(
                FakeAnalyticsRepository(kpisResult: buildKpis(), todaySpent: 0)),
            accountRepositoryProvider
                .overrideWithValue(FakeAccountRepository(const [])),
            billRepositoryProvider
                .overrideWithValue(FakeBillRepository(const [])),
            debtRepositoryProvider
                .overrideWithValue(_FakeDebtRepository()),
            transactionRepositoryProvider
                .overrideWithValue(_FakeTransactionRepository()),
            authControllerProvider.overrideWith((ref) => AuthController(authRepo)),
            storyOverride,
          ],
          child: const MaterialApp(home: FinanceHubScreen()),
        ),
      );
      return authRepo;
    }

    testWidgets('com dado: título + selo + veredito do mês', (tester) async {
      final story = buildMonthStory(
        monthExpenses: 1000,
        monthRevenue: 3000,
        avgMonthlyExpenses90d: 1000,
      );
      await pumpFinance(tester,
          storyOverride: monthStoryProvider.overrideWith((ref) async => story));
      await tester.pumpAndSettle();

      expect(find.text('Avaliação'), findsOneWidget);
      expect(find.text('Saudável'), findsOneWidget);
      expect(find.textContaining('cabem nas entradas'), findsOneWidget);
    });

    testWidgets('sem histórico: convite honesto, sem número fabricado',
        (tester) async {
      final invite = buildMonthStory(
        monthExpenses: 0,
        monthRevenue: 0,
        avgMonthlyExpenses90d: 0,
      );
      await pumpFinance(tester,
          storyOverride: monthStoryProvider.overrideWith((ref) async => invite));
      await tester.pumpAndSettle();

      expect(find.text('Avaliação'), findsOneWidget);
      expect(find.textContaining('só começar'), findsOneWidget);
    });

    testWidgets('loading: mostra "Calculando a avaliação do mês..."',
        (tester) async {
      final completer = Completer<MonthStory>();
      await pumpFinance(
        tester,
        storyOverride:
            monthStoryProvider.overrideWith((ref) => completer.future),
      );
      // Sem pumpAndSettle enquanto pendente: o spinner de loading nunca assenta.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Avaliação'), findsOneWidget);
      expect(find.textContaining('Calculando a avaliação'), findsOneWidget);

      // Resolve para o spinner parar e a árvore assentar antes do teardown
      // (evita timers pendentes no fim do teste).
      completer.complete(buildMonthStory(
          monthExpenses: 0, monthRevenue: 0, avgMonthlyExpenses90d: 0));
      await tester.pumpAndSettle();
    });

    testWidgets('erro: mensagem calma, sem crashar', (tester) async {
      await pumpFinance(
        tester,
        storyOverride: monthStoryProvider
            .overrideWith((ref) => Future<MonthStory>.error(Exception('boom'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Avaliação'), findsOneWidget);
      expect(find.text('Não foi possível avaliar o mês agora.'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 3 · Barra de alertas (ChatScreen)
  // ---------------------------------------------------------------------------
  group('_AlertsBar (Chat)', () {
    Future<void> pumpChat(WidgetTester tester, {required bool showAlertsBar}) async {
      final container = ProviderContainer(overrides: [
        chatBackendProvider.overrideWithValue(_echoBackend),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ChatScreen(showAlertsBar: showAlertsBar)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('quando visível: copy honesta, sem prometer criar alerta',
        (tester) async {
      await pumpChat(tester, showAlertsBar: true);

      expect(find.text('Alertas personalizados por IA'), findsOneWidget);
      expect(find.textContaining('Ainda não estão disponíveis'), findsOneWidget);
      // Não deve mais convidar a pessoa a "pedir" um alerta que a IA não cria.
      expect(find.textContaining('Peça ao assistente'), findsNothing);
      expect(find.textContaining('criar um alerta'), findsNothing);
    });

    testWidgets('desligada por padrão: a barra não aparece', (tester) async {
      await pumpChat(tester, showAlertsBar: false);
      expect(find.text('Alertas personalizados por IA'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 4 · Card "Dividir despesa entre a família" (CasaScreen)
  // ---------------------------------------------------------------------------
  group('Card Dividir despesa (Casa)', () {
    Future<void> pumpCasa(WidgetTester tester, List<Transaction> recent) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionRepositoryProvider.overrideWithValue(
                _FakeTransactionRepository(recent: recent)),
            alertsProvider.overrideWith((ref) async => const <AppAlert>[]),
          ],
          child: const MaterialApp(home: CasaScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renderiza o card na seção Família', (tester) async {
      await pumpCasa(tester, const []);
      expect(find.text('Dividir despesa entre a família'), findsOneWidget);
      expect(find.text('Família'), findsOneWidget);
    });

    testWidgets('com despesas: o toque abre o seletor e lista as despesas reais',
        (tester) async {
      await pumpCasa(tester, [_expense(description: 'Compras da semana')]);

      await tester.tap(find.text('Dividir despesa entre a família'));
      await tester.pumpAndSettle();

      expect(find.text('Qual despesa dividir?'), findsOneWidget);
      expect(find.text('Compras da semana'), findsOneWidget);
    });

    testWidgets('sem despesas: o seletor mostra o estado vazio honesto',
        (tester) async {
      await pumpCasa(tester, const []);

      await tester.tap(find.text('Dividir despesa entre a família'));
      await tester.pumpAndSettle();

      expect(find.text('Qual despesa dividir?'), findsOneWidget);
      expect(
          find.textContaining('Nenhuma despesa recente para dividir'), findsOneWidget);
    });
  });
}
