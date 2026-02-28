-- Add a user setting controlling dashboard clock button visibility.
alter table public.user_settings
  add column if not exists show_dashboard_clock_buttons boolean not null default true;

comment on column public.user_settings.show_dashboard_clock_buttons is
  'Whether Clock in/Clock out buttons are shown on the dashboard UI.';
