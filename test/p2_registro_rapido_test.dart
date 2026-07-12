import 'package:family_erp/core/widgets/write_confirmation_card.dart';
import 'package:family_erp/data/models/models.dart';
import 'package:family_erp/data/repositories/repositories.dart';
import 'package:family_erp/features/capture/quick_capture_sheet.dart';
import 'package:family_erp/features/chat/chat_controller.dart';
import 'package:family_erp/features/chat/chat_screen.dart';
import 'package:family_erp/features/dashboard/dashboard_screen.dart';
import 'package:family_erp/features/auth/auth_controller.dart';
import 'package:family_erp/services/ai/chat_assistant_service.dart';
import 'package:family_erp/services/ai/confirmation_service.dart';
import 'package:family_erp/services/ai/write_safety.dart';
import 'package:family_erp/services/alerts_service.dart';
import 'package:family_erp/services/ai/ai_write_tick.dart';
import 'package:family_erp/services/dream_outlook_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// P2.1 — Blindagem do Registro Rápido.
/// Testes de widget e reatividade cobrindo: o sheet (conteúdo, confirmação,
/// fechamento seguro), o card de confirmação compartilhado, a regressão do
/// chat após a extração do controller/card, e o tick de dados vivos.

/// O plugin `record` não existe no ambiente de teste — este fake substitui a
/// plataforma para os widgets poderem criar/descartar o gravador sem canal
/// nativo. Qualquer método inesperado falha alto (padrão dos fakes da casa).
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

Future<ChatMessage> _echoBackend(String input) async =>
    const ChatMessage(fromUser: false, text: 'Anotado: R\$ 50,00 no Mercado.');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    RecordPlatform.instance = _FakeRecordPlatform();
  });

  setUp(() {
    // Dica do dia desligada para não abrir diálogo em cima dos testes.
    SharedPreferences.setMockInitialValues({'economy_tips_enabled': false});
  });

  // Harness mínimo: um botão que abre o Registro Rápido.
  Future<ProviderContainer> pumpSheetHarness(WidgetTester tester,
      {Future<ChatMessage> Function(String)? backend}) async {
    final container = ProviderContainer(overrides: [
      chatBackendProvider.overrideWithValue(backend ?? _echoBackend),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showQuickCapture(context),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return container;
  }

  group('Registro Rápido — sheet', () {
    testWidgets('renderiza título, microcopy de descoberta e fallback',
        (tester) async {
      await pumpSheetHarness(tester);

      expect(find.text('O que aconteceu?'), findsOneWidget);
      expect(find.textContaining('Também entendo'), findsOneWidget);
      expect(find.text('Prefiro o formulário completo'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // Voz presente, mas não gravando (nada de vermelho por padrão).
      expect(find.byIcon(Icons.mic_outlined), findsOneWidget);
    });

    testWidgets('envia texto e mostra a resposta com ✓ e "Registrar outro"',
        (tester) async {
      await pumpSheetHarness(tester);

      await tester.enterText(
          find.byType(TextField), 'gastei 50 no mercado');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('Anotado'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.text('Registrar outro'), findsOneWidget);
      expect(find.text('Fechar'), findsOneWidget);

      // "Registrar outro" volta ao campo de entrada.
      await tester.tap(find.text('Registrar outro'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('confirmação pendente aparece DENTRO do sheet', (tester) async {
      final container = await pumpSheetHarness(tester);

      final conf = confirmationFor('add_bill', {
        'description': 'Luz',
        'amount': 120,
        'due_date': '2026-08-10',
      })!;
      final fut = container
          .read(writeConfirmationControllerProvider.notifier)
          .request(conf);
      await tester.pumpAndSettle();

      expect(find.byType(WriteConfirmationCard), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      // Limpeza: resolve para o future não ficar pendurado.
      container.read(writeConfirmationControllerProvider.notifier).resolve(false);
      final result = await fut;
      expect(result.confirmed, isFalse);
    });

    testWidgets('fechar o sheet com confirmação pendente CANCELA (não grava)',
        (tester) async {
      final container = await pumpSheetHarness(tester);

      final conf = confirmationFor('add_debt', {
        'creditor': 'Loja X',
        'original_amount': 300,
      })!;
      final fut = container
          .read(writeConfirmationControllerProvider.notifier)
          .request(conf);
      await tester.pumpAndSettle();
      expect(find.byType(WriteConfirmationCard), findsOneWidget);

      // Fecha o sheet tocando fora (barrier).
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final result = await fut;
      expect(result.confirmed, isFalse,
          reason: 'dispose do sheet deve resolver a pendência como cancelada');
      expect(container.read(writeConfirmationControllerProvider), isNull);
    });
  });

  group('WriteConfirmationCard — compartilhado', () {
    Future<(ProviderContainer, Future<ConfirmationResult>)> pumpCard(
        WidgetTester tester, WriteConfirmation conf) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final fut = container
          .read(writeConfirmationControllerProvider.notifier)
          .request(conf);
      final pending = container.read(writeConfirmationControllerProvider)!;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: WriteConfirmationCard(pending: pending),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container, fut);
    }

    testWidgets('renderiza o que entendeu + campos editáveis + botões',
        (tester) async {
      final conf = confirmationFor('add_bill', {
        'description': 'Internet',
        'amount': 99.9,
        'due_date': '2026-08-10',
      })!;
      final (_, fut) = await pumpCard(tester, conf);

      expect(find.textContaining('Entendi que'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets); // campos editáveis

      await tester.tap(find.text('Cancelar'));
      final r = await fut;
      expect(r.confirmed, isFalse);
    });

    testWidgets('Cancelar resolve como não-confirmado (nada grava)',
        (tester) async {
      final conf = confirmationFor('add_transaction', {
        'type': 'expense',
        'amount': 80,
        'category': 'Churrasco', // desconhecida → dispara confirmação
      })!;
      final (_, fut) = await pumpCard(tester, conf);

      await tester.tap(find.text('Cancelar'));
      final r = await fut;
      expect(r.confirmed, isFalse);
      expect(r.values, isEmpty);
    });

    testWidgets('Confirmar devolve os valores EDITADOS pelo usuário',
        (tester) async {
      final conf = confirmationFor('add_debt', {
        'creditor': 'Loja X',
        'original_amount': 300,
      })!;
      final (_, fut) = await pumpCard(tester, conf);

      // Corrige o valor no campo de dinheiro ("Valor").
      final moneyField = find.widgetWithText(TextField, 'Valor').first;
      await tester.enterText(moneyField, '350,50');
      await tester.tap(find.text('Confirmar'));
      final r = await fut;

      expect(r.confirmed, isTrue);
      expect(r.values['original_amount'], '350.50'); // vírgula normalizada
      expect(r.values['creditor'], 'Loja X');
    });
  });

  group('Chat — regressão pós-extração', () {
    Future<ProviderContainer> pumpChat(WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        chatBackendProvider.overrideWithValue(_echoBackend),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('input continua funcionando: envia e recebe resposta',
        (tester) async {
      await pumpChat(tester);

      await tester.enterText(
          find.byType(TextField).first, 'gastei 50 no mercado');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('gastei 50 no mercado'), findsOneWidget); // bolha user
      expect(find.textContaining('Anotado'), findsOneWidget); // resposta
    });

    testWidgets('histórico é compartilhado: greeting inicial presente',
        (tester) async {
      final container = await pumpChat(tester);
      final state = container.read(chatControllerProvider);
      expect(state.messages, isNotEmpty);
      expect(state.messages.first.fromUser, isFalse);
      expect(find.textContaining('Eu cuido das finanças'), findsOneWidget);
    });

    testWidgets('card de confirmação continua renderizando no chat',
        (tester) async {
      final container = await pumpChat(tester);

      final conf = confirmationFor('add_bill', {
        'description': 'Escola',
        'amount': 500,
        'due_date': '2026-08-15',
      })!;
      final fut = container
          .read(writeConfirmationControllerProvider.notifier)
          .request(conf);
      await tester.pumpAndSettle();

      expect(find.byType(WriteConfirmationCard), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      final r = await fut;
      expect(r.confirmed, isFalse);
    });
  });

  group('Home — FAB abre o Registro Rápido', () {
    testWidgets('FAB "+" na Home abre o sheet', (tester) async {
      final authRepo = FakeAuthRepository()
        ..sessionValue = FakeSession()
        ..profileValue = buildUser(familyId: 'fam-1', role: UserRole.admin);
      addTearDown(authRepo.dispose);

      final container = ProviderContainer(overrides: [
        chatBackendProvider.overrideWithValue(_echoBackend),
        authControllerProvider
            .overrideWith((ref) => AuthController(authRepo)),
        alertsProvider.overrideWith((ref) async => const <AppAlert>[]),
        spendingAllowanceProvider.overrideWith((ref) async =>
            const SpendingAllowance(
                perDay: 50,
                todaySpent: 10,
                freeThisMonth: 500,
                daysLeft: 10,
                status: AllowanceStatus.verde)),
        dreamOutlookProvider.overrideWith((ref) async => DreamOutlook.none),
        weekSummaryProvider.overrideWith((ref) async => const WeekSummary(
            expenses: 0,
            revenue: 0,
            previousExpenses: 0,
            topCategory: null,
            topCategoryTotal: 0)),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget, reason: 'Home deve ter UM FAB (Registrar)');
      await tester.tap(fab);
      await tester.pumpAndSettle();

      expect(find.text('O que aconteceu?'), findsOneWidget);
    });
  });

  group('Dados vivos — tick da IA', () {
    test('bump no tick refaz os providers que o observam', () async {
      var calls = 0;
      final container = ProviderContainer(overrides: [
        billRepositoryProvider.overrideWith((ref) {
          return _CountingBillRepository(() => calls++);
        }),
        inventoryRepositoryProvider
            .overrideWith((ref) => FakeInventoryRepository()),
      ]);
      addTearDown(container.dispose);

      // Mantém o provider vivo (autoDispose) e espera o primeiro valor.
      final sub = container.listen(alertsProvider.future, (_, __) {});
      await sub.read();
      expect(calls, 1);

      // A IA gravou algo → tick → o provider refaz a busca sem reload manual.
      container.read(aiWriteTickProvider.notifier).state++;
      await container.pump();
      await sub.read();
      expect(calls, 2,
          reason: 'após o tick, alertsProvider deve reconsultar as contas');
    });
  });
}

class _CountingBillRepository implements BillRepository {
  _CountingBillRepository(this.onAll);

  final void Function() onAll;

  @override
  Future<List<Bill>> all({String orderBy = 'due_date', bool asc = true}) async {
    onAll();
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_CountingBillRepository não implementa ${invocation.memberName}');
}
