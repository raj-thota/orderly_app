-- Close a same-order race in assign_invoice_number: lock the order row on the
-- idempotency read so two overlapping calls for the same order can't both see a
-- null invoice_number and both assign (which would overwrite one number and
-- leave a permanent gap in the sequence). Lock order first, then profile — a
-- consistent order that avoids deadlock.

create or replace function public.assign_invoice_number(p_order_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_existing text;
  v_prefix text;
  v_next integer;
  v_number text;
begin
  select invoice_number into v_existing
  from orders where id = p_order_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'order_not_found';
  end if;

  -- Idempotent: never burn a second number for an already-invoiced order.
  if v_existing is not null then
    return v_existing;
  end if;

  select invoice_prefix, next_invoice_number into v_prefix, v_next
  from business_profile where user_id = auth.uid()
  for update;

  if not found then
    raise exception 'business_profile_missing';
  end if;

  v_number := v_prefix || lpad(v_next::text, 4, '0');

  update orders set invoice_number = v_number
  where id = p_order_id and user_id = auth.uid();

  update business_profile set next_invoice_number = v_next + 1
  where user_id = auth.uid();

  return v_number;
end;
$$;

revoke all on function public.assign_invoice_number(uuid) from public, anon;
grant execute on function public.assign_invoice_number(uuid) to authenticated;
