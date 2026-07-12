-- ============================================================
-- 0009_family_security_hardening.sql
-- Protege papéis, vínculos familiares e atualizações de perfil.
-- Esta migration preserva os fluxos existentes via RPCs seguras.
-- ============================================================

-- Perfis são criados pelo trigger em auth.users. O cliente não escolhe role,
-- family_id ou active_2fa diretamente.
revoke insert, update on public.users from anon, authenticated;
grant update (name, avatar_url) on public.users to authenticated;

-- Famílias são criadas/movidas apenas por funções security definer.
revoke insert, update, delete on public.families from anon, authenticated;

drop policy if exists users_update on public.users;
create policy users_update_own_profile on public.users
    for update using (id = auth.uid())
    with check (id = auth.uid());

-- Quem ainda não pertence a uma família não precisa ser administrador.
update public.users set role = 'user' where family_id is null;

-- A versão anterior aceitava o papel enviado pelo cliente.
drop function if exists public.join_family(uuid, user_role);

create function public.join_family(target_family uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    if auth.uid() is null then
        raise exception 'Usuário não autenticado.';
    end if;
    if not exists (select 1 from public.families where id = target_family) then
        raise exception 'Convite não encontrado.';
    end if;

    update public.users
    set family_id = target_family, role = 'user'
    where id = auth.uid() and family_id is null;

    if not found then
        raise exception 'Este usuário já pertence a uma família.';
    end if;
end;
$$;

create or replace function public.create_family(family_name text)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    fam uuid;
    clean_name text := trim(coalesce(family_name, ''));
begin
    if auth.uid() is null then
        raise exception 'Usuário não autenticado.';
    end if;
    if char_length(clean_name) not between 1 and 120 then
        raise exception 'Nome da família inválido.';
    end if;
    if exists (select 1 from public.users where id = auth.uid() and family_id is not null) then
        raise exception 'Este usuário já pertence a uma família.';
    end if;

    insert into public.families (name) values (clean_name) returning id into fam;
    update public.users set family_id = fam, role = 'admin' where id = auth.uid();
    return fam;
end;
$$;

create or replace function public.update_family_member_role(
    target_user uuid,
    next_role user_role
)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
    actor_family uuid;
    target_family uuid;
    current_role user_role;
begin
    if auth.uid() is null or not public.is_admin() then
        raise exception 'Somente administradores podem alterar papéis.';
    end if;

    select family_id into actor_family from public.users where id = auth.uid();
    select family_id, role into target_family, current_role
    from public.users where id = target_user;
    if target_family is null or target_family is distinct from actor_family then
        raise exception 'Membro não pertence a esta família.';
    end if;
    if current_role = 'admin' and next_role <> 'admin' and
       (select count(*) from public.users where family_id = actor_family and role = 'admin') <= 1 then
        raise exception 'A família precisa manter pelo menos um administrador.';
    end if;

    update public.users set role = next_role where id = target_user;
end;
$$;

-- A marca visual de 2FA só pode ser ligada pelo próprio usuário depois da
-- verificação de MFA feita pelo Supabase no aplicativo.
create or replace function public.mark_2fa_active()
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
    if auth.uid() is null then
        raise exception 'Usuário não autenticado.';
    end if;
    update public.users set active_2fa = true where id = auth.uid();
end;
$$;

revoke all on function public.join_family(uuid) from public;
revoke all on function public.create_family(text) from public;
revoke all on function public.update_family_member_role(uuid, user_role) from public;
revoke all on function public.mark_2fa_active() from public;
grant execute on function public.join_family(uuid) to authenticated;
grant execute on function public.create_family(text) to authenticated;
grant execute on function public.update_family_member_role(uuid, user_role) to authenticated;
grant execute on function public.mark_2fa_active() to authenticated;
