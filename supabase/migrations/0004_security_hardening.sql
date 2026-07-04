-- Security hardening from Supabase advisors.

-- 1. Pin the trigger function's search_path (advisor: function_search_path_mutable).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 2. Revoke anon access on app tables (advisor: pg_graphql_anon_table_exposed).
-- The app is always authenticated before touching these tables; RLS already
-- blocks anon rows. Revoking is defense-in-depth + removes schema discoverability.
revoke all on public.business_profile from anon;
revoke all on public.customers from anon;
revoke all on public.products from anon;
revoke all on public.leads from anon;
revoke all on public.orders from anon;
revoke all on public.order_items from anon;
revoke all on public.payments from anon;
