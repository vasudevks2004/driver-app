-- Stores only request/payload hashes and delivery state, never OTPs or numbers.
create table if not exists public.driver_sms_delivery_receipts (
  id_hash text primary key check (id_hash ~ '^[a-f0-9]{64}$'),
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  status text not null check (status in ('sending','sent','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.driver_sms_delivery_receipts enable row level security;
revoke all on public.driver_sms_delivery_receipts from public, anon, authenticated;
grant select, insert, update, delete on public.driver_sms_delivery_receipts to service_role;
create index if not exists driver_sms_delivery_receipts_created_idx on public.driver_sms_delivery_receipts(created_at);
