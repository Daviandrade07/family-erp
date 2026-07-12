import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência "Modo simples" (opcional): quando ligada, a tela inicial mostra
/// poucos botões grandes e voz em primeiro lugar. Padrão: desligada (modo
/// completo). Persistida entre sessões.
class SimpleModeController extends StateNotifier<bool> {
  SimpleModeController() : super(false) {
    _load();
  }

  static const _key = 'simple_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final simpleModeProvider =
    StateNotifierProvider<SimpleModeController, bool>(
        (ref) => SimpleModeController());
