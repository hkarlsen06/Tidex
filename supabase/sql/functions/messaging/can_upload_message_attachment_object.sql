-- Function: can_upload_message_attachment_object
-- Description: Validates whether the authenticated user may upload a private message attachment object path

CREATE OR REPLACE FUNCTION public.can_upload_message_attachment_object(p_path text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_parts text[];
  v_thread_id uuid;
  v_path_user_id uuid;
BEGIN
  IF v_uid IS NULL OR p_path IS NULL OR p_path = '' THEN
    RETURN false;
  END IF;

  IF lower(p_path) !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|heic|heif|jpeg|jpg|png)$' THEN
    RETURN false;
  END IF;

  v_parts := string_to_array(p_path, '/');

  IF array_length(v_parts, 1) <> 3 THEN
    RETURN false;
  END IF;

  v_thread_id := v_parts[1]::uuid;
  v_path_user_id := v_parts[2]::uuid;

  IF v_path_user_id <> v_uid THEN
    RETURN false;
  END IF;

  RETURN public.can_post_to_thread(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) TO authenticated;
