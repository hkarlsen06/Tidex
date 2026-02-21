-- Function: get_my_sharers
-- Description: Returns users who share their shifts with the authenticated viewer.
-- Security:
--   - Uses auth.uid() server-side (viewer cannot be spoofed).
--   - Filters to active (non-blocked) share rows only.
--   - SECURITY DEFINER is required to read auth.users metadata safely.

CREATE OR REPLACE FUNCTION public.get_my_sharers()
RETURNS TABLE (
  id uuid,
  email text,
  phone text,
  first_name text,
  profile_picture_url text,
  oauth_avatar_url text,
  shared_at timestamptz,
  show_earnings boolean,
  blocked boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    ss.owner_id AS id,
    au.email,
    au.phone,
    COALESCE(
      au.raw_user_meta_data->>'full_name',
      au.raw_user_meta_data->>'name'
    ) AS first_name,
    us.profile_picture_url,
    COALESCE(
      au.raw_user_meta_data->>'avatar_url',
      au.raw_user_meta_data->>'picture'
    ) AS oauth_avatar_url,
    ss.created_at AS shared_at,
    COALESCE(ss.show_earnings, false) AS show_earnings,
    COALESCE(ss.blocked, false) AS blocked
  FROM public.shift_shares ss
  LEFT JOIN auth.users au
    ON au.id = ss.owner_id
  LEFT JOIN public.user_settings us
    ON us.user_id = ss.owner_id
  WHERE auth.uid() IS NOT NULL
    AND ss.viewer_id = auth.uid()
    AND COALESCE(ss.blocked, false) = false
  ORDER BY ss.created_at DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharers() TO authenticated;
