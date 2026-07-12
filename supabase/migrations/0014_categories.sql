-- Frente 3 — Categorias customizáveis.
-- Padrões: family_id NULL + is_default true (globais, lidos por todos, ninguém
-- edita/apaga). Customizadas: family_id da família. Transações continuam
-- guardando o NOME da categoria (texto) — então arquivar/editar NÃO some do
-- histórico: os totais passados do mordomo continuam íntegros.

create table public.categories (
    id          uuid primary key default gen_random_uuid(),
    family_id   uuid references public.families (id) on delete cascade, -- null = padrão global
    name        text not null,
    type        transaction_type not null,
    color_token text not null default 'catGray', -- token da paleta (Fase 0)
    icon        text,
    archived    boolean not null default false,
    is_default  boolean not null default false,
    created_at  timestamptz not null default now()
);

-- Nome único por (família, tipo), case-insensitive. Globais (family_id null)
-- têm índice parcial próprio para não duplicar padrão.
create unique index uq_categories_family_type_name
    on public.categories (family_id, type, lower(name));
create unique index uq_categories_global_type_name
    on public.categories (type, lower(name)) where family_id is null;
create index idx_categories_type_archived
    on public.categories (type, archived);

alter table public.categories enable row level security;

create policy categories_select on public.categories
    for select using (
        family_id is null or family_id = public.current_family_id()
    );
create policy categories_insert on public.categories
    for insert with check (
        family_id = public.current_family_id() and public.can_write()
    );
create policy categories_update on public.categories
    for update using (
        family_id = public.current_family_id() and public.can_write()
    );
create policy categories_delete on public.categories
    for delete using (
        family_id = public.current_family_id() and public.is_admin()
    );

-- Seeds dos padrões (a partir de Categories.expense / Categories.revenue).
insert into public.categories (family_id, name, type, color_token, is_default) values
    (null, 'Alimentação', 'expense', 'catOlive', true),
    (null, 'Mercado',     'expense', 'catAmber', true),
    (null, 'Moradia',     'expense', 'catSlate', true),
    (null, 'Transporte',  'expense', 'catTeal',  true),
    (null, 'Saúde',       'expense', 'catGreen', true),
    (null, 'Educação',    'expense', 'catBlue',  true),
    (null, 'Lazer',       'expense', 'catCyan',  true),
    (null, 'Vestuário',   'expense', 'catCoral', true),
    (null, 'Assinaturas', 'expense', 'catBrown', true),
    (null, 'Pets',        'expense', 'catSand',  true),
    (null, 'Outros',      'expense', 'catGray',  true),
    (null, 'Salário',       'revenue', 'catGreen', true),
    (null, 'Freelance',     'revenue', 'catTeal',  true),
    (null, 'Investimentos', 'revenue', 'catBlue',  true),
    (null, 'Aluguel',       'revenue', 'catSlate', true),
    (null, 'Outros',        'revenue', 'catGray',  true);
