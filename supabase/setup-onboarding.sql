-- Additive onboarding storage. Applicants never receive driver/admin privileges.
create table if not exists public.driver_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 100),
  city text not null check (char_length(city) between 2 and 80),
  verified_phone text not null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected')),
  birth_date date,
  licence_number text,
  licence_expiry date,
  vehicle_class text check (vehicle_class in ('LMV','TRANSPORT','BOTH')),
  selfie_path text,
  licence_front_path text,
  licence_back_path text,
  aadhaar_number text check (aadhaar_number ~ '^[2-9][0-9]{11}$'),
  aadhaar_path text,
  digilocker_document_path text,
  digilocker_document_uri text,
  digilocker_status text not null default 'not_connected'
    check (digilocker_status in ('not_connected','pending','document_received','failed')),
  consent_version text,
  consented_at timestamptz,
  submitted_at timestamptz,
  created_at timestamptz not null default now()
);
-- Safe to run against an existing v1 onboarding installation as well.
alter table public.driver_applications
  add column if not exists aadhaar_number text check (aadhaar_number ~ '^[2-9][0-9]{11}$'),
  add column if not exists aadhaar_path text;
alter table public.driver_applications enable row level security;
-- Access is exclusively through the authenticated function. Deny direct writes,
-- including attempts to self-approve or set DigiLocker verification flags.
revoke all on public.driver_applications from public, anon, authenticated;
grant select, insert, update, delete on public.driver_applications to service_role;

create table if not exists public.driver_digilocker_requests (
  state_hash text primary key,
  application_id uuid not null references public.driver_applications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  code_verifier text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consented_at timestamptz not null default now()
);
alter table public.driver_digilocker_requests enable row level security;
revoke all on public.driver_digilocker_requests from public, anon, authenticated;
grant select, insert, update, delete on public.driver_digilocker_requests to service_role;
create index if not exists driver_digilocker_requests_expiry_idx on public.driver_digilocker_requests(expires_at);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('driver-onboarding-private', 'driver-onboarding-private', false, 6291456,
  array['image/jpeg','image/png','application/pdf'])
on conflict (id) do nothing;
-- Deliberately no storage.objects policies for client roles on this bucket.
-- The service validates identity, ownership, type and size before every upload.
