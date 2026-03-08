-- Function: can_read_message_attachment_object
-- Description: Validates whether the authenticated user may read a private message attachment object path

CREATE OR REPLACE FUNCTION public.can_read_message_attachment_object(p_path text, p_owner_id text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_path IS NULL OR p_path = '' THEN
    RETURN false;
  END IF;

  IF p_owner_id = v_uid::text THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.message_attachments ma
    JOIN public.messages m
      ON m.id = ma.message_id
    WHERE ma.storage_bucket = 'message-attachments'
      AND ma.storage_path = p_path
      AND public.can_access_thread(m.thread_id)
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) TO authenticated;
