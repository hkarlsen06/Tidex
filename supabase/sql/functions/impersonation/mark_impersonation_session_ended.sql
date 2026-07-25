CREATE OR REPLACE FUNCTION public.mark_impersonation_session_ended(
  p_session_id uuid,
  p_ended_by_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_row_count integer;
BEGIN
  UPDATE internal.impersonation_sessions
  SET
    ended_at = now(),
    ended_by_admin_user_id = p_ended_by_user_id
  WHERE id = p_session_id
    AND ended_at IS NULL;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  RETURN v_row_count > 0;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_impersonation_session_ended(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_impersonation_session_ended(uuid, uuid)
  TO service_role;
