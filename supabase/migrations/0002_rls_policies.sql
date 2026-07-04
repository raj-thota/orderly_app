-- Enable RLS everywhere (deny-by-default) and add owner-scoped policies.

alter table public.business_profile enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.leads enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create policy "own business_profile" on public.business_profile
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own customers" on public.customers
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own products" on public.products
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own leads" on public.leads
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own orders" on public.orders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own order_items" on public.order_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own payments" on public.payments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
