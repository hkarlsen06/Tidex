-- Function: emit_thread_message_insert_sync_v2
-- Description: Emits V2 thread and inbox events for sanctioned message inserts

CREATE OR REPLACE FUNCTION internal.emit_thread_message_insert_sync_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
BEGIN
  IF current_setting('tidex.messaging_v2_emit_message_insert', true) IS DISTINCT FROM 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  PERFORM internal.append_thread_event(
    NEW.thread_id,
    'message_upserted',
    'message',
    NEW.id,
    internal.build_message_sync_payload_v2(NEW.id),
    NEW.sender_user_id
  );

  PERFORM internal.emit_thread_upserted_inbox_event_v2(
    tm.user_id,
    NEW.thread_id,
    true,
    NEW.id,
    NEW.sender_user_id,
    NEW.created_at
  )
  FROM public.thread_memberships tm
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND internal.can_access_thread_as_user(NEW.thread_id, tm.user_id);

  RETURN NEW;
END;
$function$;

