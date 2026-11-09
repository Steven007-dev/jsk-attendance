-- Apply only after the updated PWA is deployed and the replacement Android
-- APK is ready. The JSK clients now read/write app_data through jsk-sync.
alter table public.app_data enable row level security;
revoke all on table public.app_data from public, anon, authenticated;
grant select, insert, update, delete on table public.app_data to service_role;

-- This helper is not called by either client. Keep its SECURITY DEFINER
-- execution private and pin its object lookup path.
alter function public.handle_new_announcement() set search_path = pg_catalog, public;
revoke all on function public.handle_new_announcement() from public, anon, authenticated;
