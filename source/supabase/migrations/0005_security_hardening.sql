-- Família ERP: hardening de RPCs e políticas de escrita.
-- Todas as funções abaixo exigem uma sessão autenticada; o cliente nunca
-- recebe privilégios de service_role.

-- Impede chamadas anônimas a funções que leem/escrevem dados de famílias.
revoke execute on function public.create_family(text) from anon;
revoke execute on function public.join_family(uuid, user_role) from anon;
revoke execute on function public.current_family_id() from anon;
revoke execute on function public.current_role_of_user() from anon;
revoke execute on function public.is_admin() from anon;
revoke execute on function public.can_write() from anon;
grant execute on function public.create_family(text) to authenticated;
grant execute on function public.join_family(uuid, user_role) to authenticated;

-- UPDATE precisa proteger também o novo valor; sem WITH CHECK um cliente
-- poderia tentar mover uma linha para outra família.
alter policy transactions_update on public.transactions
  with check (family_id = public.current_family_id() and public.can_write());
alter policy budgets_update on public.budgets
  with check (family_id = public.current_family_id() and public.can_write());
alter policy accounts_and_cards_update on public.accounts_and_cards
  with check (family_id = public.current_family_id() and public.can_write());
alter policy inventory_update on public.inventory
  with check (family_id = public.current_family_id() and public.can_write());
alter policy shopping_lists_update on public.shopping_lists
  with check (family_id = public.current_family_id() and public.can_write());
alter policy meal_plans_update on public.meal_plans
  with check (family_id = public.current_family_id() and public.can_write());
alter policy financial_goals_update on public.financial_goals
  with check (family_id = public.current_family_id() and public.can_write());
alter policy bills_payable_update on public.bills_payable
  with check (family_id = public.current_family_id() and public.can_write());
alter policy debts_update on public.debts
  with check (family_id = public.current_family_id() and public.can_write());
alter policy ai_memory_update on public.ai_memory
  with check (family_id = public.current_family_id() and public.can_write());

-- RPC de entrada não aceita que o chamador escolha admin. A autorização de
-- convite temporário deverá ser adicionada antes de abrir esse fluxo ao público.
create or replace function public.join_family(target_family uuid, member_role user_role default 'user')
returns void
language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if member_role not in ('user', 'guest') then
        raise exception 'invalid_member_role' using errcode = '22023';
    end if;
    if not exists (select 1 from public.families where id = target_family) then
        raise exception 'family_not_found' using errcode = 'P0002';
    end if;
    update public.users
    set family_id = target_family,
        role = case when public.current_family_id() is null then member_role else role end
    where id = auth.uid() and family_id is null;
end $$;

create or replace function public.create_family(family_name text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    fam uuid;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if family_name is null or char_length(btrim(family_name)) not between 1 and 120 then
        raise exception 'invalid_family_name' using errcode = '22023';
    end if;
    if not exists (select 1 from public.users where id = auth.uid()) then
        raise exception 'profile_not_found' using errcode = 'P0002';
    end if;
    insert into public.families (name) values (btrim(family_name)) returning id into fam;
    update public.users set family_id = fam, role = 'admin'
      where id = auth.uid() and family_id is null;
    return fam;
end $$;

-- Evita consultas analíticas abusivamente grandes.
create or replace function public.daily_cash_flow(days_back int default 30)
returns table (day date, revenue numeric, expense numeric)
language sql stable security definer set search_path = public as $$
    select d::date as day,
           coalesce(sum(t.amount) filter (where t.type = 'revenue'), 0) as revenue,
           coalesce(sum(t.amount) filter (where t.type = 'expense'), 0) as expense
    from generate_series(current_date - (least(greatest(coalesce(days_back, 30), 1), 366) - 1), current_date, '1 day') d
    left join public.transactions t
      on t.date = d::date and t.family_id = public.current_family_id()
    where auth.uid() is not null
    group by d::date
    order by d::date;
$$;
