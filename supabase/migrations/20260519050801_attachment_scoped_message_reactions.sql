-- Add optional attachment-scoped reactions while preserving message-level reactions.

ALTER TABLE public.message_reactions
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS attachment_id uuid;

UPDATE public.message_reactions
SET id = gen_random_uuid()
WHERE id IS NULL;

ALTER TABLE public.message_reactions
  ALTER COLUMN id SET NOT NULL;

ALTER TABLE public.message_reactions
  DROP CONSTRAINT IF EXISTS message_reactions_pkey;

ALTER TABLE public.message_reactions
  ADD CONSTRAINT message_reactions_pkey PRIMARY KEY (id);

ALTER TABLE public.message_reactions
  DROP CONSTRAINT IF EXISTS message_reactions_attachment_id_fkey;

ALTER TABLE public.message_reactions
  ADD CONSTRAINT message_reactions_attachment_id_fkey
  FOREIGN KEY (attachment_id)
  REFERENCES public.message_attachments(id)
  ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS message_reactions_message_level_unique_idx
  ON public.message_reactions (message_id, user_id, emoji)
  WHERE attachment_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS message_reactions_attachment_level_unique_idx
  ON public.message_reactions (attachment_id, user_id, emoji)
  WHERE attachment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS message_reactions_attachment_id_idx
  ON public.message_reactions (attachment_id)
  WHERE attachment_id IS NOT NULL;

DROP FUNCTION IF EXISTS public.toggle_message_reaction(uuid, text);

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
            'created_at', ma.created_at,
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
            AND mr.attachment_id IS NULL
          GROUP BY mr.emoji
        ) AS reaction_summary
      ),
      '[]'::jsonb
    )
  )
  FROM public.messages m
  WHERE m.id = p_message_id;
$function$;

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
    'attachments', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_set(
            attachment.value,
            '{reactions}',
            COALESCE(
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
                  FROM jsonb_to_recordset(COALESCE(attachment.value->'reactions', '[]'::jsonb))
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
          )
          ORDER BY attachment.ordinality
        )
        FROM jsonb_array_elements(COALESCE(p_payload->'attachments', '[]'::jsonb))
          WITH ORDINALITY AS attachment(value, ordinality)
      ),
      '[]'::jsonb
    ),
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

CREATE OR REPLACE FUNCTION public.toggle_message_reaction(
  p_message_id uuid,
  p_emoji text,
  p_attachment_id uuid DEFAULT NULL
)
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
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_emoji text := btrim(COALESCE(p_emoji, ''));
  v_attachment_thread_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_emoji = '' OR char_length(v_emoji) > 16 THEN
    RAISE EXCEPTION 'Reaction emoji is invalid';
  END IF;

  SELECT m.thread_id
  INTO v_thread_id
  FROM public.messages m
  WHERE m.id = p_message_id
    AND m.deleted_at IS NULL
  LIMIT 1;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF NOT public.can_post_to_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread is read only';
  END IF;

  IF p_attachment_id IS NOT NULL THEN
    SELECT m.thread_id
    INTO v_attachment_thread_id
    FROM public.message_attachments ma
    INNER JOIN public.messages m
      ON m.id = ma.message_id
    WHERE ma.id = p_attachment_id
      AND ma.message_id = p_message_id
      AND m.deleted_at IS NULL
    LIMIT 1;

    IF v_attachment_thread_id IS NULL OR v_attachment_thread_id <> v_thread_id THEN
      RAISE EXCEPTION 'Attachment not found';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji
      AND mr.attachment_id IS NOT DISTINCT FROM p_attachment_id
  ) THEN
    PERFORM set_config('tidex.messaging_v2_emit_message_reaction', 'true', true);

    DELETE FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji
      AND mr.attachment_id IS NOT DISTINCT FROM p_attachment_id;
  ELSE
    PERFORM set_config('tidex.messaging_v2_emit_message_reaction', 'true', true);

    INSERT INTO public.message_reactions (
      thread_id,
      message_id,
      attachment_id,
      user_id,
      emoji
    )
    VALUES (
      v_thread_id,
      p_message_id,
      p_attachment_id,
      v_uid,
      v_emoji
    );
  END IF;

  RETURN QUERY
  SELECT payload.*
  FROM public.get_message_payload(p_message_id) AS payload;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text, uuid) TO authenticated;
