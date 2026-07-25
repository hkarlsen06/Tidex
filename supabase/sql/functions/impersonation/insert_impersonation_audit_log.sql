CREATE OR REPLACE FUNCTION public.insert_impersonation_audit_log(
  p_session_id uuid,
  p_admin_user_id uuid,
  p_target_user_id uuid,
  p_action text,
  p_reason text DEFAULT NULL,
  p_admin_ip text DEFAULT NULL,
  p_admin_user_agent text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_log_id uuid;
BEGIN
  INSERT INTO internal.impersonation_audit_log (
    session_id,
    admin_user_id,
    target_user_id,
    action,
    reason,
    admin_ip,
    admin_user_agent,
    metadata
  ) VALUES (
    p_session_id,
    p_admin_user_id,
    p_target_user_id,
    p_action,
    p_reason,
    p_admin_ip,
    p_admin_user_agent,
    p_metadata
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.insert_impersonation_audit_log(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insert_impersonation_audit_log(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) TO service_role;
