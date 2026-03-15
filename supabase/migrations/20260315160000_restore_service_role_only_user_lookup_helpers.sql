-- Restore least-privilege grants for auth.users lookup helpers.
-- The previous migration accidentally exposed these SECURITY DEFINER
-- functions to all authenticated users.

REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM anon;
REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_email(text) TO service_role;

REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM anon;
REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO service_role;

REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM anon;
REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_users_by_ids(uuid[]) TO service_role;
