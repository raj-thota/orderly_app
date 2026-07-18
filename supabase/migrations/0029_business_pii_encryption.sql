-- Encrypt sensitive business PII (bank account number + PAN) at rest.
--
-- Design: the plaintext columns bank_account_number / pan remain as the WRITE
-- channel (the client keeps upserting plaintext). A BEFORE trigger encrypts them
-- into bytea *_enc columns using a Vault-held key and nulls the plaintext, so
-- cleartext is never persisted. Reads go through get_business_sensitive(), an
-- owner-scoped SECURITY DEFINER RPC that decrypts for the calling user only.
-- IFSC and account-holder name stay plaintext (IFSC is public routing info).

-- 1. Private schema for internals that must NOT be exposed via PostgREST/RPC.
create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
-- authenticated needs USAGE so the BEFORE trigger's function resolves on write.
grant usage on schema private to authenticated;

-- 2. Encryption key in Vault (idempotent).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'business_pii_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'business_pii_key',
      'Symmetric key for business_profile PII column encryption'
    );
  end if;
end $$;

-- 3. Ciphertext columns.
alter table public.business_profile
  add column if not exists bank_account_number_enc bytea,
  add column if not exists pan_enc                 bytea;

-- 4. Key accessor — SECURITY DEFINER, locked to internal callers only.
create or replace function private._business_pii_key()
returns text
language sql
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'business_pii_key' limit 1;
$$;
revoke all on function private._business_pii_key() from public;
revoke all on function private._business_pii_key() from anon;
revoke all on function private._business_pii_key() from authenticated;

-- 5. Trigger: encrypt incoming plaintext, then null it so cleartext is never stored.
create or replace function private.encrypt_business_sensitive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := private._business_pii_key();
begin
  if new.bank_account_number is not null then
    new.bank_account_number_enc :=
      extensions.pgp_sym_encrypt(new.bank_account_number, v_key);
    new.bank_account_number := null;
  end if;
  if new.pan is not null then
    new.pan_enc := extensions.pgp_sym_encrypt(new.pan, v_key);
    new.pan := null;
  end if;
  return new;
end;
$$;
-- The trigger fires automatically; authenticated may resolve it but cannot read
-- the key (execute on _business_pii_key stays revoked).
grant execute on function private.encrypt_business_sensitive() to authenticated;

drop trigger if exists trg_encrypt_business_sensitive on public.business_profile;
create trigger trg_encrypt_business_sensitive
  before insert or update on public.business_profile
  for each row execute function private.encrypt_business_sensitive();

-- 6. Backfill: encrypt any plaintext already present (touch rows so the trigger runs).
update public.business_profile
  set updated_at = now()
  where bank_account_number is not null or pan is not null;

-- 7. Owner-scoped decrypt RPC for the client read path.
create or replace function public.get_business_sensitive()
returns table(bank_account_number text, pan text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  select
    case when bp.bank_account_number_enc is not null
      then extensions.pgp_sym_decrypt(bp.bank_account_number_enc, private._business_pii_key())
    end,
    case when bp.pan_enc is not null
      then extensions.pgp_sym_decrypt(bp.pan_enc, private._business_pii_key())
    end
  from public.business_profile bp
  where bp.user_id = auth.uid();
end;
$$;
revoke all on function public.get_business_sensitive() from public;
revoke all on function public.get_business_sensitive() from anon;
grant execute on function public.get_business_sensitive() to authenticated;
