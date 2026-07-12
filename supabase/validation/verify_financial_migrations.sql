-- ============================================================
-- verify_financial_migrations.sql — conferência pós-migration (SOMENTE LEITURA)
-- ============================================================
-- Rodar em STAGING/teste DEPOIS de aplicar, na ordem: 0005 → 0006 → 0007 → 0008.
-- Todas as queries são SELECT (não alteram nada). Ao lado de cada uma está o
-- RESULTADO ESPERADO. Onde diz "0 linhas", qualquer linha retornada = problema.

-- ------------------------------------------------------------
-- V1 — 0005: bills_payable.account_id (coluna + FK)
-- ------------------------------------------------------------
-- Esperado: 1 linha, is_nullable = YES, data_type = uuid
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'bills_payable'
  and column_name = 'account_id';

-- Esperado: 1 linha (FK account_id -> accounts_and_cards, on delete set null)
select conname, confdeltype
from pg_constraint
where conrelid = 'public.bills_payable'::regclass and contype = 'f'
  and conname like '%account_id%';

-- ------------------------------------------------------------
-- V2 — 0006: opening_balance existe e backfill fecha (continuidade)
-- ------------------------------------------------------------
-- Esperado: 1 linha, is_nullable = NO, default 0
select column_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'accounts_and_cards'
  and column_name = 'opening_balance';

-- Continuidade: opening_balance + Σ(tx assinadas por account_id) DEVE = balance
-- para TODA conta. Esperado: 0 linhas.
select a.id, a.name, a.balance, a.opening_balance,
       a.opening_balance + coalesce((
           select sum(case when t.type = 'revenue' then t.amount else -t.amount end)
           from public.transactions t where t.account_id = a.id), 0) as recomputado
from public.accounts_and_cards a
where abs(a.balance - (a.opening_balance + coalesce((
           select sum(case when t.type = 'revenue' then t.amount else -t.amount end)
           from public.transactions t where t.account_id = a.id), 0))) > 0.005;

-- ------------------------------------------------------------
-- V3 — 0006: índice de apoio
-- ------------------------------------------------------------
-- Esperado: 1 linha (idx_tx_account_date)
select indexname from pg_indexes
where schemaname = 'public' and tablename = 'transactions'
  and indexname = 'idx_tx_account_date';

-- ------------------------------------------------------------
-- V4 — 0006/0008: view accounts_with_available (existe + security_invoker)
-- ------------------------------------------------------------
-- Esperado: 1 linha
select table_name from information_schema.views
where table_schema = 'public' and table_name = 'accounts_with_available';

-- Esperado: reloptions contém 'security_invoker=true'
select reloptions from pg_class where relname = 'accounts_with_available';

-- ------------------------------------------------------------
-- V5 — 0008: cartão usa balance (dívida viva); conta usa saldo liquidado
-- ------------------------------------------------------------
-- (a) Cartão: available DEVE ser igual ao balance. Esperado: 0 linhas.
select id, name, type, balance, available
from public.accounts_with_available
where type = 'credit_card' and abs(available - balance) > 0.005;

-- (b) Conta SEM parcela futura: available DEVE = balance. Esperado: 0 linhas.
select a.id, a.name, a.balance, awa.available
from public.accounts_and_cards a
join public.accounts_with_available awa on awa.id = a.id
where a.type <> 'credit_card'
  and not exists (select 1 from public.transactions t
                  where t.account_id = a.id and t.date > current_date)
  and abs(a.balance - awa.available) > 0.005;

-- (c) Conta COM parcela futura: available < balance (a parte futura não conta).
-- Esperado: para cada conta listada, futuro_nao_liquidado > 0.
select a.id, a.name, a.balance, awa.available,
       (a.balance - awa.available) as futuro_nao_liquidado
from public.accounts_and_cards a
join public.accounts_with_available awa on awa.id = a.id
where a.type <> 'credit_card'
  and exists (select 1 from public.transactions t
              where t.account_id = a.id and t.date > current_date);

-- ------------------------------------------------------------
-- V6 — 0007: dashboard_kpis usa `available`
-- ------------------------------------------------------------
-- OBS: dashboard_kpis() escopa por current_family_id() = auth.uid(). No SQL
-- editor (service role) auth.uid() é null → retorna zeros. Valide por FAMÍLIA,
-- trocando :fam pelo family_id, e compare com a conta manual abaixo.
select
  coalesce(sum(available) filter (where type <> 'credit_card'), 0) as total_balance_esperado,
  coalesce(sum(available), 0) as net_worth_esperado
from public.accounts_with_available
where family_id = :fam;
-- Chamado por um MEMBRO de :fam (app logado), dashboard_kpis()->>'total_balance'
-- e ->>'net_worth' devem bater com os valores acima.
