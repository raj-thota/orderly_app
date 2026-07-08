-- Harden mark_order_delivered: deliver only from the 'shipped' state, so the
-- RPC (the real trust boundary, callable directly by any authenticated user)
-- enforces the same forward-only lifecycle the UI does. This also makes it
-- idempotent-safe: re-calling on an already-delivered order raises instead of
-- re-stamping delivered_at.

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
    and id in (
      select product_id from order_items
      where order_id = p_order_id and product_id is not null
    );
end;
$$;

revoke all on function public.mark_order_delivered(uuid) from public, anon;
grant execute on function public.mark_order_delivered(uuid) to authenticated;
