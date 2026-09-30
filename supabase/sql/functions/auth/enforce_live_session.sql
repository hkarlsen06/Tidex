-- Function: public.enforce_live_session
-- Description: PostgREST pre-request check (authenticator role setting
--              pgrst.db_pre_request). GoTrue access tokens stay valid until
--              they expire (JWT_EXP=3600), even after sign-out or after
--              internal.strip_unverified_email_login_on_oauth_link deletes the
--              session. This rejects a REST request with 401 when the token's
--              session_id no longer exists in auth.sessions or is past its
--              not_after (impersonation sessions set not_after).
--              Tokens without a session_id (anon, service_role, publishable
--              key) pass through unchanged.
-- Limits: Storage, Realtime and edge functions do not run this check.
-- Security: SECURITY DEFINER so the request role can read auth.sessions.
--           It is in public because anon and authenticated have no USAGE on
--           internal. Calling it as an RPC only checks the caller's own
--           session.

CREATE OR REPLACE FUNCTION public.enforce_live_session()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_session_id text := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id';
BEGIN
  IF v_session_id IS NULL THEN
    RETURN;
  END IF;

  IF v_session_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR NOT EXISTS (
      SELECT 1
      FROM auth.sessions s
      WHERE s.id = v_session_id::uuid
        AND (s.not_after IS NULL OR s.not_after > now())
    )
  THEN
    RAISE SQLSTATE 'PGRST'
      USING MESSAGE = '{"code":"session_not_found","message":"Session has ended. Sign in again."}',
            DETAIL = '{"status":401,"headers":{"WWW-Authenticate":"Bearer error=\"invalid_token\""}}';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.enforce_live_session() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enforce_live_session() TO anon, authenticated, service_role;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.enforce_live_session';
NOTIFY pgrst, 'reload config';
