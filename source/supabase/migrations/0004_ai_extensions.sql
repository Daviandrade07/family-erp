-- ============================================================
-- 0004_ai_extensions.sql — redefinição do assistente de IA
-- Prioridades/categorias em contas, dívidas, memória de
-- preferências e marca na despensa.
-- ============================================================

-- ---------- Contas a pagar: prioridade, categoria, pagamento ----------
create type bill_priority as enum ('muito_alta', 'alta', 'media', 'baixa');

alter table public.bills_payable
    add column if not exists priority bill_priority not null default 'media',
    add column if not exists category text,
    add column if not exists payment_method text,
    add column if not exists notes text;

create index if not exists idx_bills_priority
    on public.bills_payable (family_id, status, priority, due_date);

-- ---------- Dívidas ----------
create table if not exists public.debts (
    id               uuid primary key default gen_random_uuid(),
    family_id        uuid not null references public.families (id) on delete cascade,
    creditor         text not null,
    description      text,
    original_amount  numeric(14,2) not null check (original_amount > 0),
    remaining_amount numeric(14,2) not null check (remaining_amount >= 0),
    installments     smallint,
    interest_rate    numeric(6,3),           -- % ao mês
    priority         bill_priority not null default 'media',
    start_date       date not null default current_date,
    created_at       timestamptz not null default now()
);
create index if not exists idx_debts_family on public.debts (family_id);

alter table public.debts enable row level security;

create policy debts_select on public.debts
    for select using (family_id = public.current_family_id());
create policy debts_insert on public.debts
    for insert with check (
        family_id = public.current_family_id() and public.can_write());
create policy debts_update on public.debts
    for update using (
        family_id = public.current_family_id() and public.can_write());
create policy debts_delete on public.debts
    for delete using (
        family_id = public.current_family_id() and public.is_admin());

create trigger trg_audit_debts
    after insert or update or delete on public.debts
    for each row execute function public.write_audit_log();

-- ---------- Memória permanente do assistente (preferências) ----------
create table if not exists public.ai_memory (
    id          uuid primary key default gen_random_uuid(),
    family_id   uuid not null references public.families (id) on delete cascade,
    key         text not null,          -- ex.: mercado_favorito, marca_arroz
    value       text not null,
    updated_at  timestamptz not null default now(),
    unique (family_id, key)
);
create index if not exists idx_ai_memory_family on public.ai_memory (family_id);

alter table public.ai_memory enable row level security;

create policy ai_memory_select on public.ai_memory
    for select using (family_id = public.current_family_id());
create policy ai_memory_upsert on public.ai_memory
    for insert with check (
        family_id = public.current_family_id() and public.can_write());
create policy ai_memory_update on public.ai_memory
    for update using (
        family_id = public.current_family_id() and public.can_write());
create policy ai_memory_delete on public.ai_memory
    for delete using (
        family_id = public.current_family_id() and public.can_write());

-- ---------- Despensa: marca ----------
alter table public.inventory
    add column if not exists brand text;

-- ---------- Mercados da região de Indaiatuba ----------
insert into public.markets (name, cnpj, lat, lng) values
    ('Atacadão Indaiatuba',   '75.315.333/0001-06', -23.1120, -47.2270),
    ('Tenda Atacado Salto',   '01.157.555/0001-07', -23.1960, -47.2870),
    ('Assaí Atacadista Itu',  '06.057.223/0001-08', -23.2540, -47.2930),
    ('Paulistão Salto',       '50.948.381/0001-09', -23.2000, -47.2930),
    ('Carrefour Indaiatuba',  '45.543.915/0001-10', -23.0980, -47.2120)
on conflict (cnpj) do nothing;
