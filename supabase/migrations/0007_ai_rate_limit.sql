-- Per-user rate limiting for the parse-enquiry edge function.
-- The table is only ever touched by the SECURITY DEFINER function below;
-- authenticated/anon have no direct access (RLS on, grants revoked), which
-- also keeps it out of the GraphQL schema.
create table public.ai_parse_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index ai_parse_usage_user_time
  on public.ai_parse_usage (user_id, created_at);

alter table public.ai_parse_usage enable row level security;
revoke all on public.ai_parse_usage from anon, authenticated;

-- Returns true and records the request if the caller is under p_max requests
-- in the trailing p_window_seconds; false otherwise. Prunes expired rows so
-- the table stays small. Acts only on auth.uid(), so a caller can never read
-- or affect another user's counter.
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

revoke all on function public.check_ai_parse_rate_limit(integer, integer)
  from public, anon;
grant execute on function public.check_ai_parse_rate_limit(integer, integer)
  to authenticated;
