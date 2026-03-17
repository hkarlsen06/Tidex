-- Function: update_thread_unread_counts_on_message_soft_delete
-- Description: Decrements unread counts for active recipients when an unread message is soft deleted

CREATE OR REPLACE FUNCTION public.update_thread_unread_counts_on_message_soft_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.thread_user_state tus
  SET
    unread_count = GREATEST(COALESCE(tus.unread_count, 0) - 1, 0),
    updated_at = now()
  FROM public.thread_memberships tm
  WHERE tus.thread_id = NEW.thread_id
    AND tus.user_id = tm.user_id
    AND tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND tm.user_id <> NEW.sender_user_id
    AND (
      tus.last_read_message_id IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM public.messages rm
        WHERE rm.id = tus.last_read_message_id
          AND (OLD.created_at, OLD.id) <= (rm.created_at, rm.id)
      )
    );

  RETURN NEW;
END;
$function$;
