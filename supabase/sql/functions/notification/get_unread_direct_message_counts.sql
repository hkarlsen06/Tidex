-- Function: get_unread_direct_message_counts
-- Description: Returns unread direct-message counts for many users in one query.
-- Schema: internal
-- Used by: send-push-notifications edge function

CREATE OR REPLACE FUNCTION internal.get_unread_direct_message_counts(p_user_ids uuid[])
RETURNS TABLE (
  user_id uuid,
  unread_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $$
  WITH requested_users AS (
    SELECT DISTINCT requested.user_id
    FROM unnest(COALESCE(p_user_ids, ARRAY[]::uuid[])) AS requested(user_id)
    WHERE requested.user_id IS NOT NULL
  ),
  unread_per_thread AS (
    SELECT
      requested.user_id,
      t.id,
      COUNT(*)::integer AS unread_count
    FROM requested_users requested
    INNER JOIN public.threads t
      ON t.kind = 'direct'
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    INNER JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = requested.user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = requested.user_id
    LEFT JOIN public.messages rm
      ON rm.id = tus.last_read_message_id
    INNER JOIN public.messages m
      ON m.thread_id = t.id
     AND m.sender_user_id <> requested.user_id
    WHERE (
      dt.thread_id IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM public.shift_shares ss
        WHERE (
          (ss.owner_id = requested.user_id AND ss.viewer_id = CASE
            WHEN dt.user_low_id = requested.user_id THEN dt.user_high_id
            WHEN dt.user_high_id = requested.user_id THEN dt.user_low_id
            ELSE NULL
          END)
          OR
          (ss.owner_id = CASE
            WHEN dt.user_low_id = requested.user_id THEN dt.user_high_id
            WHEN dt.user_high_id = requested.user_id THEN dt.user_low_id
            ELSE NULL
          END AND ss.viewer_id = requested.user_id)
        )
          AND ss.blocked_by_user_id IS NOT NULL
      )
    )
      AND m.deleted_at IS NULL
      AND (
        tus.last_read_message_id IS NULL
        OR rm.id IS NULL
        OR (m.created_at, m.id) > (rm.created_at, rm.id)
      )
    GROUP BY requested.user_id, t.id
  )
  SELECT
    requested.user_id,
    COALESCE(SUM(unread_per_thread.unread_count), 0)::integer AS unread_count
  FROM requested_users requested
  LEFT JOIN unread_per_thread
    ON unread_per_thread.user_id = requested.user_id
  GROUP BY requested.user_id;
$$;

GRANT EXECUTE ON FUNCTION internal.get_unread_direct_message_counts(uuid[]) TO service_role;
