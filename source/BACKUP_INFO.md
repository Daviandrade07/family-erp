# Backup — Família ERP

Backup do código-fonte completo + banco de dados (schema) + configuração.
Gerado em 2026-07-03.

## O que está incluído
- **Código-fonte completo**: `lib/`, `web/`, `android/`, `ios/`, `test/`.
- **Banco de dados** (`supabase/`): todo o schema, RLS, funções e triggers em
  `migrations/` (0001→0004) + dados de referência em `seed/`. É o suficiente
  para recriar o banco do zero. A Edge Function do proxy de IA está em
  `functions/ai-proxy/`.
- **Dependências**: `pubspec.yaml` (declaradas) + `pubspec.lock` (versões
  exatas resolvidas).
- **Configuração**: `.env.example` (variáveis de build, sem segredos).
- **Documentação**: `README.md` (este projeto) + este arquivo.

## O que foi EXCLUÍDO (regenerável, não precisa guardar)
- `build/` — saídas de build (APK, web). Recriável com `flutter build`.
- `.dart_tool/`, `.gradle/`, `.kotlin/` — caches de build.
- `.idea/`, `*.iml`, `supabase/.temp/` — arquivos de IDE/estado local.

## Segredos NÃO incluídos (guarde à parte, com segurança)
- Chave do Groq (`GROQ_API_KEY`) — fica como secret na Supabase Edge Function.
- Chave `service_role` do Supabase, access token do Supabase.
- A `SUPABASE_ANON_KEY` é pública por design (pode ir no cliente).

## Como restaurar
1. Extraia o ZIP e entre na pasta.
2. `flutter pub get`
3. Recriar o banco (projeto Supabase novo): rode em ordem no SQL Editor
   `supabase/migrations/0001` → `0004`, depois `seed/markets_indaiatuba.sql`
   e `seed/seed.sql`. (Ou `supabase db push` com a CLI.)
4. Configure os `--dart-define` conforme `.env.example`.
5. Deploy do proxy: `npx supabase functions deploy ai-proxy` e
   `npx supabase secrets set GROQ_API_KEY=...`.
6. Build: `flutter build web` / `flutter build apk` (ver `.env.example`).

## Backup dos DADOS ao vivo (opcional)
As migrations recriam a ESTRUTURA. Para um dump dos dados atuais dos usuários:
`supabase db dump --data-only -f dados.sql` (precisa da CLI + credenciais).
