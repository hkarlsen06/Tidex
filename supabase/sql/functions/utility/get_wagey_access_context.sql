-- Load the profile + latest subscription row used for Wagey entitlement checks in one round trip.

CREATE OR REPLACE FUNCTION public.get_wagey_access_context(p_user_id uuid)
RETURNS TABLE (
  before_paywall boolean,
  wagey_invocations jsonb,
  status text,
  product_id text,
  current_period_end text,
  price_id text,
  provider text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    p.before_paywall,
    p.wagey_invocations,
    s.status,
    s.product_id,
    s.current_period_end::text,
    s.price_id,
    s.provider::text
  FROM public.profiles p
  LEFT JOIN LATERAL (
    SELECT
      sub.status,
      sub.product_id,
      sub.current_period_end,
      sub.price_id,
      sub.provider
    FROM public.subscriptions sub
    WHERE sub.user_id = p.id
    ORDER BY sub.current_period_end DESC NULLS LAST, sub.id DESC
    LIMIT 1
  ) AS s ON true
  WHERE p.id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.get_wagey_access_context(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_wagey_access_context(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_wagey_access_context(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_wagey_access_context(uuid) TO service_role;
