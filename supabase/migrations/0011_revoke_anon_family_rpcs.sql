-- ============================================================
-- 0011_revoke_anon_family_rpcs.sql
-- Remove grants legados do papel anon em RPCs de família.
-- ============================================================

revoke execute on function public.create_family(text) from anon;
revoke execute on function public.join_family(uuid) from anon;
revoke execute on function public.update_family_member_role(uuid, user_role) from anon;
revoke execute on function public.mark_2fa_active() from anon;

-- Mantém os gatilhos determinísticos e sem search_path herdável.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;
