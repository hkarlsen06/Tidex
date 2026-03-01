-- Add default startup tab preference for mobile app launch behavior.
alter table public.user_settings
  add column if not exists default_startup_tab text not null default 'home';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_settings_default_startup_tab_valid'
      and conrelid = 'public.user_settings'::regclass
  ) then
    alter table public.user_settings
      add constraint user_settings_default_startup_tab_valid
      check (default_startup_tab in ('home', 'shifts', 'add', 'stats', 'sharing'));
  end if;
end $$;

comment on column public.user_settings.default_startup_tab is
  'Default tab to open when launching the app: home, shifts, add, stats, or sharing.';
