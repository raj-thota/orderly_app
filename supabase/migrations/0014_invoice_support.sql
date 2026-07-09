-- Per-business default invoice template, and an idempotent sequential
-- invoice-number assigner. Invoker-scoped: touches only auth.uid()'s rows.

alter table public.business_profile
  add column invoice_template text not null default 'classic'
  check (invoice_template in ('classic', 'minimal', 'boutique'));

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
  from orders where id = p_order_id and user_id = auth.uid();

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
