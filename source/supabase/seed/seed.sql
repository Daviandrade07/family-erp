-- Seed reference data: fictional partner markets for the
-- shopping recommendation engine (coordinates around São Paulo).
insert into public.markets (name, cnpj, lat, lng) values
    ('Mercado Econômico',   '12.345.678/0001-01', -23.5505, -46.6333),
    ('Super Vizinho',       '23.456.789/0001-02', -23.5570, -46.6420),
    ('Atacadão da Família', '34.567.890/0001-03', -23.5401, -46.6250),
    ('Empório Premium',     '45.678.901/0001-04', -23.5620, -46.6544),
    ('Hortifruti Central',  '56.789.012/0001-05', -23.5468, -46.6390)
on conflict (cnpj) do nothing;
