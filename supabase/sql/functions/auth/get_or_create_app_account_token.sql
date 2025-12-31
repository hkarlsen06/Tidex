-- Function: get_or_create_app_account_token
-- Description: Gets existing or creates new app account token for a user (used for native app auth)
-- Used by: Native app authentication flow

CREATE OR REPLACE FUNCTION public.get_or_create_app_account_token(p_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
