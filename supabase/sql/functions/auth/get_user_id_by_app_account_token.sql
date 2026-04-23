-- Function: get_user_id_by_app_account_token
-- Description: Looks up user ID by app account token
-- Used by: Native app authentication flow

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
