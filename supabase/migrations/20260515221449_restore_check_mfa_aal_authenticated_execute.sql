-- check_mfa_aal() is referenced by restrictive RLS policies on user-owned
-- tables. Postgres requires the querying role to have EXECUTE on functions
-- referenced by policies, even when the function is SECURITY DEFINER.
--
-- Keep it unavailable to anonymous clients, but allow signed-in users to pass
-- through RLS policy evaluation.
REVOKE EXECUTE ON FUNCTION public.check_mfa_aal() FROM anon;
GRANT EXECUTE ON FUNCTION public.check_mfa_aal() TO authenticated;
