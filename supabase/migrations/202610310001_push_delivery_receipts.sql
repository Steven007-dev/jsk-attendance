-- Push receipts are private server state. The Edge Function uses the
-- Supabase service role; client roles must never read or write this table.
create table if not exists public.push_delivery_receipts (
  delivery_key text primary key,
  notification_id text not null,
  status text not null check (status in ('existing', 'processing', 'sent', 'failed')),
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.push_delivery_receipts enable row level security;
revoke all on public.push_delivery_receipts from anon, authenticated;
grant select, insert, update on public.push_delivery_receipts to service_role;

-- Mark the current inbox as historical before the database webhook is enabled,
-- so installing push delivery never blasts old notifications to users.
insert into public.push_delivery_receipts (delivery_key, notification_id, status)
select
  (item ->> 'id') || ':' || coalesce(item ->> 'ts', '0'),
  item ->> 'id',
  'existing'
from public.app_data as app,
     lateral jsonb_array_elements(
       case
         when jsonb_typeof(app.content -> 'inbox') = 'array' then app.content -> 'inbox'
         else '[]'::jsonb
       end
     ) as item
where app.id = 'main_state'
  and nullif(item ->> 'id', '') is not null
on conflict (delivery_key) do nothing;
