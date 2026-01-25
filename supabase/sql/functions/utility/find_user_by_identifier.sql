-- Efficient user lookup by email (case-insensitive)
-- Returns user ID or null
-- Used by sharing API to find users when adding friends
CREATE OR REPLACE FUNCTION public.find_user_by_email(search_email text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT id FROM auth.users
  WHERE lower(email) = lower(search_email)
  LIMIT 1;
$$;

-- Efficient user lookup by phone (normalized E.164 format)
-- Returns user ID or null
-- Phone should be normalized to format: country_code + number (e.g., "4712345678")
CREATE OR REPLACE FUNCTION public.find_user_by_phone(search_phone text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT id FROM auth.users
  WHERE phone = search_phone
  LIMIT 1;
$$;

-- Grant execute to service role only (these should only be called server-side)
REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM anon;
REVOKE ALL ON FUNCTION public.find_user_by_email(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_email(text) TO service_role;

REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM anon;
REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO service_role;
