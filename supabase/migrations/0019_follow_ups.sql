-- Standalone follow-ups (calendar-backed). Replaces leads.follow_up_date as
-- the notification engine's source. The lead columns stay (read-only) until a
-- post-V1 cleanup migration. At most one pending follow-up per lead, so the
-- client's set-for-lead upsert has a stable target.

create table public.follow_ups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  due_at timestamptz not null,
  note text,
  kind text not null default 'general' check (kind in ('reply','payment','general')),
  status text not null default 'pending' check (status in ('pending','done','skipped')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_follow_ups_updated before update on public.follow_ups
  for each row execute function public.set_updated_at();

create index idx_follow_ups_user_status_due
  on public.follow_ups (user_id, status, due_at);
create unique index uq_follow_ups_pending_lead
  on public.follow_ups (lead_id) where lead_id is not null and status = 'pending';

alter table public.follow_ups enable row level security;

create policy "own follow_ups" on public.follow_ups
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Defense-in-depth: remove anon schema discoverability (mirrors 0004 pattern).
revoke all on public.follow_ups from anon;

-- FK-support index: avoids sequential scan on customers during cascade delete.
create index idx_follow_ups_customer on public.follow_ups (customer_id);

-- Backfill: one pending follow-up per lead currently in 'follow' with a date.
-- Leads without a customer are skipped (customer_id is required here; such
-- rows can't exist via the current capture flow anyway).
insert into public.follow_ups (user_id, customer_id, lead_id, due_at, note)
select l.user_id, l.customer_id, l.id, l.follow_up_date, l.follow_up_note
from public.leads l
where l.status = 'follow'
  and l.follow_up_date is not null
  and l.customer_id is not null
  and not exists (
    select 1 from public.follow_ups f
    where f.lead_id = l.id and f.status = 'pending'
  );
