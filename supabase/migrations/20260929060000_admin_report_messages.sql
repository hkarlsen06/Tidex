-- Admin console: the conversation around a report, in the same payload shape as list_thread_messages
-- so the app can render it with the chat bubbles. Includes deleted messages.

CREATE OR REPLACE FUNCTION public.admin_get_report_messages_api(
  p_report_id uuid,
  p_context integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_report public.abuse_reports%ROWTYPE;
  v_anchor_at timestamptz;
  v_anchor_id uuid;
  v_context integer := LEAST(GREATEST(COALESCE(p_context, 10), 1), 50);
BEGIN
  PERFORM public.assert_is_admin();

  SELECT * INTO v_report FROM public.abuse_reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('messages', '[]'::jsonb);
  END IF;

  SELECT created_at, id INTO v_anchor_at, v_anchor_id
  FROM public.messages
  WHERE id = v_report.message_id;

  IF v_anchor_at IS NULL THEN
    v_anchor_at := v_report.created_at;
    -- The max uuid makes messages sent at the report time count as "before".
    v_anchor_id := 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid;
  END IF;

  RETURN (
    WITH window_rows AS (
      (
        SELECT m.*
        FROM public.messages m
        WHERE m.thread_id = v_report.thread_id
          AND (m.created_at, m.id) <= (v_anchor_at, v_anchor_id)
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT v_context + 1
      )
      UNION ALL
      (
        SELECT m.*
        FROM public.messages m
        WHERE m.thread_id = v_report.thread_id
          AND (m.created_at, m.id) > (v_anchor_at, v_anchor_id)
        ORDER BY m.created_at, m.id
        LIMIT v_context
      )
    )
    SELECT jsonb_build_object(
      -- Same fallback as counterpart avatars in get_thread_summary.
      'reportedAvatarUrl', (
        SELECT COALESCE(
          us.profile_picture_url,
          au.raw_user_meta_data->>'avatar_url',
          au.raw_user_meta_data->>'picture'
        )
        FROM auth.users au
        LEFT JOIN public.user_settings us ON us.user_id = au.id
        WHERE au.id = v_report.reported_user_id
      ),
      'messages', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', w.id,
            'thread_id', w.thread_id,
            'sender_user_id', w.sender_user_id,
            'message_type', w.message_type,
            'body', w.body,
            'client_id', w.client_id,
            'reply_to_message_id', w.reply_to_message_id,
            'created_at', w.created_at,
            'edited_at', w.edited_at,
            'deleted_at', w.deleted_at,
            'metadata', w.metadata,
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
                    'reactions', '[]'::jsonb
                  )
                  ORDER BY ma.attachment_index
                )
                FROM public.message_attachments ma
                WHERE ma.message_id = w.id
              ),
              '[]'::jsonb
            ),
            'reactions', COALESCE(
              (
                SELECT jsonb_agg(
                  jsonb_build_object('emoji', r.emoji, 'count', r.reaction_count, 'viewer_has_reacted', false)
                  ORDER BY r.reaction_count DESC, r.first_created_at, r.emoji
                )
                FROM (
                  SELECT mr.emoji, count(*)::integer AS reaction_count, min(mr.created_at) AS first_created_at
                  FROM public.message_reactions mr
                  WHERE mr.message_id = w.id AND mr.attachment_id IS NULL
                  GROUP BY mr.emoji
                ) r
              ),
              '[]'::jsonb
            )
          )
          ORDER BY w.created_at, w.id
        ),
        '[]'::jsonb
      )
    )
    FROM window_rows w
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_get_report_messages_api(uuid, integer) TO authenticated;

-- Admins may load images from reported threads so the report screen can show them.
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
      AND (
        public.can_access_thread(m.thread_id)
        OR (
          public.is_admin()
          AND EXISTS (SELECT 1 FROM public.abuse_reports ar WHERE ar.thread_id = m.thread_id)
        )
      )
  );
END;
$function$;
