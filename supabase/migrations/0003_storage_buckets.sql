-- Private storage buckets for product photos and payment proofs.
-- Files stored under a <user_id>/... path prefix so policies scope by first folder.

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', false),
       ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

-- product-images: owner-only, scoped by top folder = user id
create policy "product-images read own" on storage.objects
  for select using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "product-images write own" on storage.objects
  for insert with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "product-images update own" on storage.objects
  for update using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "product-images delete own" on storage.objects
  for delete using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- payment-proofs: owner-only
create policy "payment-proofs read own" on storage.objects
  for select using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "payment-proofs write own" on storage.objects
  for insert with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "payment-proofs update own" on storage.objects
  for update using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "payment-proofs delete own" on storage.objects
  for delete using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
