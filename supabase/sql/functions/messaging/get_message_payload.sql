-- Function: get_message_payload
-- Description: Returns the canonical payload for a single message with ordered attachment metadata

CREATE OR REPLACE FUNCTION public.get_message_payload(p_message_id uuid)
RETURNS TABLE (
  id uuid,
  thread_id uuid,
  sender_user_id uuid,
  message_type text,
  body text,
  client_id uuid,
  reply_to_message_id uuid,
  created_at timestamptz,
  edited_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb,
  attachments jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    m.id,
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.body,
    m.client_id,
    m.reply_to_message_id,
    m.created_at,
    m.edited_at,
    m.deleted_at,
    m.metadata,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', ma.id,
            'attachment_index', ma.attachment_index,
            'kind', ma.kind,
            'storage_bucket', ma.storage_bucket,
            'storage_path', ma.storage_path,
            'mime_type', ma.mime_type,
            'byte_size', ma.byte_size,
            'width', ma.width,
            'height', ma.height,
            'created_at', ma.created_at
          )
          ORDER BY ma.attachment_index ASC
        )
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    ) AS attachments
  FROM public.messages m
  WHERE m.id = p_message_id
    AND public.can_access_thread(m.thread_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_payload(uuid) TO authenticated;
