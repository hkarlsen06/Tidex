-- Add initial-month hints for shared shift navigation so the iOS app can open
-- old shared history directly instead of always landing on the current month.

DROP FUNCTION IF EXISTS public.get_my_sharers();

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
  hidden boolean,
  has_shared_calendar_content boolean,
  latest_shared_shift_date date,
  has_recurring_shared_shifts boolean
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
    COALESCE(ss.hidden, false) AS hidden,
    (
      latest_shift.latest_shared_shift_date IS NOT NULL
      OR COALESCE(recurring_shifts.has_recurring_shared_shifts, false)
    ) AS has_shared_calendar_content,
    latest_shift.latest_shared_shift_date,
    COALESCE(recurring_shifts.has_recurring_shared_shifts, false) AS has_recurring_shared_shifts
  FROM public.shift_shares ss
  LEFT JOIN auth.users au
    ON au.id = ss.owner_id
  LEFT JOIN public.user_settings us
    ON us.user_id = ss.owner_id
  LEFT JOIN LATERAL (
    SELECT MAX(s.shift_date) AS latest_shared_shift_date
    FROM public.user_shifts s
    WHERE s.user_id = ss.owner_id
      AND s.deleted_at IS NULL
  ) latest_shift
    ON TRUE
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM public.recurring_shifts r
      WHERE r.user_id = ss.owner_id
        AND r.deleted_at IS NULL
    ) AS has_recurring_shared_shifts
  ) recurring_shifts
    ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND ss.viewer_id = auth.uid()
    AND ss.blocked_by_user_id IS NULL
  ORDER BY ss.created_at DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM public;
REVOKE EXECUTE ON FUNCTION public.get_my_sharers() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sharers() TO authenticated;
