-- Create user entitlements view and helper functions

-- View to check user entitlement status (grandfathered OR active subscription)
CREATE OR REPLACE VIEW user_entitlements AS
SELECT
  u.id AS user_id,
  COALESCE(p.before_paywall, false) AS is_grandfathered,
  EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
  ) AS has_active_subscription,
  COALESCE(p.before_paywall, false) OR EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
  ) AS is_entitled,
  (
    SELECT s.provider FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
    ORDER BY s.current_period_end DESC NULLS LAST
    LIMIT 1
  ) AS active_provider,
  (
    SELECT COALESCE(s.product_id, s.price_id) FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
    ORDER BY s.current_period_end DESC NULLS LAST
    LIMIT 1
  ) AS active_product_id,
  (
    SELECT s.current_period_end FROM subscriptions s
    WHERE s.user_id = u.id
      AND s.status IN ('active', 'trialing', 'grace')
      AND (s.current_period_end IS NULL OR s.current_period_end > now())
    ORDER BY s.current_period_end DESC NULLS LAST
    LIMIT 1
  ) AS subscription_ends_at
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id;

-- Function to get user entitlement status as JSON
CREATE OR REPLACE FUNCTION get_user_entitlement_status(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT jsonb_build_object(
    'user_id', user_id,
    'is_entitled', is_entitled,
    'is_grandfathered', is_grandfathered,
    'has_active_subscription', has_active_subscription,
    'active_provider', active_provider,
    'active_product_id', active_product_id,
    'subscription_ends_at', subscription_ends_at
  )
  FROM user_entitlements
  WHERE user_id = p_user_id;
$$;

-- Function to check if user has shift storage entitlement
CREATE OR REPLACE FUNCTION has_shift_storage_entitlement(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (SELECT is_entitled FROM user_entitlements WHERE user_id = p_user_id),
    false
  );
$$;

-- Function to get or create app account token for a user
CREATE OR REPLACE FUNCTION get_or_create_app_account_token(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token uuid;
BEGIN
  -- First try to get existing token
  SELECT token INTO v_token
  FROM app_account_tokens
  WHERE user_id = p_user_id;

  -- If not found, create one
  IF v_token IS NULL THEN
    INSERT INTO app_account_tokens (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
    RETURNING token INTO v_token;
  END IF;

  RETURN v_token;
END;
$$;

-- Function to look up user by app account token
CREATE OR REPLACE FUNCTION get_user_id_by_app_account_token(p_token uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT user_id FROM app_account_tokens WHERE token = p_token;
$$;
