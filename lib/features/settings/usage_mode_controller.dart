import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// COMO a pessoa usa o app — eixo INDEPENDENTE do "Modo simples".
///
/// - [solo]: uso individual ("meu dinheiro, minhas metas"); o app fala no
///   singular e não empurra recursos de família.
/// - [grupo]: uso compartilhado (finanças e metas da família).
///
/// Regra de produto (auditoria): Solo/Grupo é uma escolha SEPARADA de
/// Simples/Completo — misturar as duas confunde. Padrão: [grupo] (preserva a
/// experiência atual de família).
enum UsageMode { solo, grupo }

class UsageModeController extends StateNotifier<UsageMode> {
  UsageModeController() : super(UsageMode.grupo) {
    _load();
  }

  static const _key = 'usage_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      state = UsageMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => UsageMode.grupo,
      );
    }
  }

  Future<void> set(UsageMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final usageModeProvider =
    StateNotifierProvider<UsageModeController, UsageMode>(
        (ref) => UsageModeController());
