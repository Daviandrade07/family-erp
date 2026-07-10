/// Environment configuration.
///
/// Values are injected at build time:
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_ANON_KEY',
  );

  /// When true, AI services (OCR, chat NLU) run against local mock engines
  /// instead of remote APIs — the full app works offline/demo.
  static const useMockAi = bool.fromEnvironment('USE_MOCK_AI', defaultValue: true);

  /// Chave da API da Anthropic para o assistente conversacional
  /// (`--dart-define=ANTHROPIC_API_KEY=sk-ant-...`). Sem a chave, o chat cai
  /// no motor offline de demonstração.
  ///
  /// ⚠️ Em produção, não embuta a chave no app cliente: faça proxy das
  /// chamadas por uma Supabase Edge Function que guarda a chave no servidor.
  static const anthropicApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  static const hasAnthropicKey = anthropicApiKey != '';

  /// Provedor OpenAI-compatible para o chat (Groq por padrão; Ollama local
  /// trocando AI_BASE_URL/AI_MODEL). Ex.:
  /// `--dart-define=AI_API_KEY=gsk_...` (Groq) ou
  /// `--dart-define=AI_BASE_URL=http://localhost:11434/v1
  ///  --dart-define=AI_MODEL=llama3.1 --dart-define=AI_API_KEY=ollama`.
  static const aiApiKey = String.fromEnvironment('AI_API_KEY');
  static const hasAiKey = aiApiKey != '';
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
  static const devEmail = String.fromEnvironment('DEV_EMAIL');
  static const devPassword = String.fromEnvironment('DEV_PASSWORD');
  static const hasDevLogin = devEmail != '' && devPassword != '';
}
