-- Read-only RPCs for the Closr AI assistant.
-- All four are SECURITY INVOKER so RLS on base tables scopes results to the
-- calling user.  No free-form SQL is ever executed; only these whitelisted
-- functions are reachable from the assistant edge function.

-- 1. Outstanding payments summary — per-customer unpaid total.
create or replace function public.assistant_outstanding_summary(
  p_limit int default 10
)
returns table(
  customer_id uuid,
  customer_name text,
  outstanding numeric
)
language sql
security invoker
stable
as $$
  select
    c.id as customer_id,
    c.name as customer_name,
    coalesce(
      sum(o.grand_total) filter (where o.payment_status = 'unpaid'),
      0
    ) as outstanding
  from public.customers c
  join public.orders o on o.customer_id = c.id and o.user_id = (select auth.uid())
  where c.user_id = (select auth.uid())
  group by c.id, c.name
  having coalesce(sum(o.grand_total) filter (where o.payment_status = 'unpaid'), 0) > 0
  order by outstanding desc
  limit p_limit;
$$;

-- 2. Top customers by lifetime value.
create or replace function public.assistant_top_customers(
  p_limit int default 10
)
returns table(
  customer_id uuid,
  customer_name text,
  lifetime_value numeric,
  order_count bigint
)
language sql
security invoker
stable
as $$
  select
    c.id as customer_id,
    c.name as customer_name,
    coalesce(sum(o.grand_total), 0) as lifetime_value,
    count(o.id) as order_count
  from public.customers c
  left join public.orders o
    on o.customer_id = c.id
    and o.user_id = (select auth.uid())
    and o.status <> 'cancelled'
  where c.user_id = (select auth.uid())
  group by c.id, c.name
  order by lifetime_value desc
  limit p_limit;
$$;

-- 3. Pipeline stats — aggregate numbers for the seller.
create or replace function public.assistant_pipeline_stats()
returns json
language sql
security invoker
stable
as $$
  select json_build_object(
    'total_leads',         (select count(*) from public.leads where user_id = (select auth.uid())),
    'open_leads',          (select count(*) from public.leads where user_id = (select auth.uid()) and status not in ('won', 'lost')),
    'total_orders',        (select count(*) from public.orders where user_id = (select auth.uid())),
    'active_orders',       (select count(*) from public.orders where user_id = (select auth.uid()) and status not in ('delivered', 'cancelled')),
    'total_revenue',       (select coalesce(sum(grand_total), 0) from public.orders where user_id = (select auth.uid()) and status <> 'cancelled'),
    'outstanding',         (select coalesce(sum(grand_total), 0) from public.orders where user_id = (select auth.uid()) and payment_status = 'unpaid'),
    'paid_this_month',     (select coalesce(sum(amount), 0) from public.payments where user_id = (select auth.uid()) and created_at >= date_trunc('month', now())),
    'total_customers',     (select count(*) from public.customers where user_id = (select auth.uid()))
  );
$$;

-- 4. Overdue follow-ups — past-due date, not yet done.
create or replace function public.assistant_overdue_followups(
  p_limit int default 10
)
returns table(
  follow_up_id uuid,
  customer_id uuid,
  customer_name text,
  kind text,
  due_date date,
  days_overdue int
)
language sql
security invoker
stable
as $$
  select
    f.id as follow_up_id,
    c.id as customer_id,
    c.name as customer_name,
    f.kind,
    f.follow_up_date as due_date,
    (current_date - f.follow_up_date)::int as days_overdue
  from public.follow_ups f
  join public.customers c on c.id = f.customer_id and c.user_id = (select auth.uid())
  where f.user_id = (select auth.uid())
    and f.status = 'pending'
    and f.follow_up_date < current_date
  order by f.follow_up_date asc
  limit p_limit;
$$;

-- Grant execute to authenticated users (anon must never call these).
grant execute on function public.assistant_outstanding_summary(int) to authenticated;
grant execute on function public.assistant_top_customers(int) to authenticated;
grant execute on function public.assistant_pipeline_stats() to authenticated;
grant execute on function public.assistant_overdue_followups(int) to authenticated;

revoke execute on function public.assistant_outstanding_summary(int) from anon;
revoke execute on function public.assistant_top_customers(int) from anon;
revoke execute on function public.assistant_pipeline_stats() from anon;
revoke execute on function public.assistant_overdue_followups(int) from anon;
