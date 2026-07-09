-- Append-only client telemetry for the validation funnel (activation events
-- plus the fake-door paywall). Rows are owner-scoped: a user can insert and
-- read only their own events. No update/delete policy exists, so events are
-- immutable once written (deny-by-default covers the rest). Never store PII in
-- props -- event names and non-identifying metadata (e.g. price) only.
create table public.app_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  props jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index app_events_user_time on public.app_events (user_id, created_at);
create index app_events_name_time on public.app_events (name, created_at);

alter table public.app_events enable row level security;

create policy "insert own app_events" on public.app_events
  for insert with check (auth.uid() = user_id);
create policy "read own app_events" on public.app_events
  for select using (auth.uid() = user_id);
