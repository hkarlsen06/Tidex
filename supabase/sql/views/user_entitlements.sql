-- View: user_entitlements
-- Purpose: Provides a unified view of user subscription entitlements
-- Used by: RLS policies, admin queries, and debugging
--
-- Note: product_id is the single source of truth for subscription tier.
-- Edge functions (Stripe webhook, Apple webhooks) normalize external IDs to internal product_id.
-- Internal product IDs: pro_monthly, pro_yearly, max_monthly, max_yearly
-- Apple product IDs: no.tidex.pro, no.tidex.pro.year, no.tidex.max, no.tidex.max.year

CREATE OR REPLACE VIEW user_entitlements AS
SELECT
  u.id AS user_id,
  COALESCE(p.before_paywall, false) AS is_grandfathered,
  (EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
  )) AS has_active_subscription,
  -- is_entitled: grandfathered OR has active subscription
  COALESCE(p.before_paywall, false) OR (EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
  )) AS is_entitled,
  -- active_provider: which provider the active subscription is from (stripe, apple, admin_trial)
  (SELECT s.provider
   FROM subscriptions s
   WHERE s.user_id = u.id
     AND s.status IN ('active', 'trialing', 'grace')
     AND (s.current_period_end IS NULL OR s.current_period_end > now())
   ORDER BY s.current_period_end DESC NULLS LAST
   LIMIT 1) AS active_provider,
  -- active_product_id: internal product ID (pro_monthly, pro_yearly, max_monthly, max_yearly)
  -- or Apple product ID (no.tidex.pro, etc.)
  (SELECT s.product_id
   FROM subscriptions s
   WHERE s.user_id = u.id
     AND s.status IN ('active', 'trialing', 'grace')
     AND (s.current_period_end IS NULL OR s.current_period_end > now())
   ORDER BY s.current_period_end DESC NULLS LAST
   LIMIT 1) AS active_product_id,
  -- subscription_ends_at: when the subscription period ends
  (SELECT s.current_period_end
   FROM subscriptions s
   WHERE s.user_id = u.id
     AND s.status IN ('active', 'trialing', 'grace')
     AND (s.current_period_end IS NULL OR s.current_period_end > now())
   ORDER BY s.current_period_end DESC NULLS LAST
   LIMIT 1) AS subscription_ends_at
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id;
