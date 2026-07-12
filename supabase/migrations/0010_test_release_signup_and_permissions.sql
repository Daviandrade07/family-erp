-- ============================================================
-- 0010_test_release_signup_and_permissions.sql
-- Fluxo de entrada para novos usuários e endurecimento para o release teste.
-- Preserva todos os dados/famílias existentes.
-- ============================================================

-- Novos cadastros recebem somente o perfil. A própria pessoa escolhe no app
-- entre usar sozinha, criar a família ou entrar por um convite. Isso evita que
-- o trigger crie uma família paralela e bloqueie o convite.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.users (id, name, email, role)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
        new.email,
        'user'
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

-- Perfis só podem nascer pelo trigger de Auth; família só pelas RPCs seguras.
drop policy if exists users_insert_self on public.users;
drop policy if exists families_insert on public.families;

-- Evita reavaliar auth.uid() para cada linha em leituras do perfil.
drop policy if exists users_select on public.users;
create policy users_select on public.users
    for select to authenticated
    using (
        id = (select auth.uid())
        or family_id = (select public.current_family_id())
    );

drop policy if exists users_update_own_profile on public.users;
create policy users_update_own_profile on public.users
    for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- Funções de trigger nunca devem ser uma API pública. As funções que o app
-- usa continuam disponíveis apenas para pessoas autenticadas.
revoke all on function public.touch_updated_at() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.write_audit_log() from public, anon, authenticated;
revoke all on function public.apply_transaction_to_balance() from public, anon, authenticated;
revoke all on function public.on_shopping_item_bought() from public, anon, authenticated;
revoke all on function public.on_inventory_low_stock() from public, anon, authenticated;
revoke all on function public.on_bill_paid() from public, anon, authenticated;

revoke all on function public.current_family_id() from public, anon;
revoke all on function public.current_role_of_user() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.can_write() from public, anon;
revoke all on function public.dashboard_kpis() from public, anon;
revoke all on function public.daily_cash_flow(integer) from public, anon;
revoke all on function public.month_spend_by_category() from public, anon;
revoke all on function public.weekday_heatmap() from public, anon;
revoke all on function public.budget_usage() from public, anon;

grant execute on function public.current_family_id() to authenticated;
grant execute on function public.current_role_of_user() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_write() to authenticated;
grant execute on function public.dashboard_kpis() to authenticated;
grant execute on function public.daily_cash_flow(integer) to authenticated;
grant execute on function public.month_spend_by_category() to authenticated;
grant execute on function public.weekday_heatmap() to authenticated;
grant execute on function public.budget_usage() to authenticated;

-- Índices de chaves estrangeiras apontados pelo advisor do Postgres.
create index if not exists idx_bills_account
    on public.bills_payable (account_id);
create index if not exists idx_shopping_inventory
    on public.shopping_lists (inventory_id);
create index if not exists idx_transactions_card
    on public.transactions (card_id);
