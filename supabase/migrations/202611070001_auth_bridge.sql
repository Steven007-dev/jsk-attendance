-- Private mapping between Supabase Auth identities and the existing JSK IDs.
-- The bridge function uses the service role; browser and mobile clients never
-- read this table directly.
create table if not exists public.jsk_auth_profiles (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  app_user_id text not null unique,
  role text not null check (role in ('admin', 'staff', 'teacher', 'student', 'guardian')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.jsk_auth_profiles enable row level security;
revoke all on table public.jsk_auth_profiles from public, anon, authenticated;
grant all on table public.jsk_auth_profiles to service_role;

-- Limit password-verified legacy bootstrap attempts by normalized email hash.
create table if not exists public.jsk_auth_bootstrap_limits (
  email_hash text primary key,
  window_started_at timestamptz not null,
  attempts integer not null default 0
);

alter table public.jsk_auth_bootstrap_limits enable row level security;
revoke all on table public.jsk_auth_bootstrap_limits from public, anon, authenticated;
grant all on table public.jsk_auth_bootstrap_limits to service_role;

create or replace function public.jsk_consume_auth_bootstrap_attempt(p_email_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts integer;
begin
  insert into public.jsk_auth_bootstrap_limits(email_hash, window_started_at, attempts)
  values (p_email_hash, pg_catalog.clock_timestamp(), 1)
  on conflict (email_hash) do update
  set window_started_at = case
        when public.jsk_auth_bootstrap_limits.window_started_at < pg_catalog.clock_timestamp() - interval '1 hour'
          then pg_catalog.clock_timestamp()
        else public.jsk_auth_bootstrap_limits.window_started_at
      end,
      attempts = case
        when public.jsk_auth_bootstrap_limits.window_started_at < pg_catalog.clock_timestamp() - interval '1 hour'
          then 1
        else public.jsk_auth_bootstrap_limits.attempts + 1
      end
  returning attempts into v_attempts;

  return v_attempts <= 8;
end;
$$;

revoke all on function public.jsk_consume_auth_bootstrap_attempt(text) from public, anon, authenticated;
grant execute on function public.jsk_consume_auth_bootstrap_attempt(text) to service_role;
