-- Private bucket for chat screenshots attached to enquiries, plus the lead
-- column that stores the uploaded object path. Files live under a
-- <user_id>/... prefix so policies scope by the first path folder, exactly
-- like product-images (migration 0003).
insert into storage.buckets (id, name, public)
values ('enquiry-attachments', 'enquiry-attachments', false)
on conflict (id) do nothing;

create policy "enquiry-attachments read own" on storage.objects
  for select using (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "enquiry-attachments write own" on storage.objects
  for insert with check (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "enquiry-attachments update own" on storage.objects
  for update using (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "enquiry-attachments delete own" on storage.objects
  for delete using (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

alter table public.leads
  add column if not exists screenshot_url text;

-- Allow capture sources introduced by the vision + share slices.
alter table public.leads drop constraint leads_source_check;
alter table public.leads add constraint leads_source_check
  check (source in ('dm','paste','product','manual','screenshot','share'));
