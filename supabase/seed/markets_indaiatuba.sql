-- ============================================================
-- FONTE CANÔNICA DE MERCADOS (Indaiatuba-SP e região)
-- ============================================================
-- Este é o ÚNICO seed oficial da tabela `markets`. Rode-o no setup
-- (SQL Editor) DEPOIS das migrations 0001–0004.
--
-- Contém os 10 mercados da região — os mesmos referenciados pelo assistente
-- de IA e pelo OCR (GoodBom/Sumerbol/Pague Menos/Covabra fazem parte daqui).
-- Cinco deles também são inseridos pela migration `0004_ai_extensions.sql`;
-- por isso este seed é IDEMPOTENTE (`on conflict (cnpj) do nothing`) e pode
-- ser rodado em qualquer ordem, sem duplicar nem apagar nada.
--
-- NÃO usar `seed/seed.sql` (mercados fictícios da capital de SP — desativado).

insert into public.markets (name, cnpj, lat, lng) values
    -- Supermercados de Indaiatuba (base do OCR/mock)
    ('GoodBom Indaiatuba',        '61.585.865/0001-01', -23.0870, -47.2110),
    ('Sumerbol Supermercados',    '52.276.719/0001-02', -23.0930, -47.2200),
    ('Pague Menos Indaiatuba',    '55.789.011/0001-03', -23.1005, -47.2260),
    ('Covabra Supermercados',     '46.395.463/0001-04', -23.0820, -47.2020),
    ('Cato Supermercados',        '44.851.657/0001-05', -23.1080, -47.2330),
    -- Atacados/rede da região (também semeados pela migration 0004)
    ('Atacadão Indaiatuba',       '75.315.333/0001-06', -23.1120, -47.2270),
    ('Tenda Atacado Salto',       '01.157.555/0001-07', -23.1960, -47.2870),
    ('Assaí Atacadista Itu',      '06.057.223/0001-08', -23.2540, -47.2930),
    ('Paulistão Salto',           '50.948.381/0001-09', -23.2000, -47.2930),
    ('Carrefour Indaiatuba',      '45.543.915/0001-10', -23.0980, -47.2120)
on conflict (cnpj) do nothing;
