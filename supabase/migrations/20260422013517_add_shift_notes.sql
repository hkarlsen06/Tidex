alter table public.user_shifts
add column if not exists note text;

alter table public.recurring_shifts
add column if not exists date_specific_notes jsonb;
