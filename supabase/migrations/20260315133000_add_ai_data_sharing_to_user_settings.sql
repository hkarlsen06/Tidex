alter table public.user_settings
  add column if not exists ai_data_sharing_enabled boolean not null default false;

comment on column public.user_settings.ai_data_sharing_enabled is
  'Whether the user has consented to Wagey AI data sharing.';
