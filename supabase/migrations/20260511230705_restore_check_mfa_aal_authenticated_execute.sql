-- check_mfa_aal() is called directly from restrictive RLS policies, so the
-- authenticated role must be allowed to execute it for protected tables.
GRANT EXECUTE ON FUNCTION public.check_mfa_aal() TO authenticated;
