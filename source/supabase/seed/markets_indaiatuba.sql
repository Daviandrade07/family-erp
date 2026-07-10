-- Mercados parceiros restritos a INDAIATUBA-SP (regra do assistente de IA).
-- Execute no SQL Editor para substituir os mercados fictícios anteriores.

delete from public.markets;

insert into public.markets (name, cnpj, lat, lng) values
    ('GoodBom Indaiatuba',        '61.585.865/0001-01', -23.0870, -47.2110),
    ('Sumerbol Supermercados',    '52.276.719/0001-02', -23.0930, -47.2200),
    ('Pague Menos Indaiatuba',    '55.789.011/0001-03', -23.1005, -47.2260),
    ('Covabra Supermercados',     '46.395.463/0001-04', -23.0820, -47.2020),
    ('Cato Supermercados',        '44.851.657/0001-05', -23.1080, -47.2330)
on conflict (cnpj) do nothing;
