-- ============================================================
-- 0012_switch_family_for_existing_users.sql
-- Permite que uma pessoa que JÁ tem conta (e já usa sozinha) entre numa
-- família existente pelo código de convite — não apenas no cadastro.
-- Segurança: só troca quem está sozinho; quem está numa família com outras
-- pessoas precisa ser removido por um admin antes (evita orfanar a família).
-- ============================================================

create or replace function public.switch_to_family(target_family uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    cur uuid;
    member_count int;
begin
    if auth.uid() is null then
        raise exception 'Usuário não autenticado.';
    end if;
    if not exists (select 1 from public.families where id = target_family) then
        raise exception 'Convite não encontrado.';
    end if;

    select family_id into cur from public.users where id = auth.uid();
    if cur = target_family then
        return; -- já está nessa família
    end if;

    if cur is not null then
        select count(*) into member_count
          from public.users where family_id = cur;
        if member_count > 1 then
            raise exception 'Você faz parte de uma família com outras pessoas. Peça a um admin para removê-lo antes de entrar em outra.';
        end if;
    end if;

    update public.users
       set family_id = target_family, role = 'user'
     where id = auth.uid();
end;
$$;

revoke all on function public.switch_to_family(uuid) from public, anon;
grant execute on function public.switch_to_family(uuid) to authenticated;
