import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência "Bloquear o app com biometria": quando ligada, o app pede
/// digital/rosto ao voltar do segundo plano. Proteção principal recomendada
/// (mais simples que o 2FA por app autenticador). Persistida entre sessões.
class AppLockController extends StateNotifier<bool> {
  AppLockController() : super(false) {
    _load();
  }

  static const _key = 'app_lock_biometric';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    if (value) {
      // O toggle não deve prender usuários em aparelhos sem Face ID/digital.
      // A tela pode habilitar a opção apenas após validar a disponibilidade.
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setBool(_key, value);
    if (saved) state = value;
  }
}

final appLockProvider =
    StateNotifierProvider<AppLockController, bool>((ref) => AppLockController());
