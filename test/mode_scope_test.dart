import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kinfin/features/mode/mode_scope.dart';
import 'package:kinfin/features/settings/usage_mode_controller.dart';

void main() {
  group('scopeUserId — regra pura de escopo', () {
    test('Solo escopa pelo meu user_id', () {
      expect(scopeUserId(UsageMode.solo, 'u-123'), 'u-123');
    });

    test('Compartilhado não filtra por autor (null)', () {
      expect(scopeUserId(UsageMode.grupo, 'u-123'), isNull);
    });

    test('Solo sem usuário conhecido → sem filtro (não vaza tudo por engano)',
        () {
      expect(scopeUserId(UsageMode.solo, null), isNull);
    });
  });

  group('usageMode — persistência', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('grava o modo escolhido', () async {
      final c = UsageModeController();
      await c.set(UsageMode.solo);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('usage_mode'), 'solo');
    });

    test('recarrega o modo salvo numa nova instância', () async {
      final c1 = UsageModeController();
      await c1.set(UsageMode.solo); // grava pelo caminho real
      final c2 = UsageModeController();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c2.state, UsageMode.solo); // recarrega
    });

    test('padrão é Compartilhado quando não há nada salvo', () async {
      final c = UsageModeController();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.state, UsageMode.grupo);
    });
  });
}
