import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Configuração da IA em tempo de execução, com 3 modos (nesta prioridade):
///
/// 1. **Chave manual de desenvolvimento**: permitida apenas fora de release.
/// 2. **Proxy** (`AI_PROXY_URL` definido): chama a Supabase Edge Function
///    `ai-proxy` usando o token de sessão do usuário — a chave do Groq fica no
///    servidor, nunca no app público. É o modo recomendado.
/// 3. **Sem IA**: cai no motor offline de demonstração.
class AiConfig {
  static String _override = '';

  static const _key = 'ai_api_key_override';

  /// Em release, a IA usa o proxy e nenhum segredo é persistido no aparelho.
  static String get manualKey {
    if (kReleaseMode) return '';
    return _override.isNotEmpty ? _override : Env.aiApiKey;
  }

  static bool get _hasManualKey => manualKey.isNotEmpty;

  /// Usa a chave manual quando existe; senão o proxy quando configurado.
  static bool get usesProxy => !_hasManualKey && Env.hasAiProxy;

  /// Sessão logada (necessária para o proxy).
  static Session? get _session => Supabase.instance.client.auth.currentSession;

  /// A IA está disponível? (chave manual, ou proxy com usuário logado)
  static bool get available =>
      _hasManualKey || (Env.hasAiProxy && _session != null);

  /// Endpoint base das chamadas /chat/completions.
  static String get endpoint => usesProxy ? Env.aiProxyUrl : Env.aiBaseUrl;

  /// Cabeçalhos de autenticação conforme o modo.
  static Map<String, String> authHeaders() {
    if (usesProxy) {
      return {
        'authorization': 'Bearer ${_session?.accessToken ?? ''}',
        'apikey': Env.supabaseAnonKey,
      };
    }
    return {'authorization': 'Bearer $manualKey'};
  }

  /// Carrega a chave manual somente no desenvolvimento local.
  static Future<void> load() async {
    if (kReleaseMode) return;
    final prefs = await SharedPreferences.getInstance();
    _override = prefs.getString(_key) ?? '';
  }

  static Future<void> setKey(String value) async {
    if (kReleaseMode) {
      throw StateError('Chaves manuais não são permitidas em produção.');
    }
    _override = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_override.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, _override);
    }
  }
}
