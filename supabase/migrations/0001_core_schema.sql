-- Closr core schema (Phase 1 foundation)
-- Clean rebuild: legacy tables (leads, order_items, users) were empty (0 rows)
-- and are dropped before recreating the new model. Approved reset (dev).

drop table if exists public.payments cascade;
drop table if exists public.order_items cascade;
drop table if exists public.orders cascade;
drop table if exists public.leads cascade;
drop table if exists public.products cascade;
drop table if exists public.customers cascade;
drop table if exists public.business_profile cascade;
drop table if exists public.users cascade;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- business_profile (one per user)
create table public.business_profile (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  logo_url text,
  address text,
  phone text,
  email text,
  upi_id text,
  upi_name text,
  gstin text,
  default_gst_rate numeric(5,2) not null default 0,
  invoice_prefix text not null default 'INV-',
  next_invoice_number integer not null default 1,
  currency text not null default 'INR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone text not null,
  email text,
  address text,
  notes text,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, phone)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  sku text,
  images text[] not null default '{}',
  price numeric(12,2) not null default 0,
  unit text not null default 'pc',
  gst_rate numeric(5,2),
  is_unique boolean not null default false,
  piece_status text not null default 'available'
    check (piece_status in ('available','booked','sold')),
  qty_on_hand integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  source text not null default 'manual'
    check (source in ('dm','paste','product','manual')),
  message text,
  intent text,
  status text not null default 'new'
    check (status in ('new','follow','won','lost')),
  follow_up_date timestamptz,
  follow_up_note text,
  activities jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,
  order_number integer,
  status text not null default 'pending'
    check (status in ('pending','packed','shipped','delivered')),
  courier text,
  tracking_no text,
  shipped_at timestamptz,
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','partial','paid')),
  subtotal numeric(12,2) not null default 0,
  tax_total numeric(12,2) not null default 0,
  grand_total numeric(12,2) not null default 0,
  invoice_number text,
  notes text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  name text not null,
  image_url text,
  unit_price numeric(12,2) not null default 0,
  gst_rate numeric(5,2) not null default 0,
  qty integer not null default 1,
  line_total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  amount numeric(12,2) not null default 0,
  method text not null default 'upi' check (method in ('upi','cash','other')),
  proof_image_url text,
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- updated_at triggers
create trigger trg_business_profile_updated before update on public.business_profile
  for each row execute function public.set_updated_at();
create trigger trg_customers_updated before update on public.customers
  for each row execute function public.set_updated_at();
create trigger trg_products_updated before update on public.products
  for each row execute function public.set_updated_at();
create trigger trg_leads_updated before update on public.leads
  for each row execute function public.set_updated_at();
create trigger trg_orders_updated before update on public.orders
  for each row execute function public.set_updated_at();

-- indexes
create index idx_customers_user on public.customers(user_id);
create index idx_products_user on public.products(user_id);
create index idx_leads_user_status on public.leads(user_id, status);
create index idx_orders_user_status on public.orders(user_id, status);
create index idx_order_items_order on public.order_items(order_id);
create index idx_payments_order on public.payments(order_id);
