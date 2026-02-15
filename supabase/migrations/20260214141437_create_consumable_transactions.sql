-- Table: consumable_transactions
-- Tracks Apple IAP consumable purchases (e.g., Wagey credit packs)

create table public.consumable_transactions (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  apple_transaction_id text unique not null,
  apple_original_transaction_id text not null,
  apple_product_id text not null,
  credits_granted integer not null default 0,
  environment text not null default 'Sandbox',
  created_at timestamptz not null default now()
);

-- Index for fast user lookups
create index idx_consumable_transactions_user_id on public.consumable_transactions(user_id);

-- Enable RLS
alter table public.consumable_transactions enable row level security;

-- Policy: users can read their own transactions
create policy "Users can view own consumable transactions"
  on public.consumable_transactions
  for select
  using (auth.uid() = user_id);;
