-- Capture slice support: phone-less customers + atomic order creation.

-- customers.phone becomes optional; uniqueness applies only when present.
alter table public.customers alter column phone drop not null;
alter table public.customers drop constraint customers_user_id_phone_key;
create unique index customers_user_phone_unique
  on public.customers(user_id, phone) where phone is not null;

-- Atomic order creation used by capture save-as-order and enquiry conversion.
-- security invoker: every statement runs under the caller's RLS policies.
create or replace function public.create_order_with_items(
  p_customer_id uuid,
  p_lead_id uuid,
  p_items jsonb,
  p_book_product_id uuid default null,
  p_notes text default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_subtotal numeric(12,2) := 0;
  v_item jsonb;
  v_price numeric(12,2);
  v_qty integer;
begin
  insert into orders (user_id, customer_id, lead_id, notes)
  values (auth.uid(), p_customer_id, p_lead_id, p_notes)
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

  update orders set subtotal = v_subtotal, grand_total = v_subtotal
  where id = v_order_id;

  if p_lead_id is not null then
    update leads set status = 'won'
    where id = p_lead_id and user_id = auth.uid();
  end if;

  if p_book_product_id is not null then
    update products set piece_status = 'booked'
    where id = p_book_product_id and user_id = auth.uid() and is_unique;
  end if;

  return v_order_id;
end;
$$;

revoke all on function public.create_order_with_items(uuid, uuid, jsonb, uuid, text) from public, anon;
grant execute on function public.create_order_with_items(uuid, uuid, jsonb, uuid, text) to authenticated;
