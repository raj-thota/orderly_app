-- Phase 1 UX consolidation: extend business_profile for the expanded
-- Business Profile + Invoice Settings screens. All columns nullable / defaulted
-- so existing rows and pre-migration app builds keep working.

alter table public.business_profile
  add column if not exists owner_name             text,
  add column if not exists city                   text,
  add column if not exists state                  text,
  add column if not exists pincode                text,
  add column if not exists pan                    text,
  add column if not exists business_type          text,
  add column if not exists bank_account_name      text,
  add column if not exists bank_account_number    text,
  add column if not exists bank_ifsc              text,
  add column if not exists default_payment_method text,
  add column if not exists gst_enabled            boolean not null default false,
  add column if not exists payment_terms          text,
  add column if not exists invoice_footer         text,
  add column if not exists signature_url          text,
  add column if not exists language               text not null default 'en',
  add column if not exists timezone               text not null default 'Asia/Kolkata';

-- Storage buckets:
--   business-assets    = public read (logos appear on customer-facing invoices)
--   business-signatures = private (signatures are sensitive; owner-only + signed URLs)
insert into storage.buckets (id, name, public)
values ('business-assets', 'business-assets', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('business-signatures', 'business-signatures', false)
on conflict (id) do nothing;

-- Policies are dropped-then-created so this migration is re-runnable
-- (Postgres has no `create policy if not exists`).

-- business-assets: public bucket. No SELECT policy — public buckets serve objects
-- by direct URL without one, and a broad SELECT policy would let clients LIST
-- (enumerate) every tenant's files. Write/update/delete scoped to the owner's uid.
drop policy if exists "business-assets read" on storage.objects;

drop policy if exists "business-assets write own" on storage.objects;
create policy "business-assets write own"
  on storage.objects for insert
  with check (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "business-assets update own" on storage.objects;
create policy "business-assets update own"
  on storage.objects for update
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "business-assets delete own" on storage.objects;
create policy "business-assets delete own"
  on storage.objects for delete
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- business-signatures: fully owner-scoped, including read.
drop policy if exists "business-signatures read own" on storage.objects;
create policy "business-signatures read own"
  on storage.objects for select
  using (
    bucket_id = 'business-signatures'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "business-signatures write own" on storage.objects;
create policy "business-signatures write own"
  on storage.objects for insert
  with check (
    bucket_id = 'business-signatures'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "business-signatures update own" on storage.objects;
create policy "business-signatures update own"
  on storage.objects for update
  using (
    bucket_id = 'business-signatures'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'business-signatures'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "business-signatures delete own" on storage.objects;
create policy "business-signatures delete own"
  on storage.objects for delete
  using (
    bucket_id = 'business-signatures'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
