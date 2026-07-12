import 'dart:io';
import 'dart:typed_data';

import 'package:family_erp/core/widgets/linkified_text.dart';
import 'package:family_erp/data/models/models.dart';
import 'package:family_erp/features/auth/auth_controller.dart';
import 'package:family_erp/features/capture/quick_capture_sheet.dart';
import 'package:family_erp/features/capture/voice_capture.dart';
import 'package:family_erp/features/chat/chat_controller.dart';
import 'package:family_erp/features/chat/chat_screen.dart';
import 'package:family_erp/features/shopping/shopping_screen.dart';
import 'package:family_erp/services/ai/audio_transcription_service.dart';
import 'package:family_erp/services/ai/chat_assistant_service.dart';
import 'package:family_erp/services/ai/shopping_recommender.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'fakes.dart';

/// P2.2 — Ajustes reais de uso: áudio (parar e enviar, pause, cancelar,
/// indicador), links clicáveis e importação honesta de lista em Compras.

class _FakeRecordPlatform extends RecordPlatform {
  String? lastPath;
  bool stopped = false;
  bool _recording = false;
  bool _paused = false;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {
    lastPath = path;
    stopped = false;
    _recording = true;
    _paused = false;
    File(path).writeAsBytesSync([1, 2, 3, 4]); // bytes p/ recordingBytes ler
  }

  @override
  Future<void> pause(String recorderId) async => _paused = true;

  @override
  Future<void> resume(String recorderId) async => _paused = false;

  @override
  Future<String?> stop(String recorderId) async {
    stopped = true;
    _recording = false;
    _paused = false;
    return lastPath;
  }

  // A API do pacote record cria e assina estes canais antes de iniciar o
  // microfone. O fake os implementa para testar o fluxo real, sem microfone.
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  Future<bool> isRecording(String recorderId) async => _recording;

  @override
  Future<bool> isPaused(String recorderId) async => _paused;

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -20, max: -8);

  @override
  Future<bool> isEncoderSupported(
          String recorderId, AudioEncoder encoder) async =>
      true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];

  @override
  Future<void> cancel(String recorderId) async {
    _recording = false;
    _paused = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_FakeRecordPlatform não implementa ${invocation.memberName}');
}

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

final _fakeRecord = _FakeRecordPlatform();

Future<ChatMessage> _echoBackend(String input) async => const ChatMessage(
    fromUser: false, text: 'Anotado: registrado com sucesso.');

/// Avança o tempo sem pumpAndSettle (as barras de gravação animam em loop).
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Permite que a leitura local do arquivo de áudio (I/O real) termine no
/// ambiente de widget test; animações em loop continuam fora deste helper.
Future<void> _completeAudioSend(WidgetTester tester) async {
  await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)));
  await _pumpFrames(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    RecordPlatform.instance = _fakeRecord;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      chatBackendProvider.overrideWithValue(_echoBackend),
      transcriptionProvider.overrideWithValue((bytes,
              {String filename = 'audio.webm',
              String contentType = 'audio/webm'}) async =>
          'gastei 80 no mercado'),
      voiceCaptureFactoryProvider.overrideWithValue(
        (transcribe) => VoiceCaptureController(
          transcribe: transcribe,
          readBytes: (_) async => Uint8List.fromList([1, 2, 3, 4]),
        ),
      ),
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

  group('Áudio — Registro Rápido', () {
    testWidgets('tocar no mic mostra indicador vivo + pause + cancelar',
        (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await _pumpFrames(tester);

      expect(find.textContaining('Ouvindo'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget,
          reason: 'enviar continua disponível — vira "parar e enviar"');

      // limpeza: cancela para o teardown não ficar com animação viva
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('enviar DURANTE a gravação para, transcreve e envia',
        (tester) async {
      final container = await pumpSheet(tester);

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await _pumpFrames(tester);
      expect(find.textContaining('Ouvindo'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      // Há microanimações persistentes na tela; estabilizamos apenas os
      // frames necessários para a ação assíncrona, sem esperar animações em
      // loop terminarem.
      await _completeAudioSend(tester);

      expect(_fakeRecord.stopped, isTrue, reason: 'enviar deve parar o mic');
      expect(find.textContaining('Anotado'), findsOneWidget);
      final msgs = container.read(chatControllerProvider).messages;
      expect(msgs.any((m) => m.fromUser && m.text == 'gastei 80 no mercado'),
          isTrue,
          reason: 'o texto transcrito é o que foi enviado');
    });

    testWidgets('pausar e depois enviar envia o áudio já gravado',
        (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await _pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await _pumpFrames(tester);
      expect(find.textContaining('Pausado'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await _completeAudioSend(tester);
      expect(find.textContaining('Anotado'), findsOneWidget);
    });

    testWidgets('cancelar descarta a gravação sem enviar nada', (tester) async {
      final container = await pumpSheet(tester);
      final baseline = container.read(chatControllerProvider).messages.length;

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await _pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('Anotado'), findsNothing);
      expect(container.read(chatControllerProvider).messages.length, baseline,
          reason: 'cancelar não pode enviar nem transcrever');
      expect(find.byType(TextField), findsOneWidget); // voltou ao campo
    });

    testWidgets('áudio NUNCA é enviado sem ação explícita do usuário',
        (tester) async {
      final container = await pumpSheet(tester);
      final baseline = container.read(chatControllerProvider).messages.length;

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await _pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      // Espera parado: nada deve acontecer sozinho.
      await tester.pump(const Duration(seconds: 2));

      expect(container.read(chatControllerProvider).messages.length, baseline);
      expect(find.textContaining('Anotado'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded)); // limpeza
      await tester.pumpAndSettle();
    });
  });

  group('Áudio — Chat', () {
    testWidgets('mic grava, enviar para e envia; indicador aparece',
        (tester) async {
      final container = ProviderContainer(overrides: [
        chatBackendProvider.overrideWithValue(_echoBackend),
        transcriptionProvider.overrideWithValue((bytes,
                {String filename = 'audio.webm',
                String contentType = 'audio/webm'}) async =>
            'paguei 120 de luz'),
        voiceCaptureFactoryProvider.overrideWithValue(
          (transcribe) => VoiceCaptureController(
            transcribe: transcribe,
            readBytes: (_) async => Uint8List.fromList([1, 2, 3, 4]),
          ),
        ),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await _pumpFrames(tester);
      expect(find.textContaining('Ouvindo'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await _completeAudioSend(tester);

      expect(find.text('paguei 120 de luz'), findsOneWidget); // bolha user
      expect(find.textContaining('Anotado'), findsOneWidget);
    });
  });

  group('Links clicáveis', () {
    testWidgets('URL real vira link clicável; texto comum não', (tester) async {
      Uri? opened;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LinkifiedText(
            'Ofertas em https://goodbom.com.br/ofertas. GoodBom e Covabra.',
            onOpen: (u) async => opened = u,
          ),
        ),
      ));

      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final linkSpans = <TextSpan>[];
      var plainWithRecognizer = 0;
      void visit(InlineSpan s) {
        if (s is TextSpan) {
          if (s.recognizer != null) {
            if ((s.text ?? '').startsWith('http')) {
              linkSpans.add(s);
            } else {
              plainWithRecognizer++;
            }
          }
          s.children?.forEach(visit);
        }
      }

      visit(rich.text);
      expect(linkSpans, hasLength(1));
      expect(linkSpans.single.text, 'https://goodbom.com.br/ofertas',
          reason: 'pontuação final não faz parte do link');
      expect(plainWithRecognizer, 0,
          reason: 'nome de mercado NUNCA vira link inventado');

      (linkSpans.single.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened.toString(), 'https://goodbom.com.br/ofertas');
    });

    testWidgets('mensagem da assistente com URL renderiza linkificada',
        (tester) async {
      final container = ProviderContainer(overrides: [
        chatBackendProvider
            .overrideWithValue((input) async => const ChatMessage(
                fromUser: false,
                text: 'Melhor preço no GoodBom: '
                    'https://goodbom.com.br/ofertas')),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'tem promoção?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(LinkifiedText), findsWidgets);
      expect(
          find.textContaining('https://goodbom.com.br/ofertas',
              findRichText: true),
          findsOneWidget);
    });
  });

  group('Compras — importar lista honesta', () {
    Future<void> pumpShopping(WidgetTester tester) async {
      final authRepo = FakeAuthRepository()
        ..sessionValue = FakeSession()
        ..profileValue = buildUser(familyId: 'fam-1', role: UserRole.admin);
      addTearDown(authRepo.dispose);
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith((ref) => AuthController(authRepo)),
        shoppingListProvider
            .overrideWith((ref) async => const <ShoppingItem>[]),
        shoppingRecommendationProvider.overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ShoppingScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opção aparece em Compras, claramente EM PREPARAÇÃO',
        (tester) async {
      await pumpShopping(tester);

      expect(find.text('Importar lista por foto'), findsOneWidget);
      expect(find.text('Em preparação'), findsOneWidget);
      // Não parece funcional: nenhum botão falso de site/scan ativo.
      expect(find.text('Abrir site'), findsNothing);
    });

    testWidgets('tocar explica honestamente e oferece a alternativa por voz',
        (tester) async {
      await pumpShopping(tester);

      await tester.tap(find.text('Importar lista por foto'));
      await tester.pump();
      expect(find.textContaining('em preparação'), findsOneWidget);
      expect(find.textContaining('dite os itens'), findsOneWidget);
    });
  });
}
