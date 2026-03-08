-- Function: list_my_threads
-- Description: Lists visible threads for the authenticated user with stable keyset pagination

CREATE OR REPLACE FUNCTION public.list_my_threads(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
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
  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    WHERE auth.uid() IS NOT NULL
      AND tm.user_id = auth.uid()
      AND tm.status = 'active'
      AND (
        p_before_last_message_at IS NULL
        OR p_before_thread_id IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
  )
  SELECT summary.*
  FROM visible_threads vt
  CROSS JOIN LATERAL public.get_thread_summary(vt.id) AS summary
  ORDER BY summary.last_message_at DESC, summary.thread_id DESC;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_my_threads(integer, timestamptz, uuid) TO authenticated;
