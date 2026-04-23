-- Harden app account token RPCs so app clients can only create/read their own
-- token and backend-only token lookup remains restricted to the service role.

CREATE OR REPLACE FUNCTION public.get_or_create_app_account_token(p_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_token uuid;
BEGIN
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not authorized'
      USING ERRCODE = '42501';
  END IF;

  -- First try to get existing token
  SELECT token INTO v_token
  FROM internal.app_account_tokens
  WHERE user_id = p_user_id;

  -- If not found, create one
  IF v_token IS NULL THEN
    INSERT INTO internal.app_account_tokens (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
    RETURNING token INTO v_token;
  END IF;

  RETURN v_token;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_app_account_token(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_or_create_app_account_token(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_or_create_app_account_token(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_app_account_token(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_id_by_app_account_token(p_token uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT user_id FROM internal.app_account_tokens WHERE token = p_token;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_user_id_by_app_account_token(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_id_by_app_account_token(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_user_id_by_app_account_token(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_id_by_app_account_token(uuid) TO service_role;
