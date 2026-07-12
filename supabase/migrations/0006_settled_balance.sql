-- ============================================================
-- 0006_settled_balance.sql — F-3B (Passo 1): base do saldo liquidado por data
-- ============================================================
-- Prepara o "saldo disponível liquidado" SEM reapontar nenhum leitor, SEM
-- tocar o trigger `apply_transaction_to_balance` e SEM alterar a coluna
-- `balance` (que permanece como shadow, garantindo rollback trivial).
-- Considera apenas transações por `account_id` (cartão/`card_id` fica para o
-- F-3D). Idempotente e aditivo.

-- 1) Saldo inicial da conta (a parte NÃO-transacional do saldo).
alter table public.accounts_and_cards
    add column if not exists opening_balance numeric(14,2) not null default 0;

-- 2) Backfill: opening_balance = balance atual − soma assinada das transações
--    da conta (mesmo sinal do trigger). Assim opening + Σ(todas as tx) = balance
--    (continuidade). Idempotente: balance e tx não mudam entre execuções.
update public.accounts_and_cards a
set opening_balance = a.balance - coalesce((
        select sum(case when t.type = 'revenue' then t.amount else -t.amount end)
        from public.transactions t
        where t.account_id = a.id
    ), 0);

-- 3) Índice de apoio à soma liquidada por conta + data (estritamente para a
--    fonte `available` abaixo). Aditivo.
create index if not exists idx_tx_account_date
    on public.transactions (account_id, date);

-- 4) Fonte do saldo disponível LIQUIDADO (`available`), como VIEW
--    security_invoker (Postgres 15+): respeita a RLS de accounts_and_cards e
--    transactions para o usuário logado (escopo por família).
--    available = opening_balance + Σ(tx da conta com date <= hoje, assinadas).
--    NÃO é lida por nenhum código ainda — apenas disponibilizada para o Passo 2.
create or replace view public.accounts_with_available
    with (security_invoker = true) as
select
    a.*,
    a.opening_balance + coalesce((
        select sum(case when t.type = 'revenue' then t.amount else -t.amount end)
        from public.transactions t
        where t.account_id = a.id
          and t.date <= current_date
    ), 0) as available
from public.accounts_and_cards a;
