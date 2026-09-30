-- User lookup by email (case-insensitive)
-- Returns user ID or null
-- Used by manage_sharing_action to find users when adding friends.
-- Matches only a user who proved the address: a verified email identity, or a
-- google/apple identity carrying that email. auth.identities.email is the
-- generated, indexed lower(identity_data ->> 'email').
CREATE OR REPLACE FUNCTION public.find_user_by_email(search_email text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT i.user_id
  FROM auth.identities i
  WHERE i.email = lower(search_email)
    AND (
      (i.provider = 'email' AND i.identity_data ->> 'email_verified' = 'true')
      OR i.provider IN ('google', 'apple')
    )
  ORDER BY i.created_at NULLS LAST, i.id
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

-- Efficiently fetch user data for a list of user IDs
-- Returns basic profile info needed for friends list
CREATE OR REPLACE FUNCTION public.get_users_by_ids(user_ids uuid[])
RETURNS TABLE (
  id uuid,
  email text,
  phone text,
  first_name text,
  oauth_avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    u.id,
    u.email,
    u.phone,
    COALESCE(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name'
    ) as first_name,
    u.raw_user_meta_data->>'avatar_url' as oauth_avatar_url
  FROM auth.users u
  WHERE u.id = ANY(user_ids);
$$;

-- Grant execute to service role only
REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM anon;
REVOKE ALL ON FUNCTION public.get_users_by_ids(uuid[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_users_by_ids(uuid[]) TO service_role;
