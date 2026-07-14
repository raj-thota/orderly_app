-- Generalize the per-user AI rate limit to per-feature counters.
-- check_ai_parse_rate_limit stays as a wrapper (feature = 'parse') until the
-- deployed parse-enquiry function migrates to check_ai_rate_limit.

alter table public.ai_parse_usage
  add column feature text not null default 'parse';

create index ai_parse_usage_user_feature_time
  on public.ai_parse_usage (user_id, feature, created_at);

create function public.check_ai_rate_limit(
  p_feature text,
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
  if p_feature is null or p_feature !~ '^[a-z_]{1,32}$' then
    return false;
  end if;
  if p_max <= 0 or p_window_seconds <= 0 or p_window_seconds > 86400 then
    return false;
  end if;
  if auth.uid() is null then
    return false;
  end if;

  delete from ai_parse_usage
  where user_id = auth.uid()
    and feature = p_feature
    and created_at < now() - make_interval(secs => p_window_seconds);

  select count(*) into v_count
  from ai_parse_usage
  where user_id = auth.uid() and feature = p_feature;

  if v_count >= p_max then
    return false;
  end if;

  insert into ai_parse_usage (user_id, feature) values (auth.uid(), p_feature);
  return true;
end;
$$;

revoke all on function public.check_ai_rate_limit(text, integer, integer)
  from public, anon;
grant execute on function public.check_ai_rate_limit(text, integer, integer)
  to authenticated;

create or replace function public.check_ai_parse_rate_limit(
  p_max integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.check_ai_rate_limit('parse', p_max, p_window_seconds);
end;
$$;
