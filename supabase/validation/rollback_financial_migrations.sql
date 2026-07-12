-- ============================================================
-- rollback_financial_migrations.sql — reversão das migrations financeiras
-- ============================================================
-- O trigger `apply_transaction_to_balance` e a coluna `balance` NUNCA foram
-- tocados (shadow vivo). Logo, reverter = voltar os leitores para `balance` e
-- remover os artefatos aditivos. `balance` está correto (imediato) → reversão
-- restaura o comportamento pré-F-3B na hora.
--
-- USE A SEÇÃO A (recomendada) para reverter só o MODELO DE SALDO (0006/0007/
-- 0008). A SEÇÃO B (0005) só se for descartar TAMBÉM o F-2 — e exige reverter
-- o Dart (Bill.toInsert/model), senão inserts de bill quebram.

-- ============================================================
-- SEÇÃO A — Rollback do modelo de saldo (0008 + 0007 + 0006)
-- ============================================================

-- A1) Restaurar dashboard_kpis original (lê accounts_and_cards.balance) [undo 0007]
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

-- A2) Remover a view (0006 + substituição 0008) [undo 0006/0008]
drop view if exists public.accounts_with_available;

-- A3) Remover índice de apoio [undo 0006]
drop index if exists public.idx_tx_account_date;

-- A4) Remover opening_balance [undo 0006]
alter table public.accounts_and_cards drop column if exists opening_balance;

-- IMPORTANTE (Dart): após a Seção A, o app AINDA aponta para
-- accounts_with_available (AccountRepository.all). Antes/junto do rollback,
-- reverter o Passo 2 no Dart (AccountRepository.all voltar a ler
-- accounts_and_cards). Sem isso, a leitura de contas quebra em runtime.

-- ============================================================
-- SEÇÃO B — Rollback do vínculo de bill (0005) — OPCIONAL/RARO
-- ============================================================
-- Só se for descartar o F-2. Exige antes reverter o Dart (Bill.toInsert deixar
-- de enviar account_id), senão os inserts de bill falham.
-- alter table public.bills_payable drop column if exists account_id;

-- ============================================================
-- Rollback PARCIAL (só cartão / 0008) — restaura a view do 0006
-- ============================================================
-- Use se apenas o comportamento de cartão precisar voltar, mantendo 0006/0007.
-- create or replace view public.accounts_with_available
--     with (security_invoker = true) as
-- select a.*, a.opening_balance + coalesce((
--     select sum(case when t.type = 'revenue' then t.amount else -t.amount end)
--     from public.transactions t
--     where t.account_id = a.id and t.date <= current_date), 0) as available
-- from public.accounts_and_cards a;
