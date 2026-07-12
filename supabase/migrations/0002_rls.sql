-- ============================================================
-- 0002_rls.sql — Row Level Security + RBAC
-- All family tables share data among members of the same
-- family_id. Roles: admin (full), user (write own data),
-- guest (read-only).
-- ============================================================

-- ---------- Helper functions (security definer avoids RLS recursion) ----------
create or replace function public.current_family_id()
returns uuid
language sql stable security definer set search_path = public
as $$
    select family_id from public.users where id = auth.uid();
$$;

create or replace function public.current_role_of_user()
returns user_role
language sql stable security definer set search_path = public
as $$
    select role from public.users where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce(public.current_role_of_user() = 'admin', false);
$$;

create or replace function public.can_write()
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce(public.current_role_of_user() in ('admin', 'user'), false);
$$;

-- ---------- FAMILIES ----------
alter table public.families enable row level security;

create policy families_select on public.families
    for select using (id = public.current_family_id());

create policy families_insert on public.families
    for insert with check (auth.uid() is not null);

create policy families_update on public.families
    for update using (id = public.current_family_id() and public.is_admin());

create policy families_delete on public.families
    for delete using (id = public.current_family_id() and public.is_admin());

-- ---------- USERS ----------
alter table public.users enable row level security;

create policy users_select on public.users
    for select using (
        id = auth.uid() or family_id = public.current_family_id()
    );

create policy users_insert_self on public.users
    for insert with check (id = auth.uid());

-- self-edit (profile) or admin manages family members
create policy users_update on public.users
    for update using (
        id = auth.uid()
        or (family_id = public.current_family_id() and public.is_admin())
    );

create policy users_delete on public.users
    for delete using (
        family_id = public.current_family_id() and public.is_admin()
    );

-- ---------- Generic family-scoped policies ----------
-- SELECT: any family member (including guest)
-- INSERT/UPDATE: admin + user
-- DELETE: admin only
do $$
declare
    t text;
begin
    foreach t in array array[
        'transactions', 'budgets', 'accounts_and_cards', 'inventory',
        'shopping_lists', 'meal_plans', 'financial_goals', 'bills_payable'
    ]
    loop
        execute format('alter table public.%I enable row level security', t);

        execute format($f$
            create policy %1$s_select on public.%1$I
                for select using (family_id = public.current_family_id())
        $f$, t);

        execute format($f$
            create policy %1$s_insert on public.%1$I
                for insert with check (
                    family_id = public.current_family_id() and public.can_write()
                )
        $f$, t);

        execute format($f$
            create policy %1$s_update on public.%1$I
                for update using (
                    family_id = public.current_family_id() and public.can_write()
                )
        $f$, t);

        execute format($f$
            create policy %1$s_delete on public.%1$I
                for delete using (
                    family_id = public.current_family_id() and public.is_admin()
                )
        $f$, t);
    end loop;
end $$;

-- ---------- AUDIT LOGS: family members read, nobody writes directly ----------
alter table public.audit_logs enable row level security;

create policy audit_select on public.audit_logs
    for select using (
        family_id = public.current_family_id() and public.is_admin()
    );
-- inserts happen only via security-definer trigger function

-- ---------- MARKETS: public read (reference data) ----------
alter table public.markets enable row level security;

create policy markets_select on public.markets
    for select using (auth.uid() is not null);
