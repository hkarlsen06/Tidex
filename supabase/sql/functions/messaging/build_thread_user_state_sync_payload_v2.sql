-- Function: build_thread_user_state_sync_payload_v2
-- Description: Builds the caller-private thread state payload used by messaging sync V2

CREATE OR REPLACE FUNCTION internal.build_thread_user_state_sync_payload_v2(
  p_thread_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'thread_id', t.id,
    'user_id', p_user_id,
    'last_read_message_id', tus.last_read_message_id,
    'last_read_at', tus.last_read_at,
    'unread_count', COALESCE(tus.unread_count, 0),
    'muted', COALESCE(tus.muted, false),
    'archived_at', tus.archived_at,
    'updated_at', COALESCE(tus.updated_at, t.created_at)
  )
  FROM public.threads t
  LEFT JOIN public.thread_user_state tus
    ON tus.thread_id = t.id
   AND tus.user_id = p_user_id
  WHERE t.id = p_thread_id
    AND internal.can_access_thread_as_user(p_thread_id, p_user_id);
$function$;
