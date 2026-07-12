# Kinfin — ERP Familiar Inteligente 🏠

Plataforma premium de gestão doméstica com IA: finanças compartilhadas, orçamentos preditivos, despensa, lista de compras otimizada por geolocalização, cardápio semanal e assistente conversacional.

**Stack:** Flutter (Android/iOS/Web) · Riverpod · go_router · fl_chart · Supabase (Auth + PostgreSQL + RLS)

---

## Estrutura

```
kinfin/
├── supabase/
│   ├── migrations/
│   │   ├── 0001_schema.sql              # Tabelas, enums, FKs, índices
│   │   ├── 0002_rls.sql                 # RLS por family_id + RBAC (admin/user/guest)
│   │   ├── 0003_functions_triggers.sql  # Auditoria, automações, RPCs de analytics
│   │   └── 0004_ai_extensions.sql       # Prioridade/categoria, dívidas, IA + mercados
│   └── seed/markets_indaiatuba.sql      # Seed OFICIAL de mercados (Indaiatuba-SP)
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── config/env.dart              # SUPABASE_URL / ANON_KEY via --dart-define
│   │   ├── theme/app_theme.dart         # Design System (slate + neon green, Inter)
│   │   ├── router/app_router.dart       # go_router + shell responsivo (rail/bottom bar)
│   │   ├── utils/formatters.dart
│   │   └── widgets/app_widgets.dart     # KpiCard, StatusBadge, DynamicProgressBar...
│   ├── data/
│   │   ├── models/models.dart
│   │   └── repositories/repositories.dart
│   ├── services/ai/
│   │   ├── budget_prediction_agent.dart # Probabilidade de estouro de orçamento
│   │   ├── ocr_service.dart             # Leitura estruturada de nota fiscal (mock plugável)
│   │   ├── chat_assistant_service.dart  # NL → dados estruturados (tabelas + gráficos)
│   │   ├── shopping_recommender.dart    # 1 mercado vs dividir lista (preço + deslocamento)
│   │   └── meal_suggester.dart          # Cardápio semanal guiado pela despensa
│   └── features/                        # auth, dashboard, transactions, budgets,
│                                        # accounts, inventory, shopping, meals,
│                                        # goals, bills, chat, settings
└── test/
```

## Setup

### 1. Banco (Supabase)

1. Crie um projeto em [supabase.com](https://supabase.com).
2. Rode as migrations **na ordem** (SQL Editor ou `supabase db push`):
   `0001_schema.sql` → `0002_rls.sql` → `0003_functions_triggers.sql` →
   `0004_ai_extensions.sql`; e por fim o **seed oficial de mercados**
   `seed/markets_indaiatuba.sql` (fonte canônica única, idempotente — **não**
   use `seed/seed.sql`, que foi desativado).
3. Em **Authentication → Providers**, habilite Email. Para o fluxo de 2FA, habilite **MFA (TOTP)**.

### 2. App Flutter

```bash
flutter create . --platforms=android,ios,web   # gera as pastas de plataforma
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY
```

> **Biometria (Android):** em `android/app/src/main/AndroidManifest.xml` adicione `USE_BIOMETRIC`, e faça `MainActivity` estender `FlutterFragmentActivity` (requisito do `local_auth`).
> **iOS:** adicione `NSFaceIDUsageDescription` e `NSCameraUsageDescription` ao `Info.plist`.

### 3. Testes

```bash
flutter test
```

## Segurança e regras de negócio

- **RLS por `family_id`** em todas as tabelas: membros só enxergam dados da própria família.
- **RBAC**: `admin` (controle total, gerencia papéis e deleta), `user` (cria/edita), `guest` (somente leitura) — imposto no banco (policies) e refletido na UI.
- **Auditoria**: triggers gravam INSERT/UPDATE/DELETE de transações, contas, orçamentos e usuários em `audit_logs` (leitura restrita a admins).
- **2FA TOTP** via Supabase MFA + **biometria local** (local_auth) após o login.
- Criptografia em repouso: nativa do Postgres gerenciado do Supabase (AES-256).

## Automações no banco

- Transação criada/editada/excluída → saldo da conta/cartão recalculado.
- Item comprado na lista → entra na despensa + histórico de preços (`price_history`).
- Despensa abaixo do mínimo → item entra sozinho na lista de compras.
- Conta recorrente paga → próxima cobrança agendada automaticamente.
- Compra parcelada no crédito → N lançamentos mensais gerados.

## Chat IA com a API da Anthropic (Claude)

O assistente do chat usa o modelo `claude-opus-4-8` com **function calling** no
Supabase. Ative passando a chave na build:

```bash
flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-... (demais defines)
```

- **Escopo estrito**: só responde sobre finanças da família e mercados de
  **Indaiatuba-SP** (recusa educadamente qualquer outro assunto).
- **Registro por voz/texto**: "gastei 50 reais no posto" → extrai valor,
  categoria e data e grava via `add_transaction` (com confirmação quando os
  dados forem ambíguos). Toda operação usa o cliente Supabase autenticado —
  RLS garante o vínculo com `user_id`/`family_id`.
- **Consultoria de economia**: analisa histórico, aponta supérfluos e sugere
  metas realistas de redução.
- **Inteligência de preços**: compara os mercados de Indaiatuba
  (`supabase/seed/markets_indaiatuba.sql`) e consolida a lista da semana.
- **Gráficos**: gerados no chat somente quando pedidos explicitamente
  (ferramenta `render_chart`).
- **Áudio**: botão de microfone no chat transcreve a fala (pt-BR) via
  `speech_to_text` no dispositivo.
- Sem a chave, o chat cai no motor offline de demonstração.
- ⚠️ **Produção**: não embuta a chave no app — faça proxy via Supabase Edge
  Function.

## IA (offline por padrão, `USE_MOCK_AI=true`)

| Serviço | O que faz |
|---|---|
| **Agente de Predição** | Combina ritmo do mês com média histórica de 90 dias, mede volatilidade diária e converte em probabilidade de estouro (curva logística). Aparece no dashboard, nos orçamentos e no chat. |
| **OCR de Nota Fiscal** | Foto → itens, valores, CNPJ e data; preenche a despesa e alimenta o histórico de preços da despensa. Interface `OcrService` pronta para ML Kit/Textract. |
| **Chat IA** | Português natural → intents → consultas reais → resposta com texto, tabela e mini-gráfico no corpo do chat. Trocar o parser por um LLM mantém o mesmo contrato. |
| **Recomendador de Compras** | Cota cada item nos mercados via `price_history`, soma custo de deslocamento (haversine × R$/km + custo por parada) e decide: tudo em um mercado ou dividir a lista. |
| **Cardápio Semanal** | Prioriza ingredientes vencendo/em excesso na despensa e lista o que falta comprar. |
