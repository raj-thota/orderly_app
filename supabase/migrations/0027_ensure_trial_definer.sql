-- Harden ensure_trial() to SECURITY DEFINER so its INSERT privilege is
-- explicit and immune to future accidental re-grants of INSERT to authenticated.
-- auth.uid() still resolves from the JWT of the calling session.
create or replace function public.ensure_trial()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated';
  end if;

  insert into public.subscriptions (user_id, plan, status, trial_end)
  values (
    (select auth.uid()),
    'pro_monthly',
    'trialing',
    now() + interval '14 days'
  )
  on conflict (user_id) do nothing;
end;
$$;

grant execute on function public.ensure_trial() to authenticated;
revoke execute on function public.ensure_trial() from anon;
