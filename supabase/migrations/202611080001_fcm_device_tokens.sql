-- Private FCM registrations. Clients can only register/remove their own
-- device through the authenticated jsk-sync Edge Function.
create table if not exists public.jsk_push_tokens (
  token_hash text primary key,
  token text not null,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  app_user_id text not null,
  platform text not null check (platform in ('android', 'web', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists jsk_push_tokens_user_idx
  on public.jsk_push_tokens (app_user_id);

alter table public.jsk_push_tokens enable row level security;
revoke all on table public.jsk_push_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.jsk_push_tokens to service_role;
