-- Record a payment against an order and recompute the order's payment_status
-- from the sum of its payments. Invoker-scoped: runs under the caller's RLS,
-- validates inputs, and only ever touches auth.uid()'s own rows.

create or replace function public.record_payment(
  p_order_id uuid,
  p_amount numeric,
  p_method text
) returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  if p_method is null or p_method not in ('upi', 'cash', 'other') then
    raise exception 'invalid_method';
  end if;

  if not exists (
    select 1 from orders where id = p_order_id and user_id = auth.uid()
  ) then
    raise exception 'order_not_found';
  end if;

  insert into payments (user_id, order_id, amount, method)
  values (auth.uid(), p_order_id, p_amount, p_method);

  update orders o set payment_status = case
      when coalesce(paid.total, 0) <= 0 then 'unpaid'
      when coalesce(paid.total, 0) >= o.grand_total then 'paid'
      else 'partial'
    end
  from (
    select coalesce(sum(amount), 0) as total
    from payments where order_id = p_order_id
  ) paid
  where o.id = p_order_id and o.user_id = auth.uid();
end;
$$;

revoke all on function public.record_payment(uuid, numeric, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, text) to authenticated;
