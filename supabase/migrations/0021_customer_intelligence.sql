-- Customer intelligence: LLM-extracted facts (each fact keeps its source
-- message id), AI summaries (regeneration skipped when source_hash unchanged),
-- and a security-invoker stats view (RLS on base tables scopes it).
-- Relationship score is computed in Dart, not stored.

alter table public.customers
  add column ai_facts jsonb not null default '[]'::jsonb,
  add column birthday date,
  add column last_contact_at timestamptz;

create table public.ai_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  bullets jsonb not null default '[]'::jsonb,
  close_confidence numeric(3,2),
  source_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, customer_id)
);

create trigger trg_ai_summaries_updated before update on public.ai_summaries
  for each row execute function public.set_updated_at();

alter table public.ai_summaries enable row level security;

create policy "own ai_summaries" on public.ai_summaries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create view public.customer_stats
with (security_invoker = true) as
select
  c.id as customer_id,
  c.user_id,
  count(o.id) filter (where o.status <> 'cancelled') as total_orders,
  coalesce(sum(o.grand_total) filter (where o.status <> 'cancelled'), 0)
    as lifetime_value,
  coalesce(sum(greatest(o.grand_total - coalesce(paid.amt, 0), 0))
    filter (where o.status <> 'cancelled'), 0) as outstanding,
  max(o.created_at) filter (where o.status <> 'cancelled') as last_order_at
from public.customers c
left join public.orders o
  on o.customer_id = c.id and o.user_id = c.user_id
left join lateral (
  select sum(p.amount) as amt from public.payments p where p.order_id = o.id
) paid on true
group by c.id, c.user_id;

revoke all on public.customer_stats from public, anon;
grant select on public.customer_stats to authenticated;
