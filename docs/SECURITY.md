# Bloqueios de Segurança — antes de QUALQUER publicação

Este documento é um **checklist de veto**. Se qualquer item abaixo falhar, **não se publica**.
A missão do produto (dar direção calma, sem pânico nem culpa) depende de o app ser
confiável: um vazamento de chave ou um bloqueio de acesso quebram a confiança mais do
que qualquer funcionalidade agrega.

---

## 1. Segredos nunca no cliente
- [ ] `grep -oE 'gsk_[A-Za-z0-9]+' build/web/main.dart.js | wc -l` **= 0** (chave Groq só existe
      como secret do Supabase Edge Function `GROQ_API_KEY`; o GitHub bloqueia push com `gsk_`).
- [ ] Nenhum `service_role`, token de Management API (`sbp_...`) ou senha no bundle.
- [ ] No cliente, **apenas** a chave pública (`sb_publishable_...`) e a URL do projeto.

## 2. Acesso não pode quebrar (a lição da Fernanda)
> Já perdemos acesso de usuária real porque a confirmação de e-mail foi ligada **sem
> entrega de e-mail funcionando**. Isso NUNCA pode se repetir.
- [ ] Se "Confirm email" estiver **ligado** no Supabase Auth, ENTÃO um provedor de e-mail
      transacional real (SMTP: Resend/SendGrid/etc.) está configurado **e testado ponta a ponta**
      (signup real → e-mail chega em < 60s → código de 6 dígitos válido).
- [ ] O template de e-mail de confirmação contém `{{ .Token }}` (código), não só `{{ .ConfirmationURL }}`.
- [ ] Rate limit de e-mail compatível com uso real (o SMTP embutido do Supabase, ~2–4/h, **não** serve para produção).
- [ ] Fluxo E2E validado num ambiente antes do prod: cadastro → bloqueio até confirmar →
      digitar código → sessão criada → login → família.

## 3. Autenticação e sessão são a fonte da verdade
- [ ] O nível de segurança da sessão vem de `auth.mfa.getAuthenticatorAssuranceLevel()`
      (`aal1`/`aal2`) — **não** de uma coluna gravável pelo app (`active_2fa` está proibido como
      fonte de verdade).
- [ ] Ações sensíveis (trocar senha, remover 2FA, exportar dados, sair da família, apagar conta)
      exigem **sessão AAL2** quando o usuário tem TOTP; caso contrário, pedem reautenticação.
- [ ] O código por e-mail confirma **posse do endereço**; **não** conta como segundo fator.

## 4. Grupo/Família com convite seguro
- [ ] Convite é **código temporário e revogável** (curto, com expiração e possibilidade de revogar),
      **não** o UUID permanente da família.
- [ ] RLS/RBAC por `family_id` em todas as tabelas; RPCs security-definer não vazam dados entre famílias.
- [ ] Entrar/sair de família não permite escalada de papel nem exposição de dados de outra família.

## 5. Qualidade mínima do build
- [ ] `flutter analyze` → **0 erros, 0 warnings** (infos toleradas).
- [ ] `flutter test` → **100% verdes**.
- [ ] Build web com os `--dart-define` corretos; patch do service worker (skipWaiting) reaplicado.
- [ ] Após deploy: `main.dart.js` remoto **byte-idêntico** ao local; **0** ocorrências de `gsk_`.

## 6. Privacidade e dados do usuário
- [ ] Exportação de dados (CSV) disponível — "seus dados são seus".
- [ ] Nada de PII em logs/telemetria do cliente.
- [ ] Consentimento explícito para qualquer conexão externa (ex.: Open Finance) — só com parceiro regulado.

---

### Procedimento de publicação (resumo)
1. `flutter analyze` (0/0) → `flutter test` (verdes).
2. `flutter build web --release ...` → reaplicar patch SW.
3. Verificar `gsk_` = 0 no bundle **local**.
4. Publicar (`build/web` → GitHub Pages).
5. Verificar remoto **byte-idêntico** + `gsk_` = 0.
6. Se mexeu em Auth: rodar o **teste E2E de acesso** (seção 2) antes de anunciar aos usuários.
