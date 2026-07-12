-- ============================================================
-- 0005_bill_account.sql — F-2: vínculo Bill ↔ Conta
-- ============================================================
-- Aditivo e idempotente. Quando uma bill vinculada a uma conta é paga, o app
-- gera uma despesa real nessa conta (lógica em BillRepository.markPaid); bills
-- sem conta seguem apenas como lembrete. Se a conta for removida, o vínculo
-- vira null (a bill continua como lembrete). Não altera RLS nem triggers.

alter table public.bills_payable
    add column if not exists account_id uuid
    references public.accounts_and_cards (id) on delete set null;
