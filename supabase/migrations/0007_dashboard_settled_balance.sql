-- ============================================================
-- 0007_dashboard_settled_balance.sql — F-3B (Passo 3)
-- ============================================================
-- Alinha o dashboard ao SALDO LIQUIDADO por data: `total_balance` e
-- `net_worth` passam a somar `available` (da view `accounts_with_available`,
-- migration 0006) em vez do saldo shadow `accounts_and_cards.balance`.
-- Só a FONTE de saldo muda; os demais KPIs (bills/month_*) ficam idênticos.
-- Não toca trigger, coluna `balance`, AccountRepository nem cartão.

create or replace function public.dashboard_kpis()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
    fam uuid := public.current_family_id();
    result jsonb;
begin
    select jsonb_build_object(
        -- F-3B: saldo disponível liquidado (exclui cartão, como antes).
        'total_balance', coalesce((
            select sum(available) from accounts_with_available
            where family_id = fam and type <> 'credit_card'), 0),
        -- F-3B: patrimônio pelo saldo liquidado (inclui todas as contas).
        'net_worth', coalesce((
            select sum(available) from accounts_with_available
            where family_id = fam), 0),
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
