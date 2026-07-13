-- Metas pessoais — Fase Início KinFin (mockup dashboard-financeiro).
--
-- Hoje toda financial_goals pertence só à família (visão compartilhada).
-- A tela "Início · Modo Solo" precisa de metas PESSOAIS (só do dono, não
-- vistas por outros membros da família — mesma filosofia de privacidade do
-- Modo Solo já documentada em mode_scope.dart: "Solo = visão privada").
--
-- user_id null  = meta da família (comportamento de hoje, sem mudança).
-- user_id <uid> = meta pessoal, visível/editável só pelo dono.

alter table public.financial_goals
    add column user_id uuid references public.users (id) on delete cascade;

create index idx_goals_family_user on public.financial_goals (family_id, user_id);

-- As policies genéricas criadas em 0002_rls.sql (loop family-scoped) não
-- distinguem metas pessoais de metas da família — qualquer membro veria
-- TODAS as linhas, inclusive metas pessoais de outros. Substituímos as 4
-- policies de financial_goals por versões que respeitam a privacidade.

drop policy if exists financial_goals_select on public.financial_goals;
drop policy if exists financial_goals_insert on public.financial_goals;
drop policy if exists financial_goals_update on public.financial_goals;
drop policy if exists financial_goals_delete on public.financial_goals;

-- SELECT: metas da família (user_id null) + minhas próprias metas pessoais.
-- Meta pessoal de outro membro NÃO aparece.
create policy financial_goals_select on public.financial_goals
    for select using (
        family_id = public.current_family_id()
        and (user_id is null or user_id = auth.uid())
    );

-- INSERT: exige can_write() em QUALQUER caso (família ou pessoal) — um
-- guest (papel só-leitura) não pode criar nem meta da família nem meta
-- pessoal seguindo o RBAC já documentado no projeto ("guest: somente
-- leitura"). Meta pessoal só pode ser criada para si mesmo.
create policy financial_goals_insert on public.financial_goals
    for insert with check (
        family_id = public.current_family_id()
        and public.can_write()
        and (user_id is null or user_id = auth.uid())
    );

-- UPDATE: mesma regra do INSERT — can_write() sempre exigido; meta pessoal
-- só pode ser editada pelo próprio dono.
create policy financial_goals_update on public.financial_goals
    for update using (
        family_id = public.current_family_id()
        and public.can_write()
        and (user_id is null or user_id = auth.uid())
    );

-- DELETE: meta da família segue admin-only (como hoje); meta pessoal exige
-- can_write() (exclui guest) E ser o próprio dono.
create policy financial_goals_delete on public.financial_goals
    for delete using (
        family_id = public.current_family_id()
        and (
            (user_id is null and public.is_admin())
            or (user_id = auth.uid() and public.can_write())
        )
    );
