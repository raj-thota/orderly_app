-- Harden create_order_with_items:
-- 1. Ownership checks for client-supplied ids (FK checks bypass RLS).
-- 2. Unique-piece booking must atomically claim an available piece; an
--    already-booked/sold piece aborts the whole transaction instead of
--    silently no-opping (prevents double-selling a one-of-one piece).
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

  return v_order_id;
end;
$$;
