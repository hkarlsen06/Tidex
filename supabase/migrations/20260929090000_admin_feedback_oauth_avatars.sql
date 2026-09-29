-- Admin console: fall back to the sign-in provider's avatar in the feedback list.

CREATE OR REPLACE FUNCTION public.admin_get_feedback_api(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH base AS (
      SELECT
        f.id,
        f.user_id,
        f.message,
        f.user_email,
        COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') AS user_name,
        -- Same fallback as counterpart avatars in get_thread_summary.
        COALESCE(
          us.profile_picture_url,
          u.raw_user_meta_data->>'avatar_url',
          u.raw_user_meta_data->>'picture'
        ) AS user_profile_picture,
        f.created_at,
        f.response,
        f.responded_at,
        f.responded_by
      FROM public.feedback f
      LEFT JOIN auth.users u ON u.id = f.user_id
      LEFT JOIN public.user_settings us ON us.user_id = f.user_id
      ORDER BY f.created_at DESC
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
      OFFSET GREATEST(COALESCE(p_offset, 0), 0)
    ),
    counted AS (
      SELECT COUNT(*)::integer AS total FROM public.feedback
    )
    SELECT jsonb_build_object(
      'feedback', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'userId', user_id,
            'message', message,
            'userEmail', user_email,
            'userName', user_name,
            'userProfilePicture', user_profile_picture,
            'createdAt', created_at,
            'response', response,
            'respondedAt', responded_at,
            'respondedBy', responded_by
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      ),
      'total', (SELECT total FROM counted)
    )
    FROM base
  );
END;
$function$;
