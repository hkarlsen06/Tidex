CREATE TABLE public.message_reactions (
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id, emoji),
  CONSTRAINT message_reactions_emoji_valid CHECK (
    btrim(emoji) <> ''
    AND char_length(emoji) <= 16
  )
);

CREATE INDEX message_reactions_thread_id_message_id_idx
  ON public.message_reactions (thread_id, message_id);

CREATE INDEX message_reactions_message_id_created_at_idx
  ON public.message_reactions (message_id, created_at ASC);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view accessible message reactions" ON public.message_reactions;
CREATE POLICY "Members can view accessible message reactions"
ON public.message_reactions FOR SELECT TO authenticated
USING (public.can_access_thread(thread_id));

DROP FUNCTION IF EXISTS public.toggle_message_reaction(uuid, text);
DROP FUNCTION IF EXISTS public.list_thread_messages(uuid, integer, timestamptz, uuid);
DROP FUNCTION IF EXISTS public.get_message_payload(uuid);

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
            'created_at', ma.created_at
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

CREATE OR REPLACE FUNCTION public.list_thread_messages(
  p_thread_id uuid,
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_message_id uuid DEFAULT NULL
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
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF (p_before_created_at IS NULL) <> (p_before_message_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both created_at and message_id';
  END IF;

  RETURN QUERY
  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
      AND (
        p_before_created_at IS NULL
        OR (m.created_at, m.id) < (p_before_created_at, p_before_message_id)
      )
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
  )
  SELECT payload.*
  FROM selected_messages sm
  CROSS JOIN LATERAL public.get_message_payload(sm.id) AS payload
  ORDER BY payload.created_at ASC, payload.id ASC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamptz, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_message_reaction(
  p_message_id uuid,
  p_emoji text
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

  IF EXISTS (
    SELECT 1
    FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji
  ) THEN
    DELETE FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji;
  ELSE
    INSERT INTO public.message_reactions (
      thread_id,
      message_id,
      user_id,
      emoji
    )
    VALUES (
      v_thread_id,
      p_message_id,
      v_uid,
      v_emoji
    );
  END IF;

  RETURN QUERY
  SELECT payload.*
  FROM public.get_message_payload(p_message_id) AS payload;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'message_reactions'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
    END IF;
  END IF;
END $$;
