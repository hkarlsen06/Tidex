-- admin_get_subscribers
-- Returns users with active subscriptions OR grandfathered status
-- User info (email, name) will be joined via auth.admin API in the server action

CREATE OR REPLACE FUNCTION admin_get_subscribers()
RETURNS TABLE (
  user_id UUID,
  subscription_id UUID,
  provider TEXT,
  product_id TEXT,
  price_id TEXT,
  status TEXT,
  current_period_end TIMESTAMPTZ,
  is_grandfathered BOOLEAN
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    sub.user_id,
    sub.subscription_id,
    sub.provider,
    sub.product_id,
    sub.price_id,
    sub.status,
    sub.current_period_end,
    sub.is_grandfathered
  FROM (
    SELECT DISTINCT ON (COALESCE(s.user_id, p.id))
      COALESCE(s.user_id, p.id) as user_id,
      s.id as subscription_id,
      s.provider,
      s.product_id,
      s.price_id,
      s.status,
      s.current_period_end,
      COALESCE(p.before_paywall, false) as is_grandfathered
    FROM profiles p
    FULL OUTER JOIN subscriptions s ON p.id = s.user_id
    WHERE
      -- Has active subscription
      (
        s.status IN ('active', 'trialing', 'grace')
        AND (s.current_period_end IS NULL OR s.current_period_end > now())
      )
      -- OR is grandfathered
      OR p.before_paywall = true
    ORDER BY COALESCE(s.user_id, p.id), COALESCE(s.current_period_end, '2099-12-31'::timestamptz) DESC
  ) sub
  ORDER BY COALESCE(sub.current_period_end, '2099-12-31'::timestamptz) DESC;
END;
$$;

COMMENT ON FUNCTION admin_get_subscribers IS 'Returns users with active subscriptions or grandfathered status. Uses DISTINCT ON to avoid ORDER BY errors.';
