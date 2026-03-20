-- Function: build_message_sync_payload_v2
-- Description: Builds the viewer-independent message payload stored in messaging sync V2 thread events

CREATE OR REPLACE FUNCTION internal.build_message_sync_payload_v2(p_message_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'id', m.id,
    'thread_id', m.thread_id,
    'sender_user_id', m.sender_user_id,
    'message_type', m.message_type,
    'body', m.body,
    'client_id', m.client_id,
    'reply_to_message_id', m.reply_to_message_id,
    'created_at', m.created_at,
    'edited_at', m.edited_at,
    'deleted_at', m.deleted_at,
    'metadata', m.metadata,
    'attachments', COALESCE(
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
    ),
    'reactions', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'emoji', reaction_summary.emoji,
            'reaction_count', reaction_summary.reaction_count,
            'reactor_user_ids', reaction_summary.reactor_user_ids,
            'first_created_at', reaction_summary.first_created_at
          )
          ORDER BY
            reaction_summary.reaction_count DESC,
            reaction_summary.first_created_at ASC,
            reaction_summary.emoji ASC
        )
        FROM (
          SELECT
            mr.emoji,
            COUNT(*)::integer AS reaction_count,
            jsonb_agg(mr.user_id ORDER BY mr.created_at ASC, mr.user_id ASC) AS reactor_user_ids,
            MIN(mr.created_at) AS first_created_at
          FROM public.message_reactions mr
          WHERE mr.message_id = m.id
          GROUP BY mr.emoji
        ) AS reaction_summary
      ),
      '[]'::jsonb
    )
  )
  FROM public.messages m
  WHERE m.id = p_message_id;
$function$;
