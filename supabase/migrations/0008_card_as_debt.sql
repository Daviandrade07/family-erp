-- ============================================================
-- 0008_card_as_debt.sql — F-3D: cartão como dívida separada do caixa
-- ============================================================
-- Corrige o `available` do cartão: contas bancárias/investimento seguem no
-- saldo LIQUIDADO por data (F-3B); cartões (`credit_card`) usam o `balance`
-- shadow (mantido vivo pelo trigger) = DÍVIDA imediata do cartão, incorrida na
-- compra. Assim o cartão deixa de ter `available` congelado e nunca é contado
-- como caixa (total_balance/afford/payment_plan já excluem credit_card).
-- Só a expressão da view muda. Não toca trigger, tabela, dashboard nem Dart.

create or replace view public.accounts_with_available
    with (security_invoker = true) as
select
    a.*,
    case
        when a.type = 'credit_card' then a.balance
        else a.opening_balance + coalesce((
            select sum(case when t.type = 'revenue' then t.amount else -t.amount end)
            from public.transactions t
            where t.account_id = a.id
              and t.date <= current_date
        ), 0)
    end as available
from public.accounts_and_cards a;
