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
  attachments jsonb,
  reactions jsonb
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
            'created_at', ma.created_at,
            'reactions', COALESCE(
              (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    'emoji', reaction_summary.emoji,
                    'count', reaction_summary.reaction_count,
                    'viewer_has_reacted', reaction_summary.viewer_has_reacted
                  )
                  ORDER BY
                    reaction_summary.viewer_has_reacted DESC,
                    reaction_summary.reaction_count DESC,
                    reaction_summary.first_created_at ASC,
                    reaction_summary.emoji ASC
                )
                FROM (
                  SELECT
                    mr.emoji,
                    COUNT(*)::integer AS reaction_count,
                    BOOL_OR(mr.user_id = auth.uid()) AS viewer_has_reacted,
                    MIN(mr.created_at) AS first_created_at
                  FROM public.message_reactions mr
                  WHERE mr.attachment_id = ma.id
                  GROUP BY mr.emoji
                ) AS reaction_summary
              ),
              '[]'::jsonb
            )
          )
          ORDER BY ma.attachment_index ASC
        )
        FROM public.message_attachments ma
        WHERE ma.message_id = m.id
      ),
      '[]'::jsonb
    ) AS attachments,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'emoji', reaction_summary.emoji,
            'count', reaction_summary.reaction_count,
            'viewer_has_reacted', reaction_summary.viewer_has_reacted
          )
          ORDER BY
            reaction_summary.viewer_has_reacted DESC,
            reaction_summary.reaction_count DESC,
            reaction_summary.first_created_at ASC,
            reaction_summary.emoji ASC
        )
        FROM (
          SELECT
            mr.emoji,
            COUNT(*)::integer AS reaction_count,
            BOOL_OR(mr.user_id = auth.uid()) AS viewer_has_reacted,
            MIN(mr.created_at) AS first_created_at
          FROM public.message_reactions mr
          WHERE mr.message_id = m.id
            AND mr.attachment_id IS NULL
          GROUP BY mr.emoji
        ) AS reaction_summary
      ),
      '[]'::jsonb
    ) AS reactions
  FROM public.messages m
  WHERE m.id = p_message_id
    AND public.can_access_thread(m.thread_id);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_payload(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_payload(uuid) TO authenticated;
