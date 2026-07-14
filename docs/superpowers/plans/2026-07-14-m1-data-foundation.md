# M1 Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the V1 database foundation (migrations 0017–0023, RPC v3, cancel_order, follow_ups backfill, customer_stats view) plus the Dart models/services that read it, and cut the notification engine over to `follow_ups`.

**Architecture:** Seven additive SQL migrations follow the house style (RLS + policies in the same file as the table, `security invoker` RPCs, forward-only). Dart side adds four new data folders (`conversations`, `work`, `followups`, `customers`) with plain `fromMap` models and thin Supabase services, mirroring `features/orders/data`. The notification engine switches its *scheduling* source from legacy lead maps to `follow_ups` rows; legacy display helpers stay until M4.

**Tech Stack:** Supabase Postgres (project `dgviploqkwyuttcdnddq` — NEVER venora), Flutter/Riverpod 2, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-11-closr-v1.0.0-tdd.md` §6, §8, §12, M1 row of §14.

---

## File structure

**Create (SQL):**
- `supabase/migrations/0017_conversations_messages.sql`
- `supabase/migrations/0018_ai_work_items.sql`
- `supabase/migrations/0019_follow_ups.sql`
- `supabase/migrations/0020_orders_pricing_lifecycle.sql`
- `supabase/migrations/0021_customer_intelligence.sql`
- `supabase/migrations/0022_leads_budget_confidence.sql`
- `supabase/migrations/0023_ai_rate_limit_general.sql`

**Create (Dart):**
- `lib/features/conversations/data/conversation.dart`, `message.dart`, `conversations_service.dart`
- `lib/features/work/data/work_item.dart`, `work_items_service.dart`
- `lib/features/followups/data/follow_up.dart`, `follow_ups_service.dart`
- `lib/features/customers/data/customer_stats.dart`, `relationship_score.dart`

**Modify (Dart):**
- `lib/features/orders/data/order.dart` — status default `confirmed`, new fields discount/shippingFee/expectedDate
- `lib/features/orders/data/orders_service.dart` — `cancelOrder`
- `lib/features/orders/controller/orders_provider.dart` — lifecycle flow rename
- `lib/features/orders/presentation/order_detail_screen.dart` — `_flow` rename
- `lib/shared/widgets/status_pill.dart` — `confirmed` + `cancelled` cases
- `lib/features/enquiries/data/enquiries_service.dart` — createOrder v3 params, follow_ups dual-write
- `lib/features/enquiries/controller/enquiries_provider.dart` — follow_ups dual-write on follow-up mutations
- `lib/core/services/notification_service.dart` — schedule from follow_ups

**Tests:** one file per new model/pure function under `test/features/<feature>/`, plus updates to `test/features/orders/*`, `test/shared/widgets/status_pill_test.dart`, `test/core/services/notification_service_test.dart` (new).

Migrations are written first (Tasks 1–7), applied together (Task 8), then Dart (Tasks 9–16). The v3 RPC drops the old signature, so the client change (Task 10) must not ship before Task 8 is applied.

---

### Task 1: Migration 0017 — conversations & messages (+ backfill)

**Files:**
- Create: `supabase/migrations/0017_conversations_messages.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Conversations (one thread per customer in V1) and messages.
-- Messages are immutable: select+insert policies only, no update/delete.
-- Backfill seeds one conversation per customer that has lead text, with the
-- lead message as the first inbound message (idempotent).

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, customer_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound')),
  source text not null check (source in ('paste','screenshot','voice','manual','ai_send')),
  body text not null,
  sent_at timestamptz,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create trigger trg_conversations_updated before update on public.conversations
  for each row execute function public.set_updated_at();

create index idx_messages_user_conv_time
  on public.messages (user_id, conversation_id, created_at);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy "own conversations" on public.conversations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own messages select" on public.messages
  for select using (auth.uid() = user_id);
create policy "own messages insert" on public.messages
  for insert with check (auth.uid() = user_id);

-- Backfill: conversation per (user, customer) that has at least one lead message.
insert into public.conversations (user_id, customer_id, last_message_at, created_at)
select l.user_id, l.customer_id, max(l.created_at), min(l.created_at)
from public.leads l
where l.customer_id is not null and coalesce(l.message, '') <> ''
group by l.user_id, l.customer_id
on conflict (user_id, customer_id) do nothing;

-- Backfill: each lead message becomes one inbound message.
insert into public.messages
  (user_id, conversation_id, direction, source, body, sent_at, created_at)
select l.user_id, c.id, 'inbound',
       case when l.source in ('paste','manual') then l.source else 'paste' end,
       l.message, l.created_at, l.created_at
from public.leads l
join public.conversations c
  on c.user_id = l.user_id and c.customer_id = l.customer_id
where l.customer_id is not null
  and coalesce(l.message, '') <> ''
  and not exists (
    select 1 from public.messages m
    where m.conversation_id = c.id
      and m.body = l.message
      and m.created_at = l.created_at
  );
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0017_conversations_messages.sql
git commit -m "feat(db): conversations and messages tables with lead backfill"
```

---

### Task 2: Migration 0018 — ai_work_items

**Files:**
- Create: `supabase/migrations/0018_ai_work_items.sql`

- [ ] **Step 1: Write the migration**

```sql
-- AI work queue. Rows are generated by the generate-work-items edge function
-- (called with the user's JWT, so owner RLS applies) and mutated by the client
-- (approve/dismiss/done). draft holds prose only — amounts live in `amount`,
-- copied from DB aggregates at generation time, never from model output.

create table public.ai_work_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  kind text not null check (kind in
    ('reply','payment_reminder','create_order','invoice','follow_up','share_catalog')),
  priority text not null check (priority in ('high','medium','low')),
  score integer not null default 0,
  title text not null,
  context text,
  amount numeric(12,2),
  draft jsonb not null default '{}'::jsonb,
  confidence numeric(3,2),
  status text not null default 'pending'
    check (status in ('pending','approved','dismissed','expired','done')),
  batch_id uuid not null,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_ai_work_items_updated before update on public.ai_work_items
  for each row execute function public.set_updated_at();

create index idx_ai_work_items_queue
  on public.ai_work_items (user_id, status, priority, score desc);

alter table public.ai_work_items enable row level security;

create policy "own ai_work_items" on public.ai_work_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0018_ai_work_items.sql
git commit -m "feat(db): ai_work_items queue table"
```

---

### Task 3: Migration 0019 — follow_ups (+ backfill)

**Files:**
- Create: `supabase/migrations/0019_follow_ups.sql`

- [ ] **Step 1: Write the migration**

```sql
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0019_follow_ups.sql
git commit -m "feat(db): follow_ups table with lead backfill"
```

---

### Task 4: Migration 0020 — orders pricing & lifecycle, RPC v3, cancel_order

**Files:**
- Create: `supabase/migrations/0020_orders_pricing_lifecycle.sql`

- [ ] **Step 1: Write the migration**

Constraint order matters: the old check forbids `confirmed`, so drop it **before** the data update.

```sql
-- Orders gain pricing columns and the mock's lifecycle:
-- confirmed / packed / shipped / delivered / cancelled ('pending' renamed).
-- create_order_with_items v3 adds discount/shipping/expected date; the old
-- signature is dropped in the same migration (single client, pre-launch).
-- cancel_order releases a booked unique piece and refuses when payments exist.

alter table public.orders
  add column discount numeric(12,2) not null default 0,
  add column shipping_fee numeric(12,2) not null default 0,
  add column expected_date date;

alter table public.orders drop constraint orders_status_check;
update public.orders set status = 'confirmed' where status = 'pending';
alter table public.orders add constraint orders_status_check
  check (status in ('confirmed','packed','shipped','delivered','cancelled'));
alter table public.orders alter column status set default 'confirmed';

drop function public.create_order_with_items(uuid, uuid, jsonb, uuid, text);

create function public.create_order_with_items(
  p_customer_id uuid,
  p_lead_id uuid,
  p_items jsonb,
  p_book_product_id uuid default null,
  p_notes text default null,
  p_discount numeric default 0,
  p_shipping_fee numeric default 0,
  p_expected_date date default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_subtotal numeric(12,2) := 0;
  v_grand numeric(12,2);
  v_item jsonb;
  v_price numeric(12,2);
  v_qty integer;
begin
  if p_discount is null or p_discount < 0
     or p_shipping_fee is null or p_shipping_fee < 0 then
    raise exception 'invalid_totals';
  end if;

  if not exists (
    select 1 from customers where id = p_customer_id and user_id = auth.uid()
  ) then
    raise exception 'customer_not_found';
  end if;

  if p_lead_id is not null and not exists (
    select 1 from leads where id = p_lead_id and user_id = auth.uid()
  ) then
    raise exception 'lead_not_found';
  end if;

  if p_book_product_id is not null then
    update products set piece_status = 'booked'
    where id = p_book_product_id
      and user_id = auth.uid()
      and is_unique
      and piece_status = 'available';
    if not found then
      raise exception 'piece_unavailable';
    end if;
  end if;

  insert into orders
    (user_id, customer_id, lead_id, notes, discount, shipping_fee,
     expected_date, order_number)
  values (
    auth.uid(), p_customer_id, p_lead_id, p_notes, p_discount, p_shipping_fee,
    p_expected_date,
    (select coalesce(max(order_number), 0) + 1
       from orders where user_id = auth.uid())
  )
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_qty := greatest(coalesce((v_item->>'qty')::integer, 1), 1);

    insert into order_items
      (user_id, order_id, product_id, name, image_url, unit_price, gst_rate, qty, line_total)
    values (
      auth.uid(),
      v_order_id,
      nullif(v_item->>'product_id', '')::uuid,
      coalesce(nullif(v_item->>'name', ''), 'Item'),
      v_item->>'image_url',
      v_price,
      coalesce((v_item->>'gst_rate')::numeric, 0),
      v_qty,
      v_price * v_qty
    );

    v_subtotal := v_subtotal + v_price * v_qty;
  end loop;

  v_grand := v_subtotal - p_discount + p_shipping_fee;
  if v_grand < 0 then
    raise exception 'invalid_totals';
  end if;

  update orders set subtotal = v_subtotal, grand_total = v_grand
  where id = v_order_id;

  if p_lead_id is not null then
    update leads set status = 'won'
    where id = p_lead_id and user_id = auth.uid();
  end if;

  return v_order_id;
end;
$$;

revoke all on function public.create_order_with_items(
  uuid, uuid, jsonb, uuid, text, numeric, numeric, date) from public, anon;
grant execute on function public.create_order_with_items(
  uuid, uuid, jsonb, uuid, text, numeric, numeric, date) to authenticated;

create function public.cancel_order(p_order_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status text;
begin
  select status into v_status
  from orders where id = p_order_id and user_id = auth.uid();

  if v_status is null then
    raise exception 'order_not_found';
  end if;
  if v_status = 'cancelled' then
    return; -- idempotent
  end if;
  if v_status = 'delivered' then
    raise exception 'order_delivered';
  end if;
  if exists (select 1 from payments where order_id = p_order_id) then
    raise exception 'order_has_payments';
  end if;

  update orders set status = 'cancelled'
  where id = p_order_id and user_id = auth.uid();

  update products set piece_status = 'available'
  where user_id = auth.uid()
    and is_unique
    and piece_status = 'booked'
    and id in (
      select product_id from order_items
      where order_id = p_order_id and product_id is not null
    );
end;
$$;

revoke all on function public.cancel_order(uuid) from public, anon;
grant execute on function public.cancel_order(uuid) to authenticated;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0020_orders_pricing_lifecycle.sql
git commit -m "feat(db): order pricing columns, confirmed/cancelled lifecycle, RPC v3, cancel_order"
```

---

### Task 5: Migration 0021 — customer intelligence & ai_summaries

**Files:**
- Create: `supabase/migrations/0021_customer_intelligence.sql`

- [ ] **Step 1: Write the migration**

```sql
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0021_customer_intelligence.sql
git commit -m "feat(db): customer ai_facts, ai_summaries, customer_stats view"
```

---

### Task 6: Migration 0022 — leads budget + capture confidence

**Files:**
- Create: `supabase/migrations/0022_leads_budget_confidence.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Capture v2 persists extracted budget and parse confidence on the lead.
alter table public.leads
  add column budget numeric(12,2) check (budget is null or budget >= 0),
  add column ai_confidence numeric(3,2)
    check (ai_confidence is null or (ai_confidence >= 0 and ai_confidence <= 1));
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0022_leads_budget_confidence.sql
git commit -m "feat(db): leads budget and ai_confidence columns"
```

---

### Task 7: Migration 0023 — generalized AI rate limit

**Files:**
- Create: `supabase/migrations/0023_ai_rate_limit_general.sql`

- [ ] **Step 1: Write the migration**

Keeps every hardening rule from 0008 (param bounds, null-uid rejection). The old function becomes a thin wrapper so the deployed `parse-enquiry` keeps working until it redeploys.

```sql
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0023_ai_rate_limit_general.sql
git commit -m "feat(db): per-feature AI rate limit with parse wrapper"
```

---

### Task 8: Apply migrations 0017–0023 and run advisors

**HARD RULE:** target project is `dgviploqkwyuttcdnddq`. The Supabase MCP connector has previously pointed at the wrong project (`venora`). Never apply there.

- [ ] **Step 1: Verify project visibility**

Use the Supabase MCP `list_projects` tool. Confirm `dgviploqkwyuttcdnddq` appears. If it does **not**, STOP: print the seven SQL files and ask the user to run them in the Supabase SQL editor in order; then continue at Step 3.

- [ ] **Step 2: Apply each migration**

Use MCP `apply_migration` against project `dgviploqkwyuttcdnddq`, one call per file, in filename order 0017 → 0023, migration name = filename without extension.

- [ ] **Step 3: Verify schema**

Use MCP `list_tables` on `dgviploqkwyuttcdnddq`. Expect new tables: `conversations`, `messages`, `ai_work_items`, `follow_ups`, `ai_summaries`. Run one SQL check via `execute_sql`:

```sql
select
  (select count(*) from public.follow_ups) as follow_ups_rows,
  (select count(*) from public.conversations) as conversations_rows,
  (select count(*) from public.orders where status = 'pending') as leftover_pending;
```

Expected: `leftover_pending = 0`.

- [ ] **Step 4: Run advisors**

MCP `get_advisors` (security + performance) on `dgviploqkwyuttcdnddq`. Expected: no new RLS findings on the five new tables. Fix any finding with a follow-up migration before proceeding.

---

### Task 9: Dart — order lifecycle rename (confirmed / cancelled)

**Files:**
- Modify: `lib/features/orders/data/order.dart:43,95`
- Modify: `lib/features/orders/controller/orders_provider.dart`
- Modify: `lib/features/orders/presentation/order_detail_screen.dart:33`
- Modify: `lib/shared/widgets/status_pill.dart:24`
- Test: `test/features/orders/order_test.dart`, `test/features/orders/orders_controller_test.dart`, `test/shared/widgets/status_pill_test.dart`

- [ ] **Step 1: Update model tests to expect the new default**

In `test/features/orders/order_test.dart`, change the tolerant-parse expectation:

```dart
expect(order.status, 'confirmed'); // default (was 'pending')
```

Add a cancelled-status parse test:

```dart
test('fromMap parses cancelled status', () {
  final order = Order.fromMap({'id': 'o3', 'status': 'cancelled'});
  expect(order.status, 'cancelled');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/orders/order_test.dart`
Expected: FAIL — default is still `'pending'`.

- [ ] **Step 3: Rename in code**

`lib/features/orders/data/order.dart`: both `'pending'` defaults → `'confirmed'`.

`lib/features/orders/controller/orders_provider.dart`:

```dart
enum OrderFilter { active, confirmed, packed, shipped, delivered, cancelled }

String? nextOrderStatus(String current) {
  const flow = ['confirmed', 'packed', 'shipped', 'delivered'];
  final i = flow.indexOf(current);
  if (i < 0 || i >= flow.length - 1) return null;
  return flow[i + 1];
}

List<Order> filterOrders(List<Order> orders, OrderFilter filter) {
  switch (filter) {
    case OrderFilter.active:
      return orders
          .where((o) => o.status != 'delivered' && o.status != 'cancelled')
          .toList();
    case OrderFilter.confirmed:
      return orders.where((o) => o.status == 'confirmed').toList();
    case OrderFilter.packed:
      return orders.where((o) => o.status == 'packed').toList();
    case OrderFilter.shipped:
      return orders.where((o) => o.status == 'shipped').toList();
    case OrderFilter.delivered:
      return orders.where((o) => o.status == 'delivered').toList();
    case OrderFilter.cancelled:
      return orders.where((o) => o.status == 'cancelled').toList();
  }
}
```

`lib/features/orders/presentation/order_detail_screen.dart`: `_flow` → `['confirmed', 'packed', 'shipped', 'delivered']`.

`lib/shared/widgets/status_pill.dart` — replace the `'pending'` case in `StatusPillStyle.forStatus`:

```dart
      case 'confirmed':
        return const StatusPillStyle('Confirmed', AppColors.warning);
      case 'cancelled':
        return const StatusPillStyle('Cancelled', AppColors.danger);
```

Then sweep every remaining reference:

Run: `grep -rn "'pending'" lib test --include='*.dart'`

Update every hit that refers to an **order lifecycle status** (leave `payment_status`-style strings and unrelated `'pending'` states — e.g. work-item status in later tasks — untouched). Expect hits in `orders_screen.dart` chip labels and the tests named above; update labels "Pending" → "Confirmed" where they render lifecycle status.

- [ ] **Step 4: Run the orders + shared tests**

Run: `flutter test test/features/orders test/shared`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "refactor(orders): rename pending lifecycle to confirmed, add cancelled"
```

---

### Task 10: Dart — Order pricing fields, createOrder v3, cancelOrder

**Files:**
- Modify: `lib/features/orders/data/order.dart`
- Modify: `lib/features/orders/data/orders_service.dart`
- Modify: `lib/features/enquiries/data/enquiries_service.dart:120-146`
- Test: `test/features/orders/order_test.dart`

- [ ] **Step 1: Write failing model test**

Append to `test/features/orders/order_test.dart`:

```dart
test('fromMap parses discount, shipping fee and expected date', () {
  final order = Order.fromMap({
    'id': 'o4',
    'subtotal': '10000',
    'discount': '500',
    'shipping_fee': '0',
    'expected_date': '2026-06-12',
    'grand_total': '9500',
  });
  expect(order.discount, 500);
  expect(order.shippingFee, 0);
  expect(order.expectedDate, DateTime.parse('2026-06-12'));
  expect(order.grandTotal, 9500);
});

test('discount and shipping default to zero when absent', () {
  final order = Order.fromMap({'id': 'o5'});
  expect(order.discount, 0);
  expect(order.shippingFee, 0);
  expect(order.expectedDate, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/orders/order_test.dart`
Expected: FAIL — `discount` getter undefined.

- [ ] **Step 3: Extend the Order model**

In `lib/features/orders/data/order.dart` add constructor params/fields (after `grandTotal`):

```dart
this.discount = 0,
this.shippingFee = 0,
this.expectedDate,
```

```dart
final double discount;
final double shippingFee;
final DateTime? expectedDate;
```

And in `fromMap` (after `grandTotal:` line):

```dart
discount: double.tryParse(map['discount']?.toString() ?? '') ?? 0,
shippingFee: double.tryParse(map['shipping_fee']?.toString() ?? '') ?? 0,
expectedDate: DateTime.tryParse(map['expected_date']?.toString() ?? ''),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/orders/order_test.dart`
Expected: PASS.

- [ ] **Step 5: Extend service calls**

`lib/features/orders/data/orders_service.dart` — add:

```dart
Future<void> cancelOrder(String id) async {
  await _client.rpc('cancel_order', params: {'p_order_id': id});
}
```

`lib/features/enquiries/data/enquiries_service.dart` `createOrder` — add optional named params and pass through:

```dart
double discount = 0,
double shippingFee = 0,
DateTime? expectedDate,
```

```dart
final orderId = await _client.rpc('create_order_with_items', params: {
  'p_customer_id': customerId,
  'p_lead_id': leadId,
  'p_items': payload,
  'p_book_product_id': bookProductId,
  'p_notes': notes,
  'p_discount': discount,
  'p_shipping_fee': shippingFee,
  'p_expected_date': expectedDate?.toIso8601String().substring(0, 10),
});
```

- [ ] **Step 6: Analyze + full orders tests**

Run: `flutter analyze lib/features/orders lib/features/enquiries && flutter test test/features/orders`
Expected: no issues, PASS.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "feat(orders): pricing fields on model, v3 RPC params, cancelOrder"
```

---

### Task 11: Dart — FollowUp model + service

**Files:**
- Create: `lib/features/followups/data/follow_up.dart`
- Create: `lib/features/followups/data/follow_ups_service.dart`
- Test: `test/features/followups/follow_up_test.dart`

- [ ] **Step 1: Write failing model test**

Create `test/features/followups/follow_up_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/followups/data/follow_up.dart';

void main() {
  final noon = DateTime(2026, 7, 14, 12);

  test('fromMap flattens customer join and parses fields', () {
    final f = FollowUp.fromMap({
      'id': 'f1',
      'customer_id': 'c1',
      'lead_id': 'l1',
      'due_at': '2026-07-14T10:30:00Z',
      'note': 'share new collection',
      'kind': 'reply',
      'status': 'pending',
      'customers': {'name': 'Meena', 'phone': '9876543210'},
    });
    expect(f.id, 'f1');
    expect(f.leadId, 'l1');
    expect(f.customerName, 'Meena');
    expect(f.kind, 'reply');
    expect(f.dueAt, DateTime.parse('2026-07-14T10:30:00Z'));
  });

  test('fromMap tolerates missing join and defaults', () {
    final f = FollowUp.fromMap({'id': 'f2', 'due_at': '2026-07-14T10:30:00Z'});
    expect(f.customerName, isNull);
    expect(f.kind, 'general');
    expect(f.status, 'pending');
  });

  test('isDueToday and isOverdue bucket by local calendar day', () {
    final today = FollowUp.fromMap(
        {'id': 'a', 'due_at': DateTime(2026, 7, 14, 9).toIso8601String()});
    final yesterday = FollowUp.fromMap(
        {'id': 'b', 'due_at': DateTime(2026, 7, 13, 18).toIso8601String()});
    final tomorrow = FollowUp.fromMap(
        {'id': 'c', 'due_at': DateTime(2026, 7, 15).toIso8601String()});

    expect(today.isDueToday(now: noon), isTrue);
    expect(today.isOverdue(now: noon), isFalse);
    expect(yesterday.isOverdue(now: noon), isTrue);
    expect(yesterday.isDueToday(now: noon), isFalse);
    expect(tomorrow.isDueToday(now: noon), isFalse);
    expect(tomorrow.isOverdue(now: noon), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/followups/follow_up_test.dart`
Expected: FAIL — file `follow_up.dart` missing.

- [ ] **Step 3: Write the model**

Create `lib/features/followups/data/follow_up.dart`:

```dart
class FollowUp {
  const FollowUp({
    this.id,
    this.customerId,
    this.leadId,
    required this.dueAt,
    this.note,
    this.kind = 'general',
    this.status = 'pending',
    this.customerName,
    this.customerPhone,
  });

  final String? id;
  final String? customerId;
  final String? leadId;
  final DateTime dueAt;
  final String? note;
  final String kind;
  final String status;
  final String? customerName;
  final String? customerPhone;

  bool isDueToday({DateTime? now}) {
    final t = now ?? DateTime.now();
    final local = dueAt.toLocal();
    return local.year == t.year && local.month == t.month && local.day == t.day;
  }

  bool isOverdue({DateTime? now}) {
    final t = now ?? DateTime.now();
    final startOfToday = DateTime(t.year, t.month, t.day);
    return dueAt.toLocal().isBefore(startOfToday);
  }

  factory FollowUp.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    return FollowUp(
      id: map['id']?.toString(),
      customerId: map['customer_id']?.toString(),
      leadId: map['lead_id']?.toString(),
      dueAt: DateTime.tryParse(map['due_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      note: map['note']?.toString(),
      kind: (map['kind'] ?? 'general').toString(),
      status: (map['status'] ?? 'pending').toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/followups/follow_up_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the service**

Create `lib/features/followups/data/follow_ups_service.dart` (Supabase calls only — no unit test, same as `OrdersService`):

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'follow_up.dart';

const _selectWithJoins = '*, customers(name, phone)';

class FollowUpsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<FollowUp>> fetchPending() async {
    final rows = await _client
        .from('follow_ups')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('status', 'pending')
        .order('due_at', ascending: true);
    return rows.map<FollowUp>((r) => FollowUp.fromMap(r)).toList();
  }

  /// Upserts the single pending follow-up for a lead (unique partial index
  /// uq_follow_ups_pending_lead guarantees at most one).
  Future<void> setForLead({
    required String leadId,
    required String customerId,
    required DateTime dueAt,
    String? note,
    String kind = 'general',
  }) async {
    final existing = await _client
        .from('follow_ups')
        .select('id')
        .eq('user_id', _userId)
        .eq('lead_id', leadId)
        .eq('status', 'pending')
        .maybeSingle();
    if (existing != null) {
      await _client.from('follow_ups').update({
        'due_at': dueAt.toIso8601String(),
        if (note != null) 'note': note,
        'kind': kind,
      }).eq('id', existing['id']);
      return;
    }
    await _client.from('follow_ups').insert({
      'user_id': _userId,
      'customer_id': customerId,
      'lead_id': leadId,
      'due_at': dueAt.toIso8601String(),
      if (note != null) 'note': note,
      'kind': kind,
    });
  }

  Future<void> completeForLead(String leadId) async {
    await _client
        .from('follow_ups')
        .update({'status': 'done'})
        .eq('user_id', _userId)
        .eq('lead_id', leadId)
        .eq('status', 'pending');
  }

  Future<void> markDone(String id) async {
    await _client
        .from('follow_ups')
        .update({'status': 'done'})
        .eq('user_id', _userId)
        .eq('id', id);
  }
}
```

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/features/followups && flutter test test/features/followups`
Expected: clean, PASS.

```bash
git add lib/features/followups test/features/followups
git commit -m "feat(followups): FollowUp model and service"
```

---

### Task 12: Dual-write follow_ups from the capture/enquiry paths

Until M2 rebuilds capture, leads keep writing `follow_up_date` **and** now mirror into `follow_ups`, so the engine cutover (Task 13) misses nothing.

**Files:**
- Modify: `lib/features/enquiries/data/enquiries_service.dart` (`addEnquiry`, `updateEnquiry` callers)
- Modify: `lib/features/enquiries/controller/enquiries_provider.dart:36` (follow-up mutation)

- [ ] **Step 1: Read both files fully**

Read `lib/features/enquiries/controller/enquiries_provider.dart` end to end. Identify every place that writes `follow_up_date` or flips lead `status` away from `'follow'` (won/lost). Those are the dual-write points.

- [ ] **Step 2: Mirror writes**

In `enquiries_service.dart` `addEnquiry`, after the lead insert `single()` returns the row, when `followUpDate != null`:

```dart
if (followUpDate != null) {
  try {
    await FollowUpsService().setForLead(
      leadId: row['id'].toString(),
      customerId: customerId,
      dueAt: followUpDate,
    );
  } catch (_) {
    // Mirror write is best-effort during the M1–M2 dual-write window;
    // the legacy column above stays authoritative for this lead.
  }
}
```

(import `package:orderly_app/features/followups/data/follow_ups_service.dart`).

In `enquiries_provider.dart`, where the follow-up date is set on an existing lead (the `'follow_up_date': date.toIso8601String()` mutation), call `FollowUpsService().setForLead(...)` with the lead's id + customer id after the lead update succeeds; where status flips to `'won'`/`'lost'`, call `FollowUpsService().completeForLead(leadId)`. Wrap both in the same best-effort try/catch pattern.

Order creation also wins leads server-side (RPC updates `leads.status`). Add `completeForLead(leadId)` in `enquiries_service.createOrder` after the RPC returns, when `leadId != null`, same try/catch.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/enquiries && flutter test test/features/enquiries`
Expected: clean, PASS (existing tests unaffected — dual-write is fire-and-forget).

- [ ] **Step 4: Commit**

```bash
git add lib/features/enquiries
git commit -m "feat(followups): dual-write follow_ups from enquiry mutations"
```

---

### Task 13: Notification engine cutover to follow_ups

**Files:**
- Modify: `lib/core/services/notification_service.dart`
- Test: `test/core/services/notification_service_test.dart` (new)

The engine's *scheduling* switches to `FollowUp` rows. The map-based helpers (`buildBuckets`, `buildSuggestions`, `isFollowUpToday`, `isOverdueFollowUp`) stay untouched — `NotificationsScreen` still renders from legacy maps until M4 retires it.

- [ ] **Step 1: Find scheduling call sites**

Run: `grep -rn "syncLeadNotifications\|checkAndTriggerSmartReminders" lib test --include='*.dart'`

Note every caller — each must compile after the signature change.

- [ ] **Step 2: Write failing tests for the new pure planner**

The sync loop is untestable (plugin calls), so extract the decision into a pure function. Create `test/core/services/notification_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/notification_service.dart';
import 'package:orderly_app/features/followups/data/follow_up.dart';

void main() {
  final noon = DateTime(2026, 7, 14, 12);

  FollowUp f(String id, DateTime due, {String? leadId}) => FollowUp.fromMap({
        'id': id,
        'lead_id': leadId,
        'due_at': due.toIso8601String(),
        'customers': {'name': 'Meena'},
      });

  test('future follow-up plans a scheduled reminder', () {
    final plans = NotificationService.planFollowUpNotifications(
      [f('a', DateTime(2026, 7, 15, 10), leadId: 'l1')],
      now: noon,
    );
    expect(plans.single.kind, FollowUpPlanKind.scheduled);
    expect(plans.single.fireAt, DateTime(2026, 7, 15, 10));
    expect(plans.single.payload, 'l1');
  });

  test('date-only follow-up defaults to 9 AM', () {
    final plans = NotificationService.planFollowUpNotifications(
      [f('a', DateTime(2026, 7, 15))],
      now: noon,
    );
    expect(plans.single.fireAt, DateTime(2026, 7, 15, 9));
  });

  test('overdue follow-up plans an immediate daily reminder', () {
    final plans = NotificationService.planFollowUpNotifications(
      [f('a', DateTime(2026, 7, 12, 17))],
      now: noon,
    );
    expect(plans.single.kind, FollowUpPlanKind.overdue);
  });

  test('due earlier today plans a show-now reminder', () {
    final plans = NotificationService.planFollowUpNotifications(
      [f('a', DateTime(2026, 7, 14, 9))],
      now: noon,
    );
    expect(plans.single.kind, FollowUpPlanKind.dueToday);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/core/services/notification_service_test.dart`
Expected: FAIL — `planFollowUpNotifications` undefined.

- [ ] **Step 4: Implement planner + sync**

In `notification_service.dart` add (near the top-level classes):

```dart
enum FollowUpPlanKind { scheduled, dueToday, overdue }

class FollowUpNotificationPlan {
  const FollowUpNotificationPlan({
    required this.followUpId,
    required this.kind,
    required this.fireAt,
    required this.title,
    required this.body,
    this.payload,
  });

  final String followUpId;
  final FollowUpPlanKind kind;
  final DateTime fireAt;
  final String title;
  final String body;
  final String? payload;
}
```

And in `NotificationService`:

```dart
/// Pure planning over pending follow-ups; the sync loop just executes plans.
static List<FollowUpNotificationPlan> planFollowUpNotifications(
  List<FollowUp> followUps, {
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final plans = <FollowUpNotificationPlan>[];

  for (final f in followUps) {
    final id = f.id;
    if (id == null) continue;
    final name = f.customerName ?? 'Customer';

    if (f.isOverdue(now: t)) {
      plans.add(FollowUpNotificationPlan(
        followUpId: id,
        kind: FollowUpPlanKind.overdue,
        fireAt: _nextOverdueReminderTime(t),
        title: 'Overdue follow-up',
        body: '$name still needs your attention.',
        payload: f.leadId,
      ));
      continue;
    }

    final fireAt = _notificationTimeForFollowUp(f.dueAt.toLocal());
    if (fireAt.isAfter(t)) {
      plans.add(FollowUpNotificationPlan(
        followUpId: id,
        kind: FollowUpPlanKind.scheduled,
        fireAt: fireAt,
        title: 'Follow-up reminder',
        body: 'Reach out to $name on time.',
        payload: f.leadId,
      ));
    } else if (f.isDueToday(now: t)) {
      plans.add(FollowUpNotificationPlan(
        followUpId: id,
        kind: FollowUpPlanKind.dueToday,
        fireAt: t,
        title: 'Follow-up today',
        body: 'Reach out to $name today.',
        payload: f.leadId,
      ));
    }
  }

  return plans;
}
```

Rewrite the sync entry points to use it (replacing the lead-map loop):

```dart
static Future<void> checkAndTriggerSmartReminders() async {
  final followUps = await FollowUpsService().fetchPending();
  await syncFollowUpNotifications(followUps: followUps);
}

static Future<void> syncFollowUpNotifications({
  required List<FollowUp> followUps,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final plans = planFollowUpNotifications(followUps, now: now);

  final previousIds = prefs.getStringList(_scheduledLeadIdsKey) ?? <String>[];
  final currentIds = plans.map((p) => p.followUpId).toSet();

  for (final removed in previousIds.where((id) => !currentIds.contains(id))) {
    await cancel(_notificationId(removed, 'follow_up'));
    await cancel(_notificationId(removed, 'overdue'));
  }

  for (final plan in plans) {
    final followUpId = _notificationId(plan.followUpId, 'follow_up');
    final overdueId = _notificationId(plan.followUpId, 'overdue');
    switch (plan.kind) {
      case FollowUpPlanKind.overdue:
        await cancel(followUpId);
        await scheduleNotification(
          id: overdueId,
          title: plan.title,
          body: plan.body,
          date: plan.fireAt,
          payload: plan.payload,
          repeatDaily: true,
        );
        await _showOncePerDay(
          prefs: prefs,
          type: 'overdue',
          leadId: plan.followUpId,
          day: now,
          id: overdueId,
          title: plan.title,
          body: plan.body,
        );
      case FollowUpPlanKind.scheduled:
        await cancel(overdueId);
        await scheduleNotification(
          id: followUpId,
          title: plan.title,
          body: plan.body,
          date: plan.fireAt,
          payload: plan.payload,
        );
      case FollowUpPlanKind.dueToday:
        await cancel(overdueId);
        await cancel(followUpId);
        await _showOncePerDay(
          prefs: prefs,
          type: 'today',
          leadId: plan.followUpId,
          day: now,
          id: followUpId,
          title: plan.title,
          body: plan.body,
        );
    }
  }

  await prefs.setStringList(_scheduledLeadIdsKey, currentIds.toList());
}
```

Notes:
- `_showOncePerDay`'s `payload` inside is the lead id today; change its `showNotification` call to pass `plan.payload` through — add a `String? payload` parameter to `_showOncePerDay` and pass `plan.payload` at both call sites.
- Delete the old `syncLeadNotifications` and update every caller found in Step 1 (most call `checkAndTriggerSmartReminders`, which keeps its name). Remove the now-unused `EnquiriesService` import if nothing else uses it.
- Imports to add: `package:orderly_app/features/followups/data/follow_up.dart`, `.../follow_ups_service.dart`.
- Keep `_notificationId`, `_notificationTimeForFollowUp`, `_nextOverdueReminderTime`, `_dailyReceiptKey` as-is (ids now keyed by follow-up id — old scheduled notifications keyed by lead id are orphaned once; acceptable one-time blip, note it in the commit body).

- [ ] **Step 5: Run tests + analyze**

Run: `flutter analyze lib/core/services && flutter test test/core/services test/features`
Expected: clean, PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services lib/features test
git commit -m "feat(notifications): schedule reminders from follow_ups

Scheduling source cuts over from leads.follow_up_date to the follow_ups
table via a pure planner (unit-tested). Display helpers for the legacy
NotificationsScreen remain until M4. Previously scheduled lead-keyed
notifications are orphaned once at upgrade; next sync rebuilds them."
```

---

### Task 14: Dart — Conversation/Message models + service

**Files:**
- Create: `lib/features/conversations/data/conversation.dart`
- Create: `lib/features/conversations/data/message.dart`
- Create: `lib/features/conversations/data/conversations_service.dart`
- Test: `test/features/conversations/conversation_test.dart`, `test/features/conversations/message_test.dart`

- [ ] **Step 1: Write failing model tests**

`test/features/conversations/message_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/data/message.dart';

void main() {
  test('fromMap parses direction, source, body and sent_at', () {
    final m = Message.fromMap({
      'id': 'm1',
      'conversation_id': 'cv1',
      'direction': 'inbound',
      'source': 'paste',
      'body': 'Hi, is the kundan set still available?',
      'sent_at': '2026-07-14T10:30:00Z',
      'meta': {'imported': true},
    });
    expect(m.direction, 'inbound');
    expect(m.source, 'paste');
    expect(m.body, contains('kundan'));
    expect(m.sentAt, DateTime.parse('2026-07-14T10:30:00Z'));
    expect(m.meta['imported'], true);
  });

  test('isFromSeller true only for outbound', () {
    final inbound = Message.fromMap(
        {'id': 'a', 'direction': 'inbound', 'source': 'paste', 'body': 'x'});
    final outbound = Message.fromMap(
        {'id': 'b', 'direction': 'outbound', 'source': 'ai_send', 'body': 'y'});
    expect(inbound.isFromSeller, isFalse);
    expect(outbound.isFromSeller, isTrue);
  });
}
```

`test/features/conversations/conversation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/data/conversation.dart';

void main() {
  test('fromMap flattens customer join', () {
    final c = Conversation.fromMap({
      'id': 'cv1',
      'customer_id': 'c1',
      'last_message_at': '2026-07-14T10:30:00Z',
      'customers': {'name': 'Meena', 'phone': '9876543210'},
    });
    expect(c.id, 'cv1');
    expect(c.customerName, 'Meena');
    expect(c.lastMessageAt, DateTime.parse('2026-07-14T10:30:00Z'));
  });

  test('fromMap tolerates missing fields', () {
    final c = Conversation.fromMap({'id': 'cv2'});
    expect(c.customerName, isNull);
    expect(c.lastMessageAt, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/conversations`
Expected: FAIL — files missing.

- [ ] **Step 3: Write the models**

`lib/features/conversations/data/message.dart`:

```dart
class Message {
  const Message({
    this.id,
    this.conversationId,
    required this.direction,
    required this.source,
    required this.body,
    this.sentAt,
    this.meta = const {},
    this.createdAt,
  });

  final String? id;
  final String? conversationId;
  final String direction;
  final String source;
  final String body;
  final DateTime? sentAt;
  final Map<String, dynamic> meta;
  final DateTime? createdAt;

  bool get isFromSeller => direction == 'outbound';

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id']?.toString(),
      conversationId: map['conversation_id']?.toString(),
      direction: (map['direction'] ?? 'inbound').toString(),
      source: (map['source'] ?? 'manual').toString(),
      body: (map['body'] ?? '').toString(),
      sentAt: DateTime.tryParse(map['sent_at']?.toString() ?? ''),
      meta: map['meta'] is Map
          ? Map<String, dynamic>.from(map['meta'] as Map)
          : const {},
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}
```

`lib/features/conversations/data/conversation.dart`:

```dart
class Conversation {
  const Conversation({
    this.id,
    this.customerId,
    this.lastMessageAt,
    this.customerName,
    this.customerPhone,
  });

  final String? id;
  final String? customerId;
  final DateTime? lastMessageAt;
  final String? customerName;
  final String? customerPhone;

  factory Conversation.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    return Conversation(
      id: map['id']?.toString(),
      customerId: map['customer_id']?.toString(),
      lastMessageAt:
          DateTime.tryParse(map['last_message_at']?.toString() ?? ''),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/conversations`
Expected: PASS.

- [ ] **Step 5: Write the service**

`lib/features/conversations/data/conversations_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'conversation.dart';
import 'message.dart';

class ConversationsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  /// Returns the customer's conversation id, creating the thread if needed
  /// (one thread per customer in V1 — unique (user_id, customer_id)).
  Future<String> ensureForCustomer(String customerId) async {
    final row = await _client
        .from('conversations')
        .upsert(
          {'user_id': _userId, 'customer_id': customerId},
          onConflict: 'user_id,customer_id',
          ignoreDuplicates: false,
        )
        .select('id')
        .single();
    return row['id'].toString();
  }

  Future<Conversation?> fetchByCustomer(String customerId) async {
    final row = await _client
        .from('conversations')
        .select('*, customers(name, phone)')
        .eq('user_id', _userId)
        .eq('customer_id', customerId)
        .maybeSingle();
    return row == null ? null : Conversation.fromMap(row);
  }

  Future<List<Message>> fetchMessages(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('user_id', _userId)
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return rows.map<Message>((r) => Message.fromMap(r)).toList();
  }

  Future<Message> appendMessage({
    required String conversationId,
    required String direction,
    required String source,
    required String body,
    DateTime? sentAt,
    Map<String, dynamic> meta = const {},
  }) async {
    final row = await _client
        .from('messages')
        .insert({
          'user_id': _userId,
          'conversation_id': conversationId,
          'direction': direction,
          'source': source,
          'body': body,
          if (sentAt != null) 'sent_at': sentAt.toIso8601String(),
          if (meta.isNotEmpty) 'meta': meta,
        })
        .select()
        .single();
    await _client
        .from('conversations')
        .update({'last_message_at': (sentAt ?? DateTime.now()).toIso8601String()})
        .eq('id', conversationId)
        .eq('user_id', _userId);
    return Message.fromMap(row);
  }
}
```

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/features/conversations && flutter test test/features/conversations`
Expected: clean, PASS.

```bash
git add lib/features/conversations test/features/conversations
git commit -m "feat(conversations): models and service for threads and messages"
```

---

### Task 15: Dart — WorkItem model + service

**Files:**
- Create: `lib/features/work/data/work_item.dart`
- Create: `lib/features/work/data/work_items_service.dart`
- Test: `test/features/work/work_item_test.dart`

- [ ] **Step 1: Write failing tests**

`test/features/work/work_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/work/data/work_item.dart';

void main() {
  WorkItem w(String id, String priority, int score) => WorkItem.fromMap({
        'id': id,
        'kind': 'payment_reminder',
        'priority': priority,
        'score': score,
        'title': 'Payment pending',
        'status': 'pending',
      });

  test('fromMap parses fields and draft message', () {
    final item = WorkItem.fromMap({
      'id': 'w1',
      'customer_id': 'c1',
      'kind': 'reply',
      'priority': 'high',
      'score': 80,
      'title': 'Interested in Kundan Set',
      'context': 'AI reply ready to send',
      'amount': '8000',
      'draft': {'message': 'Hi Meena!'},
      'confidence': '0.92',
      'status': 'pending',
      'customers': {'name': 'Meena', 'phone': '9876543210'},
    });
    expect(item.kind, 'reply');
    expect(item.priority, 'high');
    expect(item.amount, 8000);
    expect(item.draftMessage, 'Hi Meena!');
    expect(item.confidence, 0.92);
    expect(item.customerName, 'Meena');
  });

  test('sortWorkItems orders high>medium>low then score desc', () {
    final sorted = sortWorkItems([
      w('lo', 'low', 99),
      w('hi2', 'high', 10),
      w('med', 'medium', 50),
      w('hi1', 'high', 70),
    ]);
    expect(sorted.map((i) => i.id).toList(), ['hi1', 'hi2', 'med', 'lo']);
  });

  test('fromMap tolerates missing optional fields', () {
    final item = WorkItem.fromMap({'id': 'w2', 'kind': 'reply', 'title': 't'});
    expect(item.priority, 'low');
    expect(item.score, 0);
    expect(item.draftMessage, isNull);
    expect(item.amount, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/work`
Expected: FAIL — file missing.

- [ ] **Step 3: Write the model**

`lib/features/work/data/work_item.dart`:

```dart
class WorkItem {
  const WorkItem({
    this.id,
    this.customerId,
    this.leadId,
    this.orderId,
    required this.kind,
    this.priority = 'low',
    this.score = 0,
    required this.title,
    this.context,
    this.amount,
    this.draft = const {},
    this.confidence,
    this.status = 'pending',
    this.customerName,
    this.customerPhone,
  });

  final String? id;
  final String? customerId;
  final String? leadId;
  final String? orderId;
  final String kind;
  final String priority;
  final int score;
  final String title;
  final String? context;
  final double? amount;
  final Map<String, dynamic> draft;
  final double? confidence;
  final String status;
  final String? customerName;
  final String? customerPhone;

  String? get draftMessage {
    final m = draft['message'];
    return m == null || m.toString().isEmpty ? null : m.toString();
  }

  factory WorkItem.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    return WorkItem(
      id: map['id']?.toString(),
      customerId: map['customer_id']?.toString(),
      leadId: map['lead_id']?.toString(),
      orderId: map['order_id']?.toString(),
      kind: (map['kind'] ?? 'reply').toString(),
      priority: (map['priority'] ?? 'low').toString(),
      score: int.tryParse(map['score']?.toString() ?? '') ?? 0,
      title: (map['title'] ?? '').toString(),
      context: map['context']?.toString(),
      amount: double.tryParse(map['amount']?.toString() ?? ''),
      draft: map['draft'] is Map
          ? Map<String, dynamic>.from(map['draft'] as Map)
          : const {},
      confidence: double.tryParse(map['confidence']?.toString() ?? ''),
      status: (map['status'] ?? 'pending').toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
    );
  }
}

const _priorityRank = {'high': 0, 'medium': 1, 'low': 2};

/// High > medium > low, then score descending. Pure so it's testable and the
/// queue renders identically everywhere.
List<WorkItem> sortWorkItems(List<WorkItem> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    final p = (_priorityRank[a.priority] ?? 3)
        .compareTo(_priorityRank[b.priority] ?? 3);
    if (p != 0) return p;
    return b.score.compareTo(a.score);
  });
  return sorted;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/work`
Expected: PASS.

- [ ] **Step 5: Write the service**

`lib/features/work/data/work_items_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_item.dart';

class WorkItemsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  /// Pending items that haven't expired, queue-ordered.
  Future<List<WorkItem>> fetchPending() async {
    final rows = await _client
        .from('ai_work_items')
        .select('*, customers(name, phone)')
        .eq('user_id', _userId)
        .eq('status', 'pending')
        .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}');
    return sortWorkItems(
        rows.map<WorkItem>((r) => WorkItem.fromMap(r)).toList());
  }

  Future<void> updateStatus(String id, String status) async {
    await _client
        .from('ai_work_items')
        .update({'status': status})
        .eq('user_id', _userId)
        .eq('id', id);
  }
}
```

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/features/work && flutter test test/features/work`
Expected: clean, PASS.

```bash
git add lib/features/work test/features/work
git commit -m "feat(work): WorkItem model, queue sort, service"
```

---

### Task 16: Dart — CustomerStats + relationship score

**Files:**
- Create: `lib/features/customers/data/customer_stats.dart`
- Create: `lib/features/customers/data/relationship_score.dart`
- Test: `test/features/customers/customer_stats_test.dart`, `test/features/customers/relationship_score_test.dart`

- [ ] **Step 1: Write failing tests**

`test/features/customers/customer_stats_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/customers/data/customer_stats.dart';

void main() {
  test('fromMap parses aggregates', () {
    final s = CustomerStats.fromMap({
      'customer_id': 'c1',
      'total_orders': 8,
      'lifetime_value': '48500',
      'outstanding': '8000',
      'last_order_at': '2026-07-01T00:00:00Z',
    });
    expect(s.totalOrders, 8);
    expect(s.lifetimeValue, 48500);
    expect(s.outstanding, 8000);
    expect(s.lastOrderAt, DateTime.parse('2026-07-01T00:00:00Z'));
  });

  test('fromMap tolerates missing fields', () {
    final s = CustomerStats.fromMap({'customer_id': 'c2'});
    expect(s.totalOrders, 0);
    expect(s.lifetimeValue, 0);
    expect(s.outstanding, 0);
    expect(s.lastOrderAt, isNull);
  });
}
```

`test/features/customers/relationship_score_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/customers/data/customer_stats.dart';
import 'package:orderly_app/features/customers/data/relationship_score.dart';

void main() {
  final now = DateTime(2026, 7, 14);

  CustomerStats stats({
    int orders = 0,
    double ltv = 0,
    double outstanding = 0,
    DateTime? lastOrderAt,
  }) =>
      CustomerStats(
        customerId: 'c',
        totalOrders: orders,
        lifetimeValue: ltv,
        outstanding: outstanding,
        lastOrderAt: lastOrderAt,
      );

  test('new customer with no orders gets the neutral 2.5', () {
    expect(relationshipScore(stats(), now: now), 2.5);
  });

  test('frequent recent fully-paid high-value customer scores 5.0', () {
    final s = stats(
      orders: 10,
      ltv: 60000,
      outstanding: 0,
      lastOrderAt: DateTime(2026, 7, 1),
    );
    expect(relationshipScore(s, now: now), 5.0);
  });

  test('stale customer with large outstanding scores low', () {
    final s = stats(
      orders: 1,
      ltv: 5000,
      outstanding: 4000,
      lastOrderAt: DateTime(2025, 6, 1),
    );
    expect(relationshipScore(s, now: now), lessThan(2.0));
  });

  test('score is clamped to one decimal within 0..5', () {
    final s = stats(
      orders: 3,
      ltv: 12000,
      outstanding: 1000,
      lastOrderAt: DateTime(2026, 6, 20),
    );
    final score = relationshipScore(s, now: now);
    expect(score, inInclusiveRange(0, 5));
    expect((score * 10).roundToDouble() / 10, score);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/customers`
Expected: FAIL — files missing.

- [ ] **Step 3: Write model and score**

`lib/features/customers/data/customer_stats.dart`:

```dart
class CustomerStats {
  const CustomerStats({
    required this.customerId,
    this.totalOrders = 0,
    this.lifetimeValue = 0,
    this.outstanding = 0,
    this.lastOrderAt,
  });

  final String customerId;
  final int totalOrders;
  final double lifetimeValue;
  final double outstanding;
  final DateTime? lastOrderAt;

  factory CustomerStats.fromMap(Map<String, dynamic> map) {
    return CustomerStats(
      customerId: (map['customer_id'] ?? '').toString(),
      totalOrders: int.tryParse(map['total_orders']?.toString() ?? '') ?? 0,
      lifetimeValue:
          double.tryParse(map['lifetime_value']?.toString() ?? '') ?? 0,
      outstanding: double.tryParse(map['outstanding']?.toString() ?? '') ?? 0,
      lastOrderAt: DateTime.tryParse(map['last_order_at']?.toString() ?? ''),
    );
  }
}
```

`lib/features/customers/data/relationship_score.dart`:

```dart
import 'customer_stats.dart';

/// Deterministic relationship score, 0–5, one decimal. No LLM involved
/// (TDD §6/0021). Weighted components, each normalized to 0–1:
///
///   volume   (w 1.5): orders/10, capped at 1
///   recency  (w 1.5): last order ≤30d → 1.0, ≤90d → 0.6, ≤180d → 0.3, else 0
///   payment  (w 1.0): outstanding 0 → 1.0, <25% of LTV → 0.6, else 0.2
///   value    (w 1.0): LTV ≥50k → 1.0, ≥10k → 0.6, >0 → 0.3, else 0
///
/// A customer with no orders has no signal: fixed neutral 2.5.
double relationshipScore(CustomerStats stats, {DateTime? now}) {
  if (stats.totalOrders <= 0) return 2.5;

  final t = now ?? DateTime.now();

  final volume = (stats.totalOrders / 10).clamp(0.0, 1.0);

  double recency = 0;
  final last = stats.lastOrderAt;
  if (last != null) {
    final days = t.difference(last).inDays;
    recency = days <= 30
        ? 1.0
        : days <= 90
            ? 0.6
            : days <= 180
                ? 0.3
                : 0.0;
  }

  final payment = stats.outstanding <= 0
      ? 1.0
      : (stats.lifetimeValue > 0 &&
              stats.outstanding < stats.lifetimeValue * 0.25)
          ? 0.6
          : 0.2;

  final value = stats.lifetimeValue >= 50000
      ? 1.0
      : stats.lifetimeValue >= 10000
          ? 0.6
          : stats.lifetimeValue > 0
              ? 0.3
              : 0.0;

  final raw = 1.5 * volume + 1.5 * recency + 1.0 * payment + 1.0 * value;
  return ((raw.clamp(0.0, 5.0)) * 10).round() / 10;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/customers`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/customers test/features/customers
git commit -m "feat(customers): stats model and deterministic relationship score"
```

---

### Task 17: Milestone exit verification

- [ ] **Step 1: Full static + test pass**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests PASS. Fix root causes of any failure before proceeding.

- [ ] **Step 2: Advisors re-check**

MCP `get_advisors` (security) on `dgviploqkwyuttcdnddq` — expected clean (same as Task 8 Step 4; re-run in case later fixes added migrations).

- [ ] **Step 3: Manual smoke (J-subset)**

With the app running against the real project: capture an enquiry with a follow-up date → confirm a `follow_ups` row exists (MCP `execute_sql`: `select * from follow_ups order by created_at desc limit 3;`) → create an order with a discount from the enquiry → confirm `orders.discount` set and lead follow-up marked `done`.

- [ ] **Step 4: Code review**

Dispatch the code-reviewer agent on `git diff` since the M1 start commit. Security-reviewer agent on migrations 0017–0023 (RLS focus, per TDD §16 verification row for M1). Address findings.

- [ ] **Step 5: Final commit (if fixes were made)**

```bash
git add -A -- lib test supabase docs
git commit -m "chore(m1): review fixes for data foundation milestone"
```
