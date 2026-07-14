-- Orders gain pricing columns and the mock's lifecycle:
-- confirmed / packed / shipped / delivered / cancelled ('pending' renamed).
-- create_order_with_items v3 adds discount/shipping/expected date; the old
-- signature is dropped in the same migration (single client, pre-launch).
-- cancel_order releases the booked unique piece scoped to this order's
-- booked_product_id (new column), refuses when payments exist, and locks
-- the row for update to prevent TOCTOU races.
-- mark_order_delivered is replaced here to scope the sold-piece update to
-- booked_product_id rather than scanning all order_items.
-- record_payment is replaced here to lock the order row and block payments
-- on cancelled orders.

alter table public.orders
  add column discount numeric(12,2) not null default 0,
  add column shipping_fee numeric(12,2) not null default 0,
  add column expected_date date,
  add column booked_product_id uuid references public.products(id) on delete set null;

alter table public.orders drop constraint orders_status_check;
update public.orders set status = 'confirmed' where status = 'pending';
alter table public.orders add constraint orders_status_check
  check (status in ('confirmed','packed','shipped','delivered','cancelled'));
alter table public.orders alter column status set default 'confirmed';

-- Backfill: attribute currently-booked unique pieces to the newest live order
-- that carries them, so cancel/deliver release the right piece.
update public.orders o
set booked_product_id = b.product_id
from (
  select distinct on (oi.product_id) oi.product_id, oi.order_id
  from public.order_items oi
  join public.products p on p.id = oi.product_id
  join public.orders o2 on o2.id = oi.order_id
  where p.is_unique
    and p.piece_status = 'booked'
    and o2.status not in ('delivered','cancelled')
  order by oi.product_id, o2.created_at desc
) b
where o.id = b.order_id;

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
     expected_date, booked_product_id, order_number)
  values (
    auth.uid(), p_customer_id, p_lead_id, p_notes, p_discount, p_shipping_fee,
    p_expected_date, p_book_product_id,
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
  from orders where id = p_order_id and user_id = auth.uid()
  for update;

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
    and id = (select booked_product_id from orders where id = p_order_id);
end;
$$;

revoke all on function public.cancel_order(uuid) from public, anon;
grant execute on function public.cancel_order(uuid) to authenticated;

-- Replace mark_order_delivered from 0011 to scope the sold-piece update to
-- this order's booked_product_id. The forward-only guard (shipped only) and
-- idempotency semantics from 0011 are preserved exactly.
create or replace function public.mark_order_delivered(p_order_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not exists (
    select 1 from orders
    where id = p_order_id and user_id = auth.uid() and status = 'shipped'
  ) then
    raise exception 'order_not_shipped';
  end if;

  update orders
  set status = 'delivered', delivered_at = now()
  where id = p_order_id and user_id = auth.uid() and status = 'shipped';

  update products set piece_status = 'sold'
  where user_id = auth.uid()
    and is_unique
    and piece_status = 'booked'
    and id = (select booked_product_id from orders where id = p_order_id);
end;
$$;

revoke all on function public.mark_order_delivered(uuid) from public, anon;
grant execute on function public.mark_order_delivered(uuid) to authenticated;

-- Replace record_payment from 0013 to: lock the order row (prevents payments
-- racing with cancel_order), and raise when order is already cancelled.
-- Signature, security mode, search_path, and grants match 0013 exactly.
create or replace function public.record_payment(
  p_order_id uuid,
  p_amount numeric,
  p_method text
) returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_status text;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  if p_method is null or p_method not in ('upi', 'cash', 'other') then
    raise exception 'invalid_method';
  end if;

  select status into v_order_status
  from orders where id = p_order_id and user_id = auth.uid()
  for update;

  if v_order_status is null then
    raise exception 'order_not_found';
  end if;

  if v_order_status = 'cancelled' then
    raise exception 'order_cancelled';
  end if;

  insert into payments (user_id, order_id, amount, method)
  values (auth.uid(), p_order_id, p_amount, p_method);

  update orders o set payment_status = case
      -- 'unpaid' is unreachable after a validated amount > 0 insert; kept as a
      -- defensive default and reserved for a future refund/delete path.
      when coalesce(paid.total, 0) <= 0 then 'unpaid'
      when coalesce(paid.total, 0) >= o.grand_total then 'paid'
      else 'partial'
    end
  from (
    select coalesce(sum(amount), 0) as total
    from payments
    where order_id = p_order_id and user_id = auth.uid()
  ) paid
  where o.id = p_order_id and o.user_id = auth.uid();
end;
$$;

revoke all on function public.record_payment(uuid, numeric, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, text) to authenticated;
