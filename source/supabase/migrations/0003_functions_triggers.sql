-- ============================================================
-- 0003_functions_triggers.sql — automations, audit, RPCs
-- ============================================================

-- ---------- updated_at maintenance ----------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end $$;

create trigger trg_touch_users        before update on public.users            for each row execute function public.touch_updated_at();
create trigger trg_touch_transactions before update on public.transactions     for each row execute function public.touch_updated_at();
create trigger trg_touch_inventory    before update on public.inventory        for each row execute function public.touch_updated_at();
create trigger trg_touch_shopping     before update on public.shopping_lists   for each row execute function public.touch_updated_at();

-- ---------- Auto-create profile on signup ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.users (id, name, email, role)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
        new.email,
        'admin'  -- first device owner; joins to a family later or creates one
    )
    on conflict (id) do nothing;
    return new;
end $$;

create trigger trg_on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------- Audit trail for critical tables ----------
create or replace function public.write_audit_log()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    fam uuid;
begin
    fam := coalesce(
        (case when tg_op = 'DELETE' then (to_jsonb(old) ->> 'family_id')::uuid
              else (to_jsonb(new) ->> 'family_id')::uuid end),
        public.current_family_id()
    );
    insert into public.audit_logs (family_id, user_id, table_name, record_id, action, old_data, new_data)
    values (
        fam,
        auth.uid(),
        tg_table_name,
        coalesce((to_jsonb(coalesce(new, old)) ->> 'id'), ''),
        tg_op,
        case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
        case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
    );
    return coalesce(new, old);
end $$;

create trigger trg_audit_transactions after insert or update or delete on public.transactions       for each row execute function public.write_audit_log();
create trigger trg_audit_accounts     after insert or update or delete on public.accounts_and_cards for each row execute function public.write_audit_log();
create trigger trg_audit_budgets      after insert or update or delete on public.budgets            for each row execute function public.write_audit_log();
create trigger trg_audit_users        after update or delete on public.users                        for each row execute function public.write_audit_log();

-- ---------- Account balance maintenance ----------
create or replace function public.apply_transaction_to_balance()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    delta numeric(14,2);
    acc uuid;
begin
    if tg_op = 'INSERT' then
        acc := coalesce(new.account_id, new.card_id);
        if acc is not null then
            delta := case when new.type = 'revenue' then new.amount else -new.amount end;
            update public.accounts_and_cards set balance = balance + delta where id = acc;
        end if;
        return new;
    elsif tg_op = 'DELETE' then
        acc := coalesce(old.account_id, old.card_id);
        if acc is not null then
            delta := case when old.type = 'revenue' then -old.amount else old.amount end;
            update public.accounts_and_cards set balance = balance + delta where id = acc;
        end if;
        return old;
    elsif tg_op = 'UPDATE' then
        -- revert old, apply new
        acc := coalesce(old.account_id, old.card_id);
        if acc is not null then
            delta := case when old.type = 'revenue' then -old.amount else old.amount end;
            update public.accounts_and_cards set balance = balance + delta where id = acc;
        end if;
        acc := coalesce(new.account_id, new.card_id);
        if acc is not null then
            delta := case when new.type = 'revenue' then new.amount else -new.amount end;
            update public.accounts_and_cards set balance = balance + delta where id = acc;
        end if;
        return new;
    end if;
    return null;
end $$;

create trigger trg_tx_balance
    after insert or update or delete on public.transactions
    for each row execute function public.apply_transaction_to_balance();

-- ---------- Pantry automation: buying a shopping item feeds inventory ----------
create or replace function public.on_shopping_item_bought()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    inv_id uuid;
    paid numeric;
    market text;
begin
    -- Fires when a pending item is bought (UPDATE) or when an already-bought
    -- item arrives directly, e.g. from the OCR receipt flow (INSERT).
    if new.status = 'bought'
       and (tg_op = 'INSERT' or old.status = 'pending') then
        paid   := (new.execution_data ->> 'unit_price')::numeric;
        market := new.execution_data ->> 'market';

        if new.inventory_id is not null then
            inv_id := new.inventory_id;
        else
            select id into inv_id
            from public.inventory
            where family_id = new.family_id
              and lower(product_name) = lower(new.item_name)
            limit 1;
        end if;

        if inv_id is not null then
            update public.inventory
            set quantity = quantity + new.quantity,
                price_history = case
                    when paid is not null then
                        price_history || jsonb_build_array(jsonb_build_object(
                            'price', paid,
                            'market', coalesce(market, 'unknown'),
                            'date', to_char(now(), 'YYYY-MM-DD')))
                    else price_history
                end
            where id = inv_id;
        else
            insert into public.inventory (family_id, product_name, quantity, min_quantity, price_history)
            values (
                new.family_id, new.item_name, new.quantity, 1,
                case when paid is not null then
                    jsonb_build_array(jsonb_build_object(
                        'price', paid,
                        'market', coalesce(market, 'unknown'),
                        'date', to_char(now(), 'YYYY-MM-DD')))
                else '[]'::jsonb end
            );
        end if;
    end if;
    return new;
end $$;

create trigger trg_shopping_bought
    after insert or update on public.shopping_lists
    for each row execute function public.on_shopping_item_bought();

-- ---------- Pantry automation: low stock feeds shopping list ----------
create or replace function public.on_inventory_low_stock()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if new.quantity <= new.min_quantity and old.quantity > old.min_quantity then
        if not exists (
            select 1 from public.shopping_lists
            where family_id = new.family_id
              and status = 'pending'
              and (inventory_id = new.id or lower(item_name) = lower(new.product_name))
        ) then
            insert into public.shopping_lists (family_id, item_name, quantity, inventory_id, execution_data)
            values (
                new.family_id, new.product_name,
                greatest(new.min_quantity * 2 - new.quantity, 1),
                new.id,
                jsonb_build_object('auto_generated', true, 'reason', 'low_stock')
            );
        end if;
    end if;
    return new;
end $$;

create trigger trg_inventory_low_stock
    after update on public.inventory
    for each row execute function public.on_inventory_low_stock();

-- ---------- Recurring bills: paying one schedules the next ----------
create or replace function public.on_bill_paid()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if new.status = 'paid' and old.status = 'pending' then
        new.paid_at := now();
        if new.recurrence <> 'none' then
            insert into public.bills_payable (family_id, description, amount, due_date, status, recurrence)
            values (
                new.family_id, new.description, new.amount,
                case new.recurrence
                    when 'monthly' then new.due_date + interval '1 month'
                    when 'yearly'  then new.due_date + interval '1 year'
                end,
                'pending', new.recurrence
            );
        end if;
    end if;
    return new;
end $$;

create trigger trg_bill_paid
    before update on public.bills_payable
    for each row execute function public.on_bill_paid();

-- ---------- RPCs used by the app ----------

-- Executive KPIs for the dashboard in one round-trip
create or replace function public.dashboard_kpis()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
    fam uuid := public.current_family_id();
    result jsonb;
begin
    select jsonb_build_object(
        'total_balance', coalesce((
            select sum(balance) from accounts_and_cards
            where family_id = fam and type <> 'credit_card'), 0),
        'net_worth', coalesce((
            select sum(balance) from accounts_and_cards where family_id = fam), 0),
        'bills_pending', coalesce((
            select sum(amount) from bills_payable
            where family_id = fam and status = 'pending'), 0),
        'bills_overdue', coalesce((
            select sum(amount) from bills_payable
            where family_id = fam and status = 'pending' and due_date < current_date), 0),
        'month_expenses', coalesce((
            select sum(amount) from transactions
            where family_id = fam and type = 'expense'
              and date >= date_trunc('month', current_date)), 0),
        'month_revenue', coalesce((
            select sum(amount) from transactions
            where family_id = fam and type = 'revenue'
              and date >= date_trunc('month', current_date)), 0)
    ) into result;
    return result;
end $$;

-- Daily cash flow for the last N days (dashboard chart)
create or replace function public.daily_cash_flow(days_back int default 30)
returns table (day date, revenue numeric, expense numeric)
language sql stable security definer set search_path = public as $$
    select d::date as day,
           coalesce(sum(t.amount) filter (where t.type = 'revenue'), 0) as revenue,
           coalesce(sum(t.amount) filter (where t.type = 'expense'), 0) as expense
    from generate_series(current_date - (days_back - 1), current_date, '1 day') d
    left join public.transactions t
        on t.date = d::date and t.family_id = public.current_family_id()
    group by d::date
    order by d::date;
$$;

-- Spend by category in current month (treemap / pie)
create or replace function public.month_spend_by_category()
returns table (category text, total numeric)
language sql stable security definer set search_path = public as $$
    select category, sum(amount) as total
    from public.transactions
    where family_id = public.current_family_id()
      and type = 'expense'
      and date >= date_trunc('month', current_date)
    group by category
    order by total desc;
$$;

-- Weekday heatmap: avg spend per weekday over last 90 days
create or replace function public.weekday_heatmap()
returns table (weekday int, total numeric)
language sql stable security definer set search_path = public as $$
    select extract(isodow from date)::int as weekday, sum(amount) as total
    from public.transactions
    where family_id = public.current_family_id()
      and type = 'expense'
      and date >= current_date - 90
    group by 1
    order by 1;
$$;

-- Budget usage with linear-projection overflow probability inputs
create or replace function public.budget_usage()
returns table (
    budget_id uuid, category text, limit_amount numeric,
    spent numeric, avg_daily_history numeric
)
language sql stable security definer set search_path = public as $$
    select b.id,
           b.category,
           b.limit_amount,
           coalesce((
               select sum(t.amount) from public.transactions t
               where t.family_id = b.family_id and t.type = 'expense'
                 and t.category = b.category
                 and t.date >= date_trunc('month', current_date)), 0) as spent,
           coalesce((
               select sum(t.amount) / 90.0 from public.transactions t
               where t.family_id = b.family_id and t.type = 'expense'
                 and t.category = b.category
                 and t.date >= current_date - 90
                 and t.date <  date_trunc('month', current_date)), 0) as avg_daily_history
    from public.budgets b
    where b.family_id = public.current_family_id()
      and b.period = 'monthly';
$$;

-- Join a family by id (invited member flow)
create or replace function public.join_family(target_family uuid, member_role user_role default 'user')
returns void
language plpgsql security definer set search_path = public as $$
begin
    update public.users
    set family_id = target_family,
        role = case when public.current_family_id() is null then member_role else role end
    where id = auth.uid() and family_id is null;
end $$;

-- Create a family and become its admin
create or replace function public.create_family(family_name text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
    fam uuid;
begin
    insert into public.families (name) values (family_name) returning id into fam;
    update public.users set family_id = fam, role = 'admin' where id = auth.uid();
    return fam;
end $$;
