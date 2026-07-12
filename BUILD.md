# BUILD — Família ERP

Guia canônico de build. Toda configuração entra por `--dart-define` no momento
do build (ver `lib/core/config/env.dart`); não há `.env` lido em runtime.
Lista de variáveis e o que é proibido em produção: ver `.env.example`.

> ⚠️ O app **falha ao iniciar** (guard em `main.dart`) se `SUPABASE_URL` ou
> `SUPABASE_ANON_KEY` estiverem vazios ou com o placeholder padrão. Ou seja:
> **os dois defines abaixo são obrigatórios em todo build**, senão o login não
> funciona.

## Defines por tipo de build

| Define | web | APK | Observação |
|---|:---:|:---:|---|
| `SUPABASE_URL` | ✅ obrigatório | ✅ obrigatório | URL do projeto Supabase |
| `SUPABASE_ANON_KEY` | ✅ obrigatório | ✅ obrigatório | chave publishable/anon (pública por design) |
| `AI_PROXY_URL` | ✅ recomendado | ✅ recomendado | habilita a IA via proxy (sem chave no app) |
| `--base-href /family-erp/` | ✅ (GitHub Pages) | — | só web; casa com o subcaminho do Pages |

**Proibido em produção** (nunca passar nestes builds): `AI_API_KEY` (gsk_ no
cliente), `DEV_EMAIL`, `DEV_PASSWORD`. Detalhes em `.env.example`.

## Build Web (PWA / GitHub Pages)

```powershell
flutter build web --release --base-href /family-erp/ `
  --dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY `
  --dart-define=AI_PROXY_URL=https://SEU_PROJETO.supabase.co/functions/v1/ai-proxy
```

Saída: `build/web/`. O deploy no GitHub Pages é feito a partir dessa pasta
(o `build/web` tem seu próprio git de deploy — `git add -A; git commit; git push`).

## Build APK (Android)

Requer JDK 17 + Android SDK no ambiente:

```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot"
$env:ANDROID_HOME = "C:\Android\Sdk"
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY `
  --dart-define=AI_PROXY_URL=https://SEU_PROJETO.supabase.co/functions/v1/ai-proxy
```

Saída: `build/app/outputs/flutter-apk/app-release.apk` (assinado com as debug
keys — suficiente para instalar no próprio aparelho; **não** para a Play Store).

## Diferença web × APK

- **web** usa `--base-href /family-erp/` (subcaminho do GitHub Pages); o APK não.
- **APK** exige `JAVA_HOME`/`ANDROID_HOME`; o web não.
- Os `--dart-define` de Supabase e IA são **os mesmos** nos dois.

## Observações práticas do projeto atual

- **Servidor de IA:** a chave do Groq fica como secret na Edge Function
  (`GROQ_API_KEY`), nunca no build. Ver `.env.example`.
- **Dependência `record`:** o `pubspec.yaml` tem
  `dependency_overrides: record_linux: 1.3.1` — necessário para o build Android
  compilar (incompatibilidade de assinatura em versões antigas). Não remover.
- **Opcional (não incluído aqui):** estes comandos poderiam virar scripts
  `scripts/build-web.ps1` / `scripts/build-apk.ps1`. Fica como sugestão; hoje o
  projeto usa apenas os comandos acima.
