-- Impersonation used to bypass MFA for every session of the target user while
-- a record was active, and stopping it left the minted session usable.
-- The impersonation edge function now stores the minted auth session id.
-- is_impersonation_session() only matches that session, and ending the record
-- deletes it. auth.sessions.not_after stops refreshes after expires_at.
-- The last access token still works until its own exp (at most 1 hour).

ALTER TABLE internal.impersonation_sessions
  ADD COLUMN IF NOT EXISTS auth_session_id uuid;

CREATE OR REPLACE FUNCTION public.bind_impersonation_auth_session(
  p_session_id uuid,
  p_auth_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_target_user_id uuid;
  v_expires_at timestamptz;
BEGIN
  UPDATE internal.impersonation_sessions
  SET auth_session_id = p_auth_session_id
  WHERE id = p_session_id
    AND ended_at IS NULL
    AND auth_session_id IS NULL
  RETURNING target_user_id, expires_at
  INTO v_target_user_id, v_expires_at;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Impersonation session not found, ended, or already bound';
  END IF;

  UPDATE auth.sessions
  SET not_after = v_expires_at
  WHERE id = p_auth_session_id
    AND user_id = v_target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Auth session does not belong to the impersonated user';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.bind_impersonation_auth_session(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_impersonation_auth_session(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.is_impersonation_session()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM internal.impersonation_sessions
    WHERE target_user_id = auth.uid()
      AND auth_session_id = NULLIF(auth.jwt() ->> 'session_id', '')::uuid
      AND ended_at IS NULL
      AND expires_at > now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.mark_impersonation_session_ended(p_session_id uuid, p_ended_by_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_auth_session_id uuid;
  v_row_count integer;
BEGIN
  UPDATE internal.impersonation_sessions
  SET
    ended_at = now(),
    ended_by_admin_user_id = p_ended_by_user_id
  WHERE id = p_session_id
    AND ended_at IS NULL
  RETURNING auth_session_id INTO v_auth_session_id;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;

  -- Revoke the minted session. Refresh tokens cascade from auth.sessions.
  IF v_auth_session_id IS NOT NULL THEN
    DELETE FROM auth.sessions WHERE id = v_auth_session_id;
  END IF;

  RETURN v_row_count > 0;
END;
$function$;
