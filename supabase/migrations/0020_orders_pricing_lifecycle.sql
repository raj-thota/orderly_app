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
