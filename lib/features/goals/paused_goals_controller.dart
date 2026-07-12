import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metas em "ritmo pausado" — guardadas no aparelho. Pausar tira a pressão: a
/// meta some das ativas e do "falta economizar", sem culpa, até a pessoa
/// retomar. (Persistência local por ora; sincroniza entre aparelhos quando a
/// coluna `paused` for adicionada ao banco.)
class PausedGoalsController extends StateNotifier<Set<String>> {
  PausedGoalsController() : super(const {}) {
    _load();
  }

  static const _key = 'paused_goals';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getStringList(_key) ?? const []).toSet();
  }

  Future<void> toggle(String id) async {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next.toList());
  }
}

final pausedGoalsProvider =
    StateNotifierProvider<PausedGoalsController, Set<String>>(
        (ref) => PausedGoalsController());
