-- Function: update_thread_unread_counts_on_message_insert
-- Description: Increments unread counts for every other active member when a new message is inserted

CREATE OR REPLACE FUNCTION public.update_thread_unread_counts_on_message_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    unread_count,
    updated_at
  )
  SELECT
    NEW.thread_id,
    tm.user_id,
    1,
    now()
  FROM public.thread_memberships tm
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND tm.user_id <> NEW.sender_user_id
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    unread_count = COALESCE(thread_user_state.unread_count, 0) + 1,
    updated_at = now();

  RETURN NEW;
END;
$function$;
