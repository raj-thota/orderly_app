-- Real billing tables for ₹999/mo Pro subscription.
-- Subscription state is written ONLY by billing-webhook (service role).
-- Clients may SELECT their own row; no INSERT/UPDATE/DELETE for authenticated.

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan text not null default 'pro_monthly',
  status text not null check (
    status in ('trialing', 'active', 'past_due', 'cancelled', 'expired')
  ),
  gateway text check (gateway in ('razorpay', 'stripe')),
  gateway_customer_id text,
  gateway_subscription_id text,
  current_period_end timestamptz,
  trial_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

create trigger trg_subscriptions_updated
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

alter table public.subscriptions enable row level security;

-- Clients can only read their own row.
create policy "own subscription select"
  on public.subscriptions
  for select
  using ((select auth.uid()) = user_id);

-- No insert/update/delete for authenticated — billing-webhook uses service role.
revoke insert, update, delete on public.subscriptions from authenticated;

-- Webhook idempotency ledger — no client policies; service role only.
create table public.billing_events (
  id text primary key,                    -- gateway event id (e.g. evt_xxx)
  user_id uuid,                           -- null for events before user link
  gateway text not null,
  type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.billing_events enable row level security;
-- No policies — not accessible by clients.
revoke all on public.billing_events from authenticated, anon;

-- Anon must never reach subscriptions.
revoke select on public.subscriptions from anon;

-- ---------------------------------------------------------------------------
-- ensure_trial(): idempotent — creates a trialing row (14-day trial) for the
-- calling user if none exists. Called by the Flutter app on first subscription
-- provider load; safe to call repeatedly.
-- ---------------------------------------------------------------------------
create or replace function public.ensure_trial()
returns void
language plpgsql
security invoker
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
