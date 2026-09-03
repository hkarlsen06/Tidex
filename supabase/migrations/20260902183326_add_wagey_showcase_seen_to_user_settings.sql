alter table public.user_settings
  add column if not exists wagey_showcase_seen boolean not null default false;

comment on column public.user_settings.wagey_showcase_seen is
  'Whether the user has dismissed the Wagey showcase';
