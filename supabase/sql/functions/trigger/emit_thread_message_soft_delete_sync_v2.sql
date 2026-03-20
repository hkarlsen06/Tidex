-- Function: emit_thread_message_soft_delete_sync_v2
-- Description: Emits V2 thread and inbox events for sanctioned message soft deletes

CREATE OR REPLACE FUNCTION internal.emit_thread_message_soft_delete_sync_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_last_message_id uuid;
  v_last_message_sender_id uuid;
  v_last_message_at timestamptz;
  v_thread_created_at timestamptz;
BEGIN
  IF current_setting('tidex.messaging_v2_emit_message_soft_delete', true) IS DISTINCT FROM 'true' THEN
    RETURN NEW;
  END IF;

  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT
    m.id,
    m.sender_user_id,
    m.created_at
  INTO
    v_last_message_id,
    v_last_message_sender_id,
    v_last_message_at
  FROM public.messages m
  WHERE m.thread_id = NEW.thread_id
    AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  SELECT t.created_at
  INTO v_thread_created_at
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  PERFORM internal.append_thread_event(
    NEW.thread_id,
    'message_deleted',
    'message',
    NEW.id,
    jsonb_build_object(
      'id', NEW.id,
      'thread_id', NEW.thread_id,
      'deleted_at', NEW.deleted_at
    ),
    NEW.sender_user_id
  );

  PERFORM internal.emit_thread_upserted_inbox_event_v2(
    tm.user_id,
    NEW.thread_id,
    true,
    v_last_message_id,
    v_last_message_sender_id,
    COALESCE(v_last_message_at, v_thread_created_at)
  )
  FROM public.thread_memberships tm
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND internal.can_access_thread_as_user(NEW.thread_id, tm.user_id);

  RETURN NEW;
END;
$function$;

