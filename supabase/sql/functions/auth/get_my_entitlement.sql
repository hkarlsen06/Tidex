-- Function: get_my_entitlement
-- Description: Returns the entitlement status for the CURRENT authenticated user
-- Security: SECURITY DEFINER ensures auth.uid() is trusted, not user-supplied
-- Used by: iOS app, web app (client-safe entitlement queries)
--
-- NOTE: RETURNS TABLE (not jsonb) for clean Supabase client decoding
-- This allows direct decoding to Swift structs without wrapper handling
--
-- SECURITY: This function is the ONLY safe way for clients to query entitlements.
-- Direct SELECT on user_entitlements is revoked from anon/authenticated roles.
-- The auth.uid() call happens server-side and cannot be spoofed by clients.

CREATE OR REPLACE FUNCTION public.get_my_entitlement()
RETURNS TABLE (
  user_id uuid,
  tier text,
  is_entitled boolean,
  is_grandfathered boolean,
  has_active_subscription boolean,
  active_provider text,
  active_product_id text,
  subscription_ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    ue.user_id,
    ue.tier,
    ue.is_entitled,
    ue.is_grandfathered,
    ue.has_active_subscription,
    ue.active_provider,
    ue.active_product_id,
    ue.subscription_ends_at
  FROM public.user_entitlements ue
  WHERE ue.user_id = auth.uid();
$function$;

-- Grant execute to authenticated users only
GRANT EXECUTE ON FUNCTION public.get_my_entitlement() TO authenticated;

-- Revoke from public and anon
REVOKE EXECUTE ON FUNCTION public.get_my_entitlement() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_entitlement() FROM anon;
