import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted light/dark/system preference. Defaults to dark (brand identity).
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      state = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.dark,
      );
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<void> toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
        (ref) => ThemeModeController());

/// Um acento nomeado que o usuário pode escolher. Personalização sóbria (a
/// versão discreta do "fundo aurora" de apps como o Pluma): recolore só o
/// elemento primário — botões, indicador de aba, foco —, mantendo superfícies
/// calmas e legibilidade intacta. Todos têm contraste suficiente para texto
/// branco por cima.
class AppAccent {
  const AppAccent(this.name, this.color);
  final String name;
  final Color color;
}

const kAppAccents = <AppAccent>[
  AppAccent('Menta', Color(0xFF5CC8B3)), // padrão (Casa Viva)
  AppAccent('Coral', Color(0xFFF19A78)),
  AppAccent('Índigo', Color(0xFF8174E8)),
  AppAccent('Âmbar', Color(0xFFE7B967)),
  AppAccent('Lagoa', Color(0xFF46AFC3)),
  AppAccent('Rosa', Color(0xFFE86C9A)),
];

/// Cor de acento persistida (primary do tema). Default = índigo da marca.
class AccentColorController extends StateNotifier<Color> {
  AccentColorController() : super(kAppAccents.first.color) {
    _load();
  }

  static const _key = 'accent_color';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) state = Color(v);
  }

  Future<void> set(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, color.toARGB32());
  }
}

final accentColorProvider =
    StateNotifierProvider<AccentColorController, Color>(
        (ref) => AccentColorController());

/// Modo privacidade (como em app de banco): quando ligado, os valores em R$
/// ficam ocultos até a pessoa escolher ver. Combina com o DNA "sem pânico" —
/// quem está num lugar público decide quando mostrar os números. Persistido.
class HideAmountsController extends StateNotifier<bool> {
  HideAmountsController() : super(false) {
    _load();
  }

  static const _key = 'hide_amounts';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final hideAmountsProvider =
    StateNotifierProvider<HideAmountsController, bool>(
        (ref) => HideAmountsController());
