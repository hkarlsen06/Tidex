-- Migration: create_consumable_transactions
-- Applied remotely as version 20260214141437

create table public.consumable_transactions (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  apple_transaction_id text not null unique,
  apple_original_transaction_id text not null,
  apple_product_id text not null,
  credits_granted integer not null default 0,
  environment text not null default 'Sandbox',
  created_at timestamptz not null default now()
);

create index idx_consumable_transactions_user_id on public.consumable_transactions (user_id);

alter table public.consumable_transactions enable row level security;

create policy "Users can view own consumable transactions"
  on public.consumable_transactions
  for select
  using (auth.uid() = user_id);
