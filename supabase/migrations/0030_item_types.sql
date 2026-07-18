-- Item types: products gain a type + per-type fields; order_items snapshot the
-- type for badge display. Lifecycle is unchanged. Idempotent.

alter table public.products
  add column if not exists type text not null default 'product',
  add column if not exists category text,
  add column if not exists duration text,
  add column if not exists delivery_method text;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_type_check'
  ) then
    alter table public.products
      add constraint products_type_check
      check (type in ('product','service','digital','other'));
  end if;
end $$;

alter table public.order_items
  add column if not exists item_type text not null default 'product';

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'order_items_item_type_check'
  ) then
    alter table public.order_items
      add constraint order_items_item_type_check
      check (item_type in ('product','service','digital','other'));
  end if;
end $$;

create index if not exists idx_products_user_type
  on public.products(user_id, type);

create or replace function public.create_order_with_items(
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
      (user_id, order_id, product_id, name, image_url, item_type, unit_price, gst_rate, qty, line_total)
    values (
      auth.uid(),
      v_order_id,
      nullif(v_item->>'product_id', '')::uuid,
      coalesce(nullif(v_item->>'name', ''), 'Item'),
      v_item->>'image_url',
      coalesce(nullif(v_item->>'item_type', ''), 'product'),
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
