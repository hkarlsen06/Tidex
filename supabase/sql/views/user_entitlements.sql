-- View: user_entitlements
-- Purpose: Provides a unified view of user subscription entitlements
-- Used by: RLS policies, admin queries, iOS app, and debugging
--
-- Note: product_id is the single source of truth for subscription tier.
-- Edge functions (Stripe webhook, Apple webhooks) normalize external IDs to internal product_id.
-- Internal product IDs: pro_monthly, pro_yearly, max_monthly, max_yearly
-- Apple product IDs: no.tidex.pro, no.tidex.pro.year, no.tidex.max, no.tidex.max.year
--
-- Performance: Uses LATERAL join to compute active subscription ONCE per user,
-- avoiding repeated correlated subqueries for each column.
--
-- Security: Direct SELECT is revoked from anon/authenticated roles.
-- Clients must use get_my_entitlement() RPC function which enforces auth.uid().

CREATE OR REPLACE VIEW public.user_entitlements AS
SELECT
  u.id AS user_id,
  COALESCE(p.before_paywall, false) AS is_grandfathered,
  (s.user_id IS NOT NULL) AS has_active_subscription,
  (COALESCE(p.before_paywall, false) OR (s.user_id IS NOT NULL)) AS is_entitled,
  s.provider AS active_provider,
  s.product_id AS active_product_id,
  s.current_period_end AS subscription_ends_at,

  -- tier column (free|pro|max) - single source of truth
  -- All tier logic lives here, iOS just reads this column
  CASE
    -- Grandfathered without active subscription = pro
    WHEN COALESCE(p.before_paywall, false) AND s.user_id IS NULL THEN 'pro'
    -- Has Max subscription (internal or Apple product IDs)
    WHEN s.product_id IN ('max_monthly', 'max_yearly', 'no.tidex.max', 'no.tidex.max.year') THEN 'max'
    -- Has Pro subscription (internal or Apple product IDs)
    WHEN s.product_id IN ('pro_monthly', 'pro_yearly', 'no.tidex.pro', 'no.tidex.pro.year') THEN 'pro'
    -- Grandfathered with any subscription (edge case: unknown product)
    WHEN COALESCE(p.before_paywall, false) THEN 'pro'
    -- Default: free
    ELSE 'free'
  END AS tier

FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
-- LATERAL join computes active subscription ONCE per user (efficient)
-- Avoids repeated correlated subqueries for each column
LEFT JOIN LATERAL (
  SELECT s_1.user_id, s_1.provider, s_1.product_id, s_1.current_period_end
  FROM subscriptions s_1
  WHERE s_1.user_id = u.id
    AND s_1.status IN ('active', 'trialing', 'grace')
    AND (s_1.current_period_end IS NULL OR s_1.current_period_end > now())
  ORDER BY s_1.current_period_end DESC NULLS LAST
  LIMIT 1
) s ON true;

-- Revoke direct access from client roles (security)
REVOKE ALL ON public.user_entitlements FROM anon;
REVOKE ALL ON public.user_entitlements FROM authenticated;

-- Keep access for admin roles
GRANT SELECT ON public.user_entitlements TO service_role;
GRANT SELECT ON public.user_entitlements TO postgres;
