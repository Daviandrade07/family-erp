-- ============================================================
-- 0001_schema.sql — Family ERP: core schema
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ---------- ENUMS ----------
create type user_role as enum ('admin', 'user', 'guest');
create type transaction_type as enum ('revenue', 'expense');
create type budget_period as enum ('monthly', 'yearly');
create type account_type as enum ('bank_account', 'credit_card', 'investment');
create type shopping_status as enum ('pending', 'bought');
create type bill_status as enum ('paid', 'pending');
create type bill_recurrence as enum ('none', 'monthly', 'yearly');

-- ---------- FAMILIES ----------
create table public.families (
    id          uuid primary key default gen_random_uuid(),
    name        text not null check (char_length(name) between 1 and 120),
    created_at  timestamptz not null default now()
);

-- ---------- USERS (profile, 1:1 with auth.users) ----------
create table public.users (
    id          uuid primary key references auth.users (id) on delete cascade,
    family_id   uuid references public.families (id) on delete set null,
    name        text not null,
    email       text not null unique,
    role        user_role not null default 'user',
    active_2fa  boolean not null default false,
    avatar_url  text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);
create index idx_users_family on public.users (family_id);

-- ---------- ACCOUNTS & CARDS ----------
create table public.accounts_and_cards (
    id            uuid primary key default gen_random_uuid(),
    family_id     uuid not null references public.families (id) on delete cascade,
    name          text not null,
    type          account_type not null,
    balance       numeric(14,2) not null default 0,
    credit_limit  numeric(14,2),
    closing_day   smallint check (closing_day between 1 and 31),
    due_day       smallint check (due_day between 1 and 31),
    created_at    timestamptz not null default now()
);
create index idx_accounts_family on public.accounts_and_cards (family_id);

-- ---------- TRANSACTIONS ----------
create table public.transactions (
    id                  uuid primary key default gen_random_uuid(),
    family_id           uuid not null references public.families (id) on delete cascade,
    user_id             uuid not null references public.users (id) on delete restrict,
    type                transaction_type not null,
    amount              numeric(14,2) not null check (amount > 0),
    category            text not null,
    subcategory         text,
    description         text,
    receipt_url         text,
    date                date not null default current_date,
    payment_method      text,
    card_id             uuid references public.accounts_and_cards (id) on delete set null,
    account_id          uuid references public.accounts_and_cards (id) on delete set null,
    installment_number  smallint check (installment_number >= 1),
    total_installments  smallint check (total_installments >= 1),
    lat                 double precision,
    lng                 double precision,
    beneficiary         text,
    tags                text[] not null default '{}',
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    constraint chk_installments
        check (installment_number is null or total_installments is null
               or installment_number <= total_installments)
);
create index idx_tx_family_date     on public.transactions (family_id, date desc);
create index idx_tx_family_category on public.transactions (family_id, category);
create index idx_tx_user            on public.transactions (user_id);
create index idx_tx_tags            on public.transactions using gin (tags);

-- ---------- BUDGETS ----------
create table public.budgets (
    id            uuid primary key default gen_random_uuid(),
    family_id     uuid not null references public.families (id) on delete cascade,
    category      text not null,
    limit_amount  numeric(14,2) not null check (limit_amount > 0),
    period        budget_period not null default 'monthly',
    created_at    timestamptz not null default now(),
    unique (family_id, category, period)
);
create index idx_budgets_family on public.budgets (family_id);

-- ---------- INVENTORY (pantry) ----------
create table public.inventory (
    id               uuid primary key default gen_random_uuid(),
    family_id        uuid not null references public.families (id) on delete cascade,
    product_name     text not null,
    quantity         numeric(10,2) not null default 0 check (quantity >= 0),
    min_quantity     numeric(10,2) not null default 1,
    unit             text not null default 'un',
    expiration_date  date,
    location         text,
    category         text,
    price_history    jsonb not null default '[]'::jsonb,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now()
);
create index idx_inventory_family     on public.inventory (family_id);
create index idx_inventory_expiration on public.inventory (family_id, expiration_date);
create index idx_inventory_prices     on public.inventory using gin (price_history);

-- ---------- SHOPPING LISTS ----------
create table public.shopping_lists (
    id              uuid primary key default gen_random_uuid(),
    family_id       uuid not null references public.families (id) on delete cascade,
    item_name       text not null,
    quantity        numeric(10,2) not null default 1,
    status          shopping_status not null default 'pending',
    execution_data  jsonb not null default '{}'::jsonb,
    inventory_id    uuid references public.inventory (id) on delete set null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);
create index idx_shopping_family_status on public.shopping_lists (family_id, status);

-- ---------- MEAL PLANS ----------
create table public.meal_plans (
    id          uuid primary key default gen_random_uuid(),
    family_id   uuid not null references public.families (id) on delete cascade,
    week_start  date not null,
    menu_data   jsonb not null default '{}'::jsonb,
    created_at  timestamptz not null default now(),
    unique (family_id, week_start)
);
create index idx_meals_family on public.meal_plans (family_id, week_start desc);

-- ---------- FINANCIAL GOALS ----------
create table public.financial_goals (
    id              uuid primary key default gen_random_uuid(),
    family_id       uuid not null references public.families (id) on delete cascade,
    name            text not null,
    target_amount   numeric(14,2) not null check (target_amount > 0),
    current_amount  numeric(14,2) not null default 0 check (current_amount >= 0),
    deadline        date,
    created_at      timestamptz not null default now()
);
create index idx_goals_family on public.financial_goals (family_id);

-- ---------- BILLS PAYABLE ----------
create table public.bills_payable (
    id           uuid primary key default gen_random_uuid(),
    family_id    uuid not null references public.families (id) on delete cascade,
    description  text not null,
    amount       numeric(14,2) not null check (amount > 0),
    due_date     date not null,
    status       bill_status not null default 'pending',
    recurrence   bill_recurrence not null default 'none',
    paid_at      timestamptz,
    created_at   timestamptz not null default now()
);
create index idx_bills_family_due on public.bills_payable (family_id, status, due_date);

-- ---------- AUDIT LOG (critical changes, structured) ----------
create table public.audit_logs (
    id          bigint generated always as identity primary key,
    family_id   uuid,
    user_id     uuid,
    table_name  text not null,
    record_id   text not null,
    action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
    old_data    jsonb,
    new_data    jsonb,
    created_at  timestamptz not null default now()
);
create index idx_audit_family_time on public.audit_logs (family_id, created_at desc);

-- ---------- MARKETS (partner/fictional, for the shopping recommender) ----------
create table public.markets (
    id          uuid primary key default gen_random_uuid(),
    name        text not null,
    cnpj        text unique,
    lat         double precision not null,
    lng         double precision not null,
    created_at  timestamptz not null default now()
);
