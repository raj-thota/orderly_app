-- Harden check_ai_parse_rate_limit: the function is granted to authenticated
-- and thus directly callable via PostgREST. A non-positive p_window_seconds
-- turned `now() - make_interval(secs => p_window_seconds)` into a FUTURE bound,
-- so the prune `delete ... where created_at < <future>` wiped the caller's own
-- counter and defeated the limit. Reject out-of-range params before any delete.
create or replace function public.check_ai_parse_rate_limit(
  p_max integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if p_max <= 0 or p_window_seconds <= 0 or p_window_seconds > 86400 then
    return false;
  end if;

  if auth.uid() is null then
    return false;
  end if;

  delete from ai_parse_usage
  where user_id = auth.uid()
    and created_at < now() - make_interval(secs => p_window_seconds);

  select count(*) into v_count
  from ai_parse_usage
  where user_id = auth.uid();

  if v_count >= p_max then
    return false;
  end if;

  insert into ai_parse_usage (user_id) values (auth.uid());
  return true;
end;
$$;
