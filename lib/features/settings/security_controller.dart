import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência local do bloqueio. [loaded] evita uma abertura sem proteção
/// enquanto a preferência ainda está sendo recuperada do aparelho.
class AppLockState {
  const AppLockState({required this.enabled, required this.loaded});

  final bool enabled;
  final bool loaded;
}

/// Proteção opcional persistida no dispositivo — o app nunca armazena dados
/// biométricos; apenas pede ao sistema para confirmar a identidade.
class AppLockController extends StateNotifier<AppLockState> {
  AppLockController()
      : super(const AppLockState(enabled: false, loaded: false)) {
    _load();
  }

  static const _key = 'app_lock_biometric';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppLockState(enabled: prefs.getBool(_key) ?? false, loaded: true);
  }

  Future<void> set(bool value) async {
    state = AppLockState(enabled: value, loaded: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>(
    (ref) => AppLockController());
