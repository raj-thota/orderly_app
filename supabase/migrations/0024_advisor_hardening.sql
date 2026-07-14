-- Advisor follow-up after applying 0017–0023 (Supabase database lints):
-- 1. auth_rls_initplan: wrap auth.uid() in a scalar subquery so the planner
--    evaluates it once per statement instead of once per row. Identical
--    semantics, applied to every owner policy (old and new) for consistency.
-- 2. conversations.customer_id FK had no covering index — the table's unique
--    (user_id, customer_id) can't serve customer-side cascade deletes.
-- 3. app_events (0016) was created without the 0004-style anon revoke.

alter policy "own customers" on public.customers
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own products" on public.products
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own leads" on public.leads
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own orders" on public.orders
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own order_items" on public.order_items
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own payments" on public.payments
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own business_profile" on public.business_profile
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "read own app_events" on public.app_events
  using ((select auth.uid()) = user_id);
alter policy "insert own app_events" on public.app_events
  with check ((select auth.uid()) = user_id);
alter policy "own conversations" on public.conversations
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own messages select" on public.messages
  using ((select auth.uid()) = user_id);
alter policy "own messages insert" on public.messages
  with check ((select auth.uid()) = user_id);
alter policy "own ai_work_items" on public.ai_work_items
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own follow_ups" on public.follow_ups
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
alter policy "own ai_summaries" on public.ai_summaries
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- FK-support index: avoids sequential scan on messages' parent side when a
-- customer cascade-deletes their conversations.
create index idx_conversations_customer on public.conversations (customer_id);

-- Defense-in-depth: remove anon schema discoverability (mirrors 0004 pattern).
revoke all on public.app_events from anon;
