-- Function: get_thread_summary
-- Description: Returns the canonical summary payload for a thread visible to the authenticated user

CREATE OR REPLACE FUNCTION public.get_thread_summary(p_thread_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH auth_context AS (
    SELECT auth.uid() AS user_id
  ),
  base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      t.last_message_id,
      t.last_message_sender_id,
      t.last_message_at,
      t.created_at,
      tus.muted,
      dt.user_low_id,
      dt.user_high_id,
      cu.user_id
    FROM public.threads t
    JOIN auth_context cu
      ON cu.user_id IS NOT NULL
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = cu.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = cu.user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  ),
  read_marker AS (
    SELECT
      tus.thread_id,
      rm.created_at AS last_read_created_at,
      rm.id AS last_read_message_id
    FROM public.thread_user_state tus
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    JOIN auth_context cu
      ON cu.user_id = tus.user_id
    WHERE tus.thread_id = p_thread_id
  )
  SELECT
    c.id AS thread_id,
    c.kind,
    c.title,
    c.avatar_url,
    c.metadata,
    c.counterpart_user_id,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END AS counterpart_display_name,
    us.profile_picture_url AS counterpart_profile_picture_url,
    CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END AS counterpart_oauth_avatar_url,
    c.last_message_id,
    c.last_message_sender_id,
    c.last_message_at,
    lm.body AS last_message_body,
    EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS last_message_has_image,
    COALESCE(
      (
        SELECT count(*)
        FROM public.messages um
        LEFT JOIN read_marker rm
          ON rm.thread_id = um.thread_id
        WHERE um.thread_id = c.id
          AND um.deleted_at IS NULL
          AND um.sender_user_id <> c.user_id
          AND (
            rm.last_read_message_id IS NULL
            OR (um.created_at, um.id) > (rm.last_read_created_at, rm.last_read_message_id)
          )
      ),
      0
    ) AS unread_count,
    COALESCE(c.muted, false) AS muted,
    c.created_at
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;
