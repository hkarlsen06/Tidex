-- Function: build_direct_thread_counterpart_sync_payload_v2
-- Description: Builds the direct-thread counterpart presence payload for messaging sync V2

CREATE OR REPLACE FUNCTION internal.build_direct_thread_counterpart_sync_payload_v2(
  p_thread_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH counterpart AS (
    SELECT
      CASE
        WHEN dt.user_low_id = p_user_id THEN dt.user_high_id
        WHEN dt.user_high_id = p_user_id THEN dt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM public.direct_threads dt
    WHERE dt.thread_id = p_thread_id
  )
  SELECT jsonb_build_object(
    'user_id', c.counterpart_user_id,
    'display_name', COALESCE(
      au.raw_user_meta_data->>'full_name',
      au.raw_user_meta_data->>'name',
      au.email,
      'Someone'
    ),
    'profile_picture_url', us.profile_picture_url,
    'oauth_avatar_url', COALESCE(
      au.raw_user_meta_data->>'avatar_url',
      au.raw_user_meta_data->>'picture'
    )
  )
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  WHERE c.counterpart_user_id IS NOT NULL
    AND internal.can_access_thread_as_user(p_thread_id, p_user_id);
$function$;

