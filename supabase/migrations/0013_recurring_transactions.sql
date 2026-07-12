-- Frente 2 — Recorrentes (assinaturas, salário, aluguel).
-- Modelada pensando no mordomo de IA (Fase 3): started_at + frequency +
-- interval_count permitem dizer "assinatura X repete há N meses"; a ligação
-- transactions.recurring_id permite comparar valores gerados ao longo do tempo
-- ("essa cobrança aumentou"). auto_post=false por padrão: a IA sugere, não posta
-- sozinha (DNA do produto).

create type recurrence_frequency as enum ('weekly', 'monthly', 'yearly');

create table public.recurring_transactions (
    id             uuid primary key default gen_random_uuid(),
    family_id      uuid not null references public.families (id) on delete cascade,
    user_id        uuid not null references public.users (id) on delete restrict,
    type           transaction_type not null,
    amount         numeric(14,2) not null check (amount > 0),
    category       text not null,
    description    text,
    frequency      recurrence_frequency not null,
    interval_count smallint not null default 1 check (interval_count >= 1),
    started_at     date not null,
    next_run       date not null,
    last_run       date,
    end_at         date,
    active         boolean not null default true,
    auto_post      boolean not null default false,
    account_id     uuid references public.accounts_and_cards (id) on delete set null,
    card_id        uuid references public.accounts_and_cards (id) on delete set null,
    created_at     timestamptz not null default now()
);

create index idx_recurring_family_active
    on public.recurring_transactions (family_id, active, next_run);

alter table public.recurring_transactions enable row level security;

create policy recurring_transactions_select on public.recurring_transactions
    for select using (family_id = public.current_family_id());
create policy recurring_transactions_insert on public.recurring_transactions
    for insert with check (
        family_id = public.current_family_id() and public.can_write()
    );
create policy recurring_transactions_update on public.recurring_transactions
    for update using (
        family_id = public.current_family_id() and public.can_write()
    );
create policy recurring_transactions_delete on public.recurring_transactions
    for delete using (
        family_id = public.current_family_id() and public.is_admin()
    );

-- Liga cada transação gerada à sua regra (matéria-prima do mordomo).
alter table public.transactions
    add column if not exists recurring_id uuid
    references public.recurring_transactions (id) on delete set null;
