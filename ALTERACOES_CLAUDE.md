# Alterações — Família ERP (assistente Claude)

Resumo das mudanças feitas no código-fonte, o estado de cada frente, e o que
você precisa fazer para rodar/compilar e configurar o Supabase.

> **Segurança:** este pacote **não contém segredos**. As chaves (Supabase,
> Groq/IA, Resend) entram via `--dart-define` no build ou como *secrets* no
> servidor. Veja `.env.example` e a seção "Configurações no Supabase".

---

## 1. Arquivos alterados / criados e o que cada um faz

### Identidade visual e layout (redesign estilo "Pluma"/premium)
| Arquivo | O que mudou |
|---|---|
| `lib/core/theme/app_theme.dart` | **Tipografia serifada (Fraunces)** nos números grandes e títulos, mantendo Inter no corpo. Tema passou a aceitar uma **cor de acento** parametrizável (`AppTheme.light({accent})` / `dark({accent})`). Números tabulares. |
| `lib/main.dart` | Liga a cor de acento escolhida pelo usuário ao tema (`accentColorProvider`). |
| `lib/features/settings/theme_controller.dart` | Novo `AccentColorController` + lista `kAppAccents` (6 tons sóbrios) persistida em `shared_preferences`. |
| `lib/features/transactions/transactions_screen.dart` | **Resumo do mês** no topo (Receitas/Despesas/Saldo com KPIs reais) + **agrupamento por dia** com subtotais ("Hoje/Ontem/data"), com proteção de honestidade no limite de paginação. |
| `lib/features/goals/goals_screen.dart` | **Resumo 2×2** (Metas ativas / Total acumulado / Falta economizar / Concluídas) + cards com "Faltam R$X" e barra de progresso. |
| `lib/features/budgets/budgets_screen.dart` | **Resumo Orçado/Gasto/Sobra** no topo + linha "Ainda pode gastar R$X / Estourou R$X" por card. |
| `lib/features/cards/cards_screen.dart` | **NOVO.** Tela de Cartões/Faturas: "Fatura do mês" + gráfico de 6 meses (fl_chart) + abas Todos/Compras/Parcelas + seletor de cartão. |
| `lib/features/accounts/accounts_screen.dart` | Ação "Faturas" na AppBar e cartões de crédito tocáveis → `/cards`. |
| `lib/features/settings/settings_screen.dart` | **Seletor de cor de acento**; selo de 2FA agora reflete o estado REAL (ver auth); AAL2 exigido em exportar CSV e trocar de família. |

### Autenticação e segurança (sprint de auth)
| Arquivo | O que mudou |
|---|---|
| `lib/data/repositories/repositories.dart` | `verifyEmailOtp`/`resendSignupCode` (fluxo oficial signUp→verifyOTP); **removido `mark_2fa_active`** (selo gravável); `hasAal2` (nível REAL da sessão), `hasVerifiedTotp`, `elevateToAal2`; `byCard` (faturas). |
| `lib/features/auth/auth_controller.dart` | Passthroughs de OTP/AAL2 + `twoFactorActiveProvider` (fonte da verdade do 2FA = sessão, não coluna). |
| `lib/features/auth/auth_screen.dart` | Cadastro que exige confirmação navega para a tela de código `/confirm-email`. |
| `lib/features/auth/email_otp_screen.dart` | **NOVO.** Tela própria de **código de 6 dígitos** (reenvio em 60s, mensagens anti-enumeração, e-mail mascarado). |
| `lib/features/auth/aal2_guard.dart` | **NOVO.** `requireAal2()` — pede o código do app autenticador antes de ações sensíveis, **só** se a pessoa tem 2FA e a sessão ainda é AAL1. |
| `lib/core/router/app_router.dart` | Rotas `/cards` e `/confirm-email` (esta liberada no redirect `signedOut`). |

### Documentação
| Arquivo | O que é |
|---|---|
| `docs/SECURITY.md` | **NOVO.** Checklist de bloqueios de veto antes de publicar (segredos, acesso, AAL2, convite, build). |
| `docs/DESIGN_SYSTEM.md` | Régua de identidade (cores, voz, bússola→estrela). |
| `ALTERACOES_CLAUDE.md` | Este arquivo. |

---

## 2. O que ainda NÃO está pronto

**Fase A (cliente) — falta:**
- **Dois eixos separados:** Solo/Grupo (quem usa) ≠ Simples/Completo (como mostra). Hoje "modo simples" é um toggle e solo/grupo é implícito.
- **Ritmos de meta:** confortável / acelerar / pausar (sem ranking familiar).

**Fase B (backend) — falta:**
- **Verificar um domínio no Resend** e então **ligar a confirmação de e-mail** (`mailer_autoconfirm=false`) + teste E2E de acesso. *Hoje está DESLIGADA de propósito* — sem domínio verificado o Resend só entrega para o e-mail dono da conta; ligar agora trancaria famílias novas para fora.
- **Convite temporário e revogável:** hoje o convite ainda é o **UUID permanente** da família. Falta uma tabela + RPC de convite com código curto, expiração e revogação.

**Limpeza opcional no banco (não urgente):** a coluna `active_2fa` e o RPC `mark_2fa_active` ficaram **sem uso** (o 2FA agora é lido da sessão). Podem ser removidos numa migração futura.

---

## 3. Como executar e compilar

Pré-requisitos: Flutter (canal stable recente), Dart. `flutter doctor` sem erros.

```bash
flutter pub get
```

**Rodar no navegador (dev):**
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=SUA_CHAVE_PUBLISHABLE \
  --dart-define=AI_PROXY_URL=https://SEU_PROJETO.supabase.co/functions/v1/ai-proxy
```

**Build web (PWA / GitHub Pages):**
```bash
flutter build web --release --base-href /family-erp/ \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=AI_PROXY_URL=...
```

**Build Android (APK):**
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=AI_PROXY_URL=...
```

**Qualidade antes de publicar:** `flutter analyze` (0 erros/warnings) e `flutter test` (todos verdes). Ver `docs/SECURITY.md`.

> Os valores das variáveis estão documentados em `.env.example` (com placeholders).
> Se existir `BUILD.md`, ele traz o guia canônico de build.

---

## 4. Configurações externas no Supabase

1. **Migrações do banco** — aplicar tudo em `supabase/migrations/` (via `supabase db push` com a CLI, ou colando no SQL editor). Inclui RLS/RBAC por `family_id`, RPCs (`create_family`, `join_family`, `switch_to_family`, `dashboard_kpis`, etc.) e triggers.

2. **Edge Function `ai-proxy`** — faz proxy da IA (Groq) guardando a chave no servidor:
   ```bash
   npx supabase functions deploy ai-proxy
   npx supabase secrets set GROQ_API_KEY=gsk_xxx   # SÓ no servidor, nunca no app
   ```

3. **Auth / e-mail (para o código de 6 dígitos)** — no Auth Settings do projeto:
   - **SMTP** apontando para o Resend (host `smtp.resend.com`, porta `465`, user `resend`, senha = API key do Resend).
   - **Remetente:** um endereço de um **domínio verificado no Resend** (obrigatório para entregar a famílias reais; sem domínio, o Resend só entrega para o dono da conta).
   - **Template de confirmação** contendo `{{ .Token }}` (o código). Assunto sugerido: "Seu código do Família ERP".
   - **Comprimento do OTP = 6**.
   - **Confirmar e-mail (`Confirm email`)**: manter **desligado** até o domínio estar verificado e o teste E2E passar; então ligar. Enquanto desligado, o cadastro cria sessão direto (a tela de código não aparece).
   - **URL allow-list** deve incluir a URL do app (ex.: a URL do GitHub Pages).

4. **2FA (TOTP)** — já suportado nativamente pelo Supabase MFA; o app usa `getAuthenticatorAssuranceLevel()` para exigir **AAL2** em ações sensíveis. Nada a configurar além de habilitar MFA no projeto (padrão).
