-- Check if the current JWT belongs to the auth session minted for an active
-- impersonation (bound by bind_impersonation_auth_session)
-- This allows AAL1 sessions that are part of impersonation to bypass AAL2 checks
-- Used by check_mfa_aal() to allow admin impersonation of MFA-enabled users
CREATE OR REPLACE FUNCTION public.is_impersonation_session()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public', 'internal'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM internal.impersonation_sessions
    WHERE target_user_id = auth.uid()
      AND auth_session_id = NULLIF(auth.jwt() ->> 'session_id', '')::uuid
      AND ended_at IS NULL
      AND expires_at > now()
  );
$$;
