import 'package:flutter/foundation.dart' show kReleaseMode;

/// Environment configuration.
///
/// Values are injected at build time:
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
class Env {
  /// Valores-sentinela usados como default quando o build NÃO passa os
  /// `--dart-define`. O guard [assertConfigured] compara contra estes mesmos
  /// valores para detectar um build não configurado (ver BUILD.md).
  static const _supabaseUrlPlaceholder = 'https://YOUR_PROJECT.supabase.co';
  static const _supabaseAnonKeyPlaceholder = 'YOUR_ANON_KEY';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _supabaseUrlPlaceholder,
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _supabaseAnonKeyPlaceholder,
  );

  /// When true, AI services (OCR, chat NLU) run against local mock engines
  /// instead of remote APIs — the full app works offline/demo.
  static const useMockAi =
      bool.fromEnvironment('USE_MOCK_AI', defaultValue: true);

  /// OCR real de nota fiscal habilitado? Enquanto false (padrão), o botão de
  /// escanear nota NÃO grava nada — o OCR atual é mock e gravaria dados
  /// fabricados. Ligar apenas quando houver backend de OCR real:
  /// `--dart-define=OCR_ENABLED=true`.
  static const ocrEnabled =
      bool.fromEnvironment('OCR_ENABLED', defaultValue: false);

  /// Chave da API da Anthropic para o assistente conversacional
  /// (`--dart-define=ANTHROPIC_API_KEY=sk-ant-...`). Sem a chave, o chat cai
  /// no motor offline de demonstração.
  ///
  /// ⚠️ Em produção, não embuta a chave no app cliente: faça proxy das
  /// chamadas por uma Supabase Edge Function que guarda a chave no servidor.
  static const anthropicApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

  /// Valores de dart-define podem ser extraídos de um app compilado. A chave
  /// direta fica disponível somente no desenvolvimento local; produção deve
  /// usar o proxy autenticado.
  static bool get hasAnthropicKey => !kReleaseMode && anthropicApiKey != '';

  /// Provedor OpenAI-compatible para o chat (Groq por padrão; Ollama local
  /// trocando AI_BASE_URL/AI_MODEL). Ex.:
  /// `--dart-define=AI_API_KEY=gsk_...` (Groq) ou
  /// `--dart-define=AI_BASE_URL=http://localhost:11434/v1
  ///  --dart-define=AI_MODEL=llama3.1 --dart-define=AI_API_KEY=ollama`.
  static const aiApiKey = String.fromEnvironment('AI_API_KEY');
  static bool get hasAiKey => !kReleaseMode && aiApiKey != '';
  static const aiBaseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'https://api.groq.com/openai/v1',
  );
  // Llama 4 Scout: melhor limite gratuito na Groq (30k tokens/min, medido
  // em 2026-07) e bom desempenho com function calling.
  static const aiModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'meta-llama/llama-4-scout-17b-16e-instruct',
  );

  /// Proxy de IA (Supabase Edge Function). Quando definido, o app envia as
  /// chamadas de IA para o proxy usando o token de sessão do usuário — a chave
  /// do Groq fica no servidor, nunca no app. Formato:
  /// `<supabaseUrl>/functions/v1/ai-proxy`.
  static const aiProxyUrl = String.fromEnvironment('AI_PROXY_URL');
  static const hasAiProxy = aiProxyUrl != '';

  /// Dev-only auto-login (never set these in production builds):
  /// `--dart-define=DEV_EMAIL=... --dart-define=DEV_PASSWORD=...`
  ///
  /// A2: mesmo que os defines sejam passados, o auto-login **nunca** vale em
  /// build release — `kReleaseMode` é `const`, então isto continua `const`.
  static const devEmail = String.fromEnvironment('DEV_EMAIL');
  static const devPassword = String.fromEnvironment('DEV_PASSWORD');
  static const hasDevLogin =
      !kReleaseMode && devEmail != '' && devPassword != '';

  /// A1: true quando o build não configurou o Supabase (vazio ou placeholder).
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseUrl != _supabaseUrlPlaceholder &&
      supabaseAnonKey.isNotEmpty &&
      supabaseAnonKey != _supabaseAnonKeyPlaceholder;

  /// A1: falha cedo e explícito quando o build não forneceu as credenciais do
  /// Supabase. Deve ser chamado no início de `main()`, antes de
  /// `Supabase.initialize`. Sem isto, o app subia com placeholders e o login
  /// quebrava silenciosamente.
  static void assertConfigured() {
    if (isSupabaseConfigured) return;
    final urlProblem = supabaseUrl.isEmpty
        ? 'ausente (vazio)'
        : (supabaseUrl == _supabaseUrlPlaceholder
            ? 'ainda no placeholder'
            : 'ok');
    final keyProblem = supabaseAnonKey.isEmpty
        ? 'ausente (vazio)'
        : (supabaseAnonKey == _supabaseAnonKeyPlaceholder
            ? 'ainda no placeholder'
            : 'ok');
    throw StateError(
      'Configuração do Supabase inválida — o app não pode iniciar com '
      'placeholders.\n'
      '  SUPABASE_URL: $urlProblem\n'
      '  SUPABASE_ANON_KEY: $keyProblem\n'
      'Forneça os valores no build via --dart-define:\n'
      '  --dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co\n'
      '  --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY\n'
      'Veja BUILD.md para o comando completo (web e APK).',
    );
  }
}
