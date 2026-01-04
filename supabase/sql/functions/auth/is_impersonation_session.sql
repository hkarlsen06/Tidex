-- Check if current authenticated user has an active impersonation session
-- This allows AAL1 sessions that are part of impersonation to bypass AAL2 checks
-- Used by check_mfa_aal() to allow admin impersonation of MFA-enabled users
CREATE OR REPLACE FUNCTION public.is_impersonation_session()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.impersonation_sessions
    WHERE target_user_id = auth.uid()
      AND ended_at IS NULL
      AND expires_at > now()
  );
$$;
