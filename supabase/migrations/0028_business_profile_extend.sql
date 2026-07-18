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

-- Storage bucket for business logo + signature uploads.
insert into storage.buckets (id, name, public)
values ('business-assets', 'business-assets', true)
on conflict (id) do nothing;

-- Owner can write only under their own uid/ prefix; public read (logos appear on
-- shared invoices).
create policy "business-assets read"
  on storage.objects for select
  using (bucket_id = 'business-assets');

create policy "business-assets write own"
  on storage.objects for insert
  with check (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "business-assets update own"
  on storage.objects for update
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
