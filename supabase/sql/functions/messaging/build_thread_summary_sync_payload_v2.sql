-- Function: build_thread_summary_sync_payload_v2
-- Description: Builds the caller-specific thread-list summary payload used by messaging sync V2

CREATE OR REPLACE FUNCTION internal.build_thread_summary_sync_payload_v2(
  p_thread_id uuid,
  p_viewer_user_id uuid,
  p_use_last_message_override boolean DEFAULT false,
  p_last_message_id uuid DEFAULT NULL,
  p_last_message_sender_id uuid DEFAULT NULL,
  p_last_message_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      CASE
        WHEN p_use_last_message_override THEN p_last_message_id
        ELSE t.last_message_id
      END AS last_message_id,
      CASE
        WHEN p_use_last_message_override THEN p_last_message_sender_id
        ELSE t.last_message_sender_id
      END AS last_message_sender_id,
      CASE
        WHEN p_use_last_message_override THEN COALESCE(p_last_message_at, t.created_at)
        ELSE t.last_message_at
      END AS last_message_at,
      t.created_at,
      tus.muted,
      tus.unread_count,
      dt.user_low_id,
      dt.user_high_id,
      p_viewer_user_id AS viewer_user_id
    FROM public.threads t
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = p_viewer_user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = p_viewer_user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.viewer_user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.viewer_user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  )
  SELECT jsonb_build_object(
    'thread_id', c.id,
    'kind', c.kind,
    'title', c.title,
    'avatar_url', c.avatar_url,
    'metadata', c.metadata,
    'counterpart_user_id', c.counterpart_user_id,
    'counterpart_display_name', CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END,
    'counterpart_profile_picture_url', us.profile_picture_url,
    'counterpart_oauth_avatar_url', CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END,
    'last_message_id', c.last_message_id,
    'last_message_sender_id', c.last_message_sender_id,
    'last_message_at', c.last_message_at,
    'last_message_body', lm.body,
    'last_message_preview_kind', public.message_preview_kind(
      lm.body,
      lm.metadata,
      COALESCE(last_message_media.has_image, false)
    ),
    'last_message_has_image', COALESCE(last_message_media.has_image, false),
    'unread_count', COALESCE(c.unread_count, 0)::bigint,
    'muted', COALESCE(c.muted, false),
    'created_at', c.created_at
  )
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS has_image
  ) AS last_message_media
    ON true
  WHERE c.counterpart_user_id IS NULL
     OR NOT internal.is_user_pair_abuse_blocked_for_user(p_viewer_user_id, c.counterpart_user_id);
$function$;

