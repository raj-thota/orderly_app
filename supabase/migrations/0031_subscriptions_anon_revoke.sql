-- Hygiene: 0026 revoked SELECT from anon but left the default INSERT/UPDATE/
-- DELETE grants in place. RLS (no anon policies) already blocks them, but the
-- grants should not exist at all — defense in depth for billing state.
revoke all on public.subscriptions from anon;
revoke all on public.billing_events from anon;

-- plan had no CHECK (status did). Single purchasable plan today; extend the
-- allowed set when new tiers ship.
alter table public.subscriptions
  add constraint subscriptions_plan_check
  check (plan in ('pro_monthly'));
