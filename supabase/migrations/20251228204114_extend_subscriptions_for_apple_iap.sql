-- Extend subscriptions table for Apple IAP support

-- Add provider column to distinguish between Stripe and Apple
ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'stripe'
  CONSTRAINT subscriptions_provider_check CHECK (provider = ANY (ARRAY['stripe'::text, 'apple'::text]));

COMMENT ON COLUMN subscriptions.provider IS 'Payment provider: stripe or apple';

-- Add provider-agnostic subscription ID
ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS provider_subscription_id text;

COMMENT ON COLUMN subscriptions.provider_subscription_id IS 'Provider-specific subscription ID (Stripe sub_xxx or Apple originalTransactionId)';

-- Add product_id for internal mapping
ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS product_id text;

COMMENT ON COLUMN subscriptions.product_id IS 'Internal product identifier mapped from provider-specific IDs';

-- Add current_period_start for billing period tracking
ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS current_period_start timestamptz;

COMMENT ON COLUMN subscriptions.current_period_start IS 'Start of current billing period';

-- Apple-specific columns
ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS apple_original_transaction_id text;

COMMENT ON COLUMN subscriptions.apple_original_transaction_id IS 'Apple StoreKit original transaction ID (stable across renewals)';

ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS apple_last_transaction_id text;

COMMENT ON COLUMN subscriptions.apple_last_transaction_id IS 'Apple StoreKit most recent transaction ID';

ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS apple_environment text
  CONSTRAINT subscriptions_apple_environment_check CHECK (apple_environment IS NULL OR (apple_environment = ANY (ARRAY['Production'::text, 'Sandbox'::text])));

COMMENT ON COLUMN subscriptions.apple_environment IS 'Apple environment: Production or Sandbox';

ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS app_account_token uuid;

COMMENT ON COLUMN subscriptions.app_account_token IS 'UUID token linking Apple purchase to Tidex user';

ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS raw_provider_payload jsonb;

COMMENT ON COLUMN subscriptions.raw_provider_payload IS 'Raw JSON payload from provider for debugging';

-- Extend status constraint to include Apple-specific statuses
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
ALTER TABLE subscriptions
ADD CONSTRAINT subscriptions_status_check CHECK (status = ANY (ARRAY[
  'active'::text,
  'trialing'::text,
  'past_due'::text,
  'incomplete'::text,
  'paused'::text,
  'canceled'::text,
  'incomplete_expired'::text,
  'unpaid'::text,
  'grace'::text,
  'expired'::text,
  'refunded'::text
]));

-- Indexes for Apple IAP queries
CREATE INDEX IF NOT EXISTS idx_subscriptions_provider ON subscriptions(provider);
CREATE INDEX IF NOT EXISTS idx_subscriptions_provider_subscription_id ON subscriptions(provider, provider_subscription_id) WHERE provider_subscription_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_apple_original_transaction_id ON subscriptions(apple_original_transaction_id) WHERE apple_original_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_status_period_end ON subscriptions(status, current_period_end);
CREATE INDEX IF NOT EXISTS idx_subscriptions_app_account_token ON subscriptions(app_account_token) WHERE app_account_token IS NOT NULL;

-- Unique constraint to prevent duplicate Apple subscriptions
CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_unique_apple_transaction ON subscriptions(apple_original_transaction_id) WHERE provider = 'apple' AND apple_original_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_unique_provider_sub ON subscriptions(provider, provider_subscription_id) WHERE provider_subscription_id IS NOT NULL;

-- App account tokens table for linking Apple purchases to users
CREATE TABLE IF NOT EXISTS app_account_tokens (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  token uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE app_account_tokens IS 'Stable UUID tokens linking Apple IAP purchases to Tidex users';

CREATE INDEX IF NOT EXISTS idx_app_account_tokens_token ON app_account_tokens(token);

-- RLS for app_account_tokens
ALTER TABLE app_account_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own app_account_token" ON app_account_tokens
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own app_account_token" ON app_account_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);
