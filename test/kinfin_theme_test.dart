import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:family_erp/core/theme/app_theme.dart';
import 'package:family_erp/core/theme/kinfin_theme.dart';
import 'package:family_erp/core/widgets/kinfin_scope.dart';
import 'package:family_erp/features/settings/usage_mode_controller.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  // Montamos um MaterialApp com o tema para que o carregamento de fonte
  // (google_fonts) seja tolerado como no resto da suíte; a asserção é sobre o
  // ThemeData construído.
  group('KinFinTheme.build — acento por modo', () {
    testWidgets('Solo usa roxo/índigo como primário', (tester) async {
      final theme = KinFinTheme.build(isSolo: true);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
      expect(theme.colorScheme.primary, KinFinColors.solo);
    });

    testWidgets('Compartilhado usa verde como primário', (tester) async {
      final theme = KinFinTheme.build(isSolo: false);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
      expect(theme.colorScheme.primary, KinFinColors.shared);
    });

    testWidgets('scaffold transparente (a convivência depende disso)',
        (tester) async {
      final theme = KinFinTheme.build(isSolo: true);
      await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
    });
  });

  group('KinFinScope — aplica o primário certo lendo o modo', () {
    Future<Color> primaryFor(WidgetTester tester, UsageMode mode) async {
      late Color captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            usageModeProvider
                .overrideWith((ref) => UsageModeController()..set(mode)),
          ],
          child: MaterialApp(
            home: KinFinScope(
              child: Builder(builder: (ctx) {
                captured = Theme.of(ctx).colorScheme.primary;
                return const SizedBox();
              }),
            ),
          ),
        ),
      );
      await tester.pump();
      return captured;
    }

    testWidgets('modo Solo → primário roxo', (tester) async {
      expect(await primaryFor(tester, UsageMode.solo), KinFinColors.solo);
    });

    testWidgets('modo Compartilhado → primário verde', (tester) async {
      expect(await primaryFor(tester, UsageMode.grupo), KinFinColors.shared);
    });
  });

  group('Casa Viva intacto (telas antigas não mudam)', () {
    testWidgets('AppTheme.dark ainda tem a menta como primário padrão',
        (tester) async {
      final theme = AppTheme.dark();
      await tester.pumpWidget(MaterialApp(theme: theme, home: const SizedBox()));
      expect(theme.colorScheme.primary, AppColors.mint);
    });

    test('KinFin não colide com o primário do Casa Viva e usa fundo próprio', () {
      expect(KinFinColors.solo, isNot(AppColors.mint));
      expect(KinFinColors.shared, isNot(AppColors.mint));
      expect(KinFinColors.bg, isNot(AppColors.darkBg));
    });
  });
}
