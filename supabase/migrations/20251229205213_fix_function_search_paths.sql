-- Fix function search paths for security
-- Set search_path to empty string to prevent search path injection attacks

CREATE OR REPLACE FUNCTION public.get_user_entitlement_status(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
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
  FROM public.user_entitlements
  WHERE user_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION public.has_shift_storage_entitlement(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT COALESCE(
    (SELECT is_entitled FROM public.user_entitlements WHERE user_id = p_user_id),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.get_or_create_app_account_token(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_token uuid;
BEGIN
  -- First try to get existing token
  SELECT token INTO v_token
  FROM public.app_account_tokens
  WHERE user_id = p_user_id;

  -- If not found, create one
  IF v_token IS NULL THEN
    INSERT INTO public.app_account_tokens (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
    RETURNING token INTO v_token;
  END IF;

  RETURN v_token;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_id_by_app_account_token(p_token uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT user_id FROM public.app_account_tokens WHERE token = p_token;
$$;
