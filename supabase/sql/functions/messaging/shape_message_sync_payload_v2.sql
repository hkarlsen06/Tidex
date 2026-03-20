-- Function: shape_message_sync_payload_v2
-- Description: Shapes a viewer-independent V2 message payload into caller-facing JSON

CREATE OR REPLACE FUNCTION internal.shape_message_sync_payload_v2(
  p_payload jsonb,
  p_viewer_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'id', p_payload->'id',
    'thread_id', p_payload->'thread_id',
    'sender_user_id', p_payload->'sender_user_id',
    'message_type', p_payload->'message_type',
    'body', p_payload->'body',
    'client_id', p_payload->'client_id',
    'reply_to_message_id', p_payload->'reply_to_message_id',
    'created_at', p_payload->'created_at',
    'edited_at', p_payload->'edited_at',
    'deleted_at', p_payload->'deleted_at',
    'metadata', COALESCE(p_payload->'metadata', '{}'::jsonb),
    'attachments', COALESCE(p_payload->'attachments', '[]'::jsonb),
    'reactions', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'emoji', reaction.emoji,
            'count', reaction.reaction_count,
            'viewer_has_reacted', reaction.viewer_has_reacted
          )
          ORDER BY
            reaction.viewer_has_reacted DESC,
            reaction.reaction_count DESC,
            reaction.first_created_at ASC,
            reaction.emoji ASC
        )
        FROM (
          SELECT
            r.emoji,
            COALESCE(r.reaction_count, 0) AS reaction_count,
            EXISTS (
              SELECT 1
              FROM jsonb_array_elements_text(COALESCE(r.reactor_user_ids, '[]'::jsonb)) AS reactor(user_id)
              WHERE reactor.user_id::uuid = p_viewer_user_id
            ) AS viewer_has_reacted,
            r.first_created_at
          FROM jsonb_to_recordset(COALESCE(p_payload->'reactions', '[]'::jsonb))
            AS r(
              emoji text,
              reaction_count integer,
              reactor_user_ids jsonb,
              first_created_at timestamptz
            )
        ) AS reaction
      ),
      '[]'::jsonb
    )
  );
$function$;

