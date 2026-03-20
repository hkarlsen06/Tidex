ALTER TABLE public.threads
  ADD COLUMN IF NOT EXISTS state_version bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS retained_from_version bigint NOT NULL DEFAULT 0;

CREATE TABLE internal.thread_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  version bigint NOT NULL,
  event_type text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT thread_events_thread_id_version_key UNIQUE (thread_id, version)
);

CREATE INDEX thread_events_created_at_idx
  ON internal.thread_events (created_at);

CREATE TABLE internal.user_inbox_sync_state (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  version bigint NOT NULL DEFAULT 0,
  retained_from_version bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE internal.inbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  version bigint NOT NULL,
  thread_id uuid NULL REFERENCES public.threads(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inbox_events_user_id_version_key UNIQUE (user_id, version)
);

CREATE INDEX inbox_events_created_at_idx
  ON internal.inbox_events (created_at);

-- Source: supabase/sql/functions/messaging/is_user_pair_abuse_blocked_for_user.sql
CREATE OR REPLACE FUNCTION internal.is_user_pair_abuse_blocked_for_user(
  p_user_id uuid,
  p_other_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN p_user_id IS NULL OR p_other_user_id IS NULL OR p_user_id = p_other_user_id THEN false
    ELSE EXISTS (
      SELECT 1
      FROM public.shift_shares ss
      WHERE (
        (ss.owner_id = p_user_id AND ss.viewer_id = p_other_user_id)
        OR
        (ss.owner_id = p_other_user_id AND ss.viewer_id = p_user_id)
      )
        AND ss.blocked_by_user_id IS NOT NULL
    )
  END;
$function$;

-- Source: supabase/sql/functions/messaging/can_access_thread_as_user.sql
CREATE OR REPLACE FUNCTION internal.can_access_thread_as_user(
  p_thread_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH current_membership AS (
    SELECT
      tm.thread_id,
      CASE
        WHEN dt.user_low_id = p_user_id THEN dt.user_high_id
        WHEN dt.user_high_id = p_user_id THEN dt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM public.thread_memberships tm
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = tm.thread_id
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = p_user_id
      AND tm.status = 'active'
  )
  SELECT EXISTS (
    SELECT 1
    FROM current_membership cm
    WHERE cm.counterpart_user_id IS NULL
      OR NOT internal.is_user_pair_abuse_blocked_for_user(p_user_id, cm.counterpart_user_id)
  );
$function$;

-- Source: supabase/sql/functions/messaging/build_thread_core_sync_payload_v2.sql
CREATE OR REPLACE FUNCTION internal.build_thread_core_sync_payload_v2(p_thread_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'id', t.id,
    'kind', t.kind,
    'title', t.title,
    'avatar_url', t.avatar_url,
    'metadata', t.metadata,
    'created_at', t.created_at
  )
  FROM public.threads t
  WHERE t.id = p_thread_id;
$function$;

-- Source: supabase/sql/functions/messaging/build_thread_user_state_sync_payload_v2.sql
CREATE OR REPLACE FUNCTION internal.build_thread_user_state_sync_payload_v2(
  p_thread_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'thread_id', t.id,
    'user_id', p_user_id,
    'last_read_message_id', tus.last_read_message_id,
    'last_read_at', tus.last_read_at,
    'unread_count', COALESCE(tus.unread_count, 0),
    'muted', COALESCE(tus.muted, false),
    'archived_at', tus.archived_at,
    'updated_at', COALESCE(tus.updated_at, t.created_at)
  )
  FROM public.threads t
  LEFT JOIN public.thread_user_state tus
    ON tus.thread_id = t.id
   AND tus.user_id = p_user_id
  WHERE t.id = p_thread_id
    AND internal.can_access_thread_as_user(p_thread_id, p_user_id);
$function$;

-- Source: supabase/sql/functions/messaging/build_direct_thread_counterpart_sync_payload_v2.sql
CREATE OR REPLACE FUNCTION internal.build_direct_thread_counterpart_sync_payload_v2(
  p_thread_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH counterpart AS (
    SELECT
      CASE
        WHEN dt.user_low_id = p_user_id THEN dt.user_high_id
        WHEN dt.user_high_id = p_user_id THEN dt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM public.direct_threads dt
    WHERE dt.thread_id = p_thread_id
  )
  SELECT jsonb_build_object(
    'user_id', c.counterpart_user_id,
    'display_name', COALESCE(
      au.raw_user_meta_data->>'full_name',
      au.raw_user_meta_data->>'name',
      au.email,
      'Someone'
    ),
    'profile_picture_url', us.profile_picture_url,
    'oauth_avatar_url', COALESCE(
      au.raw_user_meta_data->>'avatar_url',
      au.raw_user_meta_data->>'picture'
    )
  )
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  WHERE c.counterpart_user_id IS NOT NULL
    AND internal.can_access_thread_as_user(p_thread_id, p_user_id);
$function$;

-- Source: supabase/sql/functions/messaging/build_thread_summary_sync_payload_v2.sql
CREATE OR REPLACE FUNCTION internal.build_thread_summary_sync_payload_v2(
  p_thread_id uuid,
  p_viewer_user_id uuid,
  p_use_last_message_override boolean DEFAULT false,
  p_last_message_id uuid DEFAULT NULL,
  p_last_message_sender_id uuid DEFAULT NULL,
  p_last_message_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH base_thread AS (
    SELECT
      t.id,
      t.kind,
      t.title,
      t.avatar_url,
      t.metadata,
      CASE
        WHEN p_use_last_message_override THEN p_last_message_id
        ELSE t.last_message_id
      END AS last_message_id,
      CASE
        WHEN p_use_last_message_override THEN p_last_message_sender_id
        ELSE t.last_message_sender_id
      END AS last_message_sender_id,
      CASE
        WHEN p_use_last_message_override THEN COALESCE(p_last_message_at, t.created_at)
        ELSE t.last_message_at
      END AS last_message_at,
      t.created_at,
      tus.muted,
      tus.unread_count,
      dt.user_low_id,
      dt.user_high_id,
      p_viewer_user_id AS viewer_user_id
    FROM public.threads t
    JOIN public.thread_memberships tm
      ON tm.thread_id = t.id
     AND tm.user_id = p_viewer_user_id
     AND tm.status = 'active'
    LEFT JOIN public.thread_user_state tus
      ON tus.thread_id = t.id
     AND tus.user_id = p_viewer_user_id
    LEFT JOIN public.direct_threads dt
      ON dt.thread_id = t.id
    WHERE t.id = p_thread_id
  ),
  counterpart AS (
    SELECT
      bt.*,
      CASE
        WHEN bt.kind = 'direct' AND bt.user_low_id = bt.viewer_user_id THEN bt.user_high_id
        WHEN bt.kind = 'direct' AND bt.user_high_id = bt.viewer_user_id THEN bt.user_low_id
        ELSE NULL
      END AS counterpart_user_id
    FROM base_thread bt
  )
  SELECT jsonb_build_object(
    'thread_id', c.id,
    'kind', c.kind,
    'title', c.title,
    'avatar_url', c.avatar_url,
    'metadata', c.metadata,
    'counterpart_user_id', c.counterpart_user_id,
    'counterpart_display_name', CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.email,
        'Someone'
      )
    END,
    'counterpart_profile_picture_url', us.profile_picture_url,
    'counterpart_oauth_avatar_url', CASE
      WHEN c.counterpart_user_id IS NULL THEN NULL
      ELSE COALESCE(
        au.raw_user_meta_data->>'avatar_url',
        au.raw_user_meta_data->>'picture'
      )
    END,
    'last_message_id', c.last_message_id,
    'last_message_sender_id', c.last_message_sender_id,
    'last_message_at', c.last_message_at,
    'last_message_body', lm.body,
    'last_message_preview_kind', public.message_preview_kind(
      lm.body,
      lm.metadata,
      COALESCE(last_message_media.has_image, false)
    ),
    'last_message_has_image', COALESCE(last_message_media.has_image, false),
    'unread_count', COALESCE(c.unread_count, 0)::bigint,
    'muted', COALESCE(c.muted, false),
    'created_at', c.created_at
  )
  FROM counterpart c
  LEFT JOIN auth.users au
    ON au.id = c.counterpart_user_id
  LEFT JOIN public.user_settings us
    ON us.user_id = c.counterpart_user_id
  LEFT JOIN public.messages lm
    ON lm.id = c.last_message_id
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1
      FROM public.message_attachments lma
      WHERE lma.message_id = c.last_message_id
    ) AS has_image
  ) AS last_message_media
    ON true
  WHERE c.counterpart_user_id IS NULL
     OR NOT internal.is_user_pair_abuse_blocked_for_user(p_viewer_user_id, c.counterpart_user_id);
$function$;

-- Source: supabase/sql/functions/messaging/build_message_sync_payload_v2.sql
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

-- Source: supabase/sql/functions/messaging/shape_message_sync_payload_v2.sql
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

-- Source: supabase/sql/functions/messaging/append_thread_event.sql
CREATE OR REPLACE FUNCTION internal.append_thread_event(
  p_thread_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb,
  p_actor_user_id uuid DEFAULT NULL
)
RETURNS internal.thread_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_thread public.threads%ROWTYPE;
  v_event internal.thread_events%ROWTYPE;
  v_now timestamptz := now();
  v_next_version bigint;
  v_next_retained_from_version bigint;
BEGIN
  IF p_thread_id IS NULL THEN
    RAISE EXCEPTION 'thread_id is required';
  END IF;

  IF NULLIF(btrim(COALESCE(p_event_type, '')), '') IS NULL THEN
    RAISE EXCEPTION 'event_type is required';
  END IF;

  IF NULLIF(btrim(COALESCE(p_entity_type, '')), '') IS NULL THEN
    RAISE EXCEPTION 'entity_type is required';
  END IF;

  SELECT *
  INTO v_thread
  FROM public.threads t
  WHERE t.id = p_thread_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Thread not found';
  END IF;

  v_next_version := COALESCE(v_thread.state_version, 0) + 1;
  v_next_retained_from_version := CASE
    WHEN COALESCE(v_thread.state_version, 0) = 0 AND COALESCE(v_thread.retained_from_version, 0) = 0 THEN 1
    ELSE COALESCE(v_thread.retained_from_version, 0)
  END;

  UPDATE public.threads t
  SET
    state_version = v_next_version,
    retained_from_version = v_next_retained_from_version
  WHERE t.id = p_thread_id;

  INSERT INTO internal.thread_events (
    thread_id,
    version,
    event_type,
    entity_type,
    entity_id,
    payload,
    actor_user_id,
    created_at
  )
  VALUES (
    p_thread_id,
    v_next_version,
    p_event_type,
    p_entity_type,
    p_entity_id,
    COALESCE(p_payload, '{}'::jsonb),
    p_actor_user_id,
    v_now
  )
  RETURNING *
  INTO v_event;

  RETURN v_event;
END;
$function$;

-- Source: supabase/sql/functions/messaging/append_inbox_event.sql
CREATE OR REPLACE FUNCTION internal.append_inbox_event(
  p_user_id uuid,
  p_thread_id uuid,
  p_event_type text,
  p_payload jsonb
)
RETURNS internal.inbox_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_state internal.user_inbox_sync_state%ROWTYPE;
  v_event internal.inbox_events%ROWTYPE;
  v_now timestamptz := now();
  v_next_version bigint;
  v_next_retained_from_version bigint;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id is required';
  END IF;

  IF NULLIF(btrim(COALESCE(p_event_type, '')), '') IS NULL THEN
    RAISE EXCEPTION 'event_type is required';
  END IF;

  INSERT INTO internal.user_inbox_sync_state (
    user_id,
    version,
    retained_from_version,
    updated_at
  )
  VALUES (
    p_user_id,
    0,
    0,
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;

  SELECT *
  INTO v_state
  FROM internal.user_inbox_sync_state uiss
  WHERE uiss.user_id = p_user_id
  FOR UPDATE;

  v_next_version := COALESCE(v_state.version, 0) + 1;
  v_next_retained_from_version := CASE
    WHEN COALESCE(v_state.version, 0) = 0 AND COALESCE(v_state.retained_from_version, 0) = 0 THEN 1
    ELSE COALESCE(v_state.retained_from_version, 0)
  END;

  UPDATE internal.user_inbox_sync_state uiss
  SET
    version = v_next_version,
    retained_from_version = v_next_retained_from_version,
    updated_at = v_now
  WHERE uiss.user_id = p_user_id;

  INSERT INTO internal.inbox_events (
    user_id,
    version,
    thread_id,
    event_type,
    payload,
    created_at
  )
  VALUES (
    p_user_id,
    v_next_version,
    p_thread_id,
    p_event_type,
    COALESCE(p_payload, '{}'::jsonb),
    v_now
  )
  RETURNING *
  INTO v_event;

  RETURN v_event;
END;
$function$;

-- Source: supabase/sql/functions/messaging/emit_thread_upserted_inbox_event_v2.sql
CREATE OR REPLACE FUNCTION internal.emit_thread_upserted_inbox_event_v2(
  p_user_id uuid,
  p_thread_id uuid,
  p_use_last_message_override boolean DEFAULT false,
  p_last_message_id uuid DEFAULT NULL,
  p_last_message_sender_id uuid DEFAULT NULL,
  p_last_message_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_payload jsonb;
BEGIN
  v_payload := internal.build_thread_summary_sync_payload_v2(
    p_thread_id,
    p_user_id,
    p_use_last_message_override,
    p_last_message_id,
    p_last_message_sender_id,
    p_last_message_at
  );

  IF v_payload IS NULL THEN
    RETURN;
  END IF;

  PERFORM internal.append_inbox_event(
    p_user_id,
    p_thread_id,
    'thread_upserted',
    v_payload
  );
END;
$function$;

-- Source: supabase/sql/functions/messaging/emit_thread_removed_inbox_event_v2.sql
CREATE OR REPLACE FUNCTION internal.emit_thread_removed_inbox_event_v2(
  p_user_id uuid,
  p_thread_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
BEGIN
  IF p_user_id IS NULL OR p_thread_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM internal.append_inbox_event(
    p_user_id,
    p_thread_id,
    'thread_removed',
    jsonb_build_object(
      'thread_id', p_thread_id,
      'removed_at', now()
    )
  );
END;
$function$;

-- Source: supabase/sql/functions/messaging/purge_messaging_sync_events_v2.sql
CREATE OR REPLACE FUNCTION internal.purge_messaging_sync_events_v2(
  p_retention interval DEFAULT interval '30 days'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_cutoff timestamptz := now() - COALESCE(p_retention, interval '30 days');
  v_deleted_thread_events integer := 0;
  v_deleted_inbox_events integer := 0;
BEGIN
  DELETE FROM internal.thread_events te
  WHERE te.created_at < v_cutoff;
  GET DIAGNOSTICS v_deleted_thread_events = ROW_COUNT;

  DELETE FROM internal.inbox_events ie
  WHERE ie.created_at < v_cutoff;
  GET DIAGNOSTICS v_deleted_inbox_events = ROW_COUNT;

  UPDATE public.threads t
  SET retained_from_version = CASE
    WHEN t.state_version = 0 THEN 0
    ELSE COALESCE(
      (
        SELECT MIN(te.version)
        FROM internal.thread_events te
        WHERE te.thread_id = t.id
      ),
      t.state_version + 1
    )
  END
  WHERE t.state_version > 0;

  UPDATE internal.user_inbox_sync_state uiss
  SET retained_from_version = CASE
    WHEN uiss.version = 0 THEN 0
    ELSE COALESCE(
      (
        SELECT MIN(ie.version)
        FROM internal.inbox_events ie
        WHERE ie.user_id = uiss.user_id
      ),
      uiss.version + 1
    )
  END;

  RETURN jsonb_build_object(
    'cutoff', v_cutoff,
    'deleted_thread_events', v_deleted_thread_events,
    'deleted_inbox_events', v_deleted_inbox_events
  );
END;
$function$;

-- Source: supabase/sql/functions/trigger/emit_thread_message_insert_sync_v2.sql
CREATE OR REPLACE FUNCTION internal.emit_thread_message_insert_sync_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
BEGIN
  IF current_setting('tidex.messaging_v2_emit_message_insert', true) IS DISTINCT FROM 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  PERFORM internal.append_thread_event(
    NEW.thread_id,
    'message_upserted',
    'message',
    NEW.id,
    internal.build_message_sync_payload_v2(NEW.id),
    NEW.sender_user_id
  );

  PERFORM internal.emit_thread_upserted_inbox_event_v2(
    tm.user_id,
    NEW.thread_id,
    true,
    NEW.id,
    NEW.sender_user_id,
    NEW.created_at
  )
  FROM public.thread_memberships tm
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND internal.can_access_thread_as_user(NEW.thread_id, tm.user_id);

  RETURN NEW;
END;
$function$;

-- Source: supabase/sql/functions/trigger/emit_thread_message_soft_delete_sync_v2.sql
CREATE OR REPLACE FUNCTION internal.emit_thread_message_soft_delete_sync_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_last_message_id uuid;
  v_last_message_sender_id uuid;
  v_last_message_at timestamptz;
  v_thread_created_at timestamptz;
BEGIN
  IF current_setting('tidex.messaging_v2_emit_message_soft_delete', true) IS DISTINCT FROM 'true' THEN
    RETURN NEW;
  END IF;

  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT
    m.id,
    m.sender_user_id,
    m.created_at
  INTO
    v_last_message_id,
    v_last_message_sender_id,
    v_last_message_at
  FROM public.messages m
  WHERE m.thread_id = NEW.thread_id
    AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  SELECT t.created_at
  INTO v_thread_created_at
  FROM public.threads t
  WHERE t.id = NEW.thread_id;

  PERFORM internal.append_thread_event(
    NEW.thread_id,
    'message_deleted',
    'message',
    NEW.id,
    jsonb_build_object(
      'id', NEW.id,
      'thread_id', NEW.thread_id,
      'deleted_at', NEW.deleted_at
    ),
    NEW.sender_user_id
  );

  PERFORM internal.emit_thread_upserted_inbox_event_v2(
    tm.user_id,
    NEW.thread_id,
    true,
    v_last_message_id,
    v_last_message_sender_id,
    COALESCE(v_last_message_at, v_thread_created_at)
  )
  FROM public.thread_memberships tm
  WHERE tm.thread_id = NEW.thread_id
    AND tm.status = 'active'
    AND internal.can_access_thread_as_user(NEW.thread_id, tm.user_id);

  RETURN NEW;
END;
$function$;

-- Source: supabase/sql/functions/trigger/emit_message_reaction_sync_v2.sql
CREATE OR REPLACE FUNCTION internal.emit_message_reaction_sync_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_message_id uuid := COALESCE(NEW.message_id, OLD.message_id);
  v_thread_id uuid := COALESCE(NEW.thread_id, OLD.thread_id);
  v_actor_user_id uuid := COALESCE(NEW.user_id, OLD.user_id);
BEGIN
  IF current_setting('tidex.messaging_v2_emit_message_reaction', true) IS DISTINCT FROM 'true' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM internal.append_thread_event(
    v_thread_id,
    'message_upserted',
    'message',
    v_message_id,
    internal.build_message_sync_payload_v2(v_message_id),
    v_actor_user_id
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Source: supabase/sql/functions/messaging/get_thread_sync_snapshot_v2.sql
CREATE OR REPLACE FUNCTION public.get_thread_sync_snapshot_v2(
  p_thread_id uuid,
  p_message_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_message_limit, 50), 1), 100);
  v_snapshot_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_thread_payload jsonb;
  v_viewer_state_payload jsonb;
  v_counterpart_payload jsonb;
  v_messages_payload jsonb := '[]'::jsonb;
  v_next_cursor jsonb;
  v_has_more boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT
    t.state_version,
    t.retained_from_version
  INTO
    v_snapshot_version,
    v_retained_from_version
  FROM public.threads t
  WHERE t.id = p_thread_id;

  v_thread_payload := internal.build_thread_core_sync_payload_v2(p_thread_id);
  v_viewer_state_payload := internal.build_thread_user_state_sync_payload_v2(p_thread_id, v_uid);
  v_counterpart_payload := internal.build_direct_thread_counterpart_sync_payload_v2(p_thread_id, v_uid);

  WITH selected_messages AS (
    SELECT m.id, m.created_at
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT v_limit + 1
  ),
  page_messages AS (
    SELECT sm.id, sm.created_at
    FROM selected_messages sm
    ORDER BY sm.created_at DESC, sm.id DESC
    LIMIT v_limit
  ),
  ordered_messages AS (
    SELECT pm.id, pm.created_at
    FROM page_messages pm
    ORDER BY pm.created_at ASC, pm.id ASC
  ),
  page_bounds AS (
    SELECT
      EXISTS (
        SELECT 1
        FROM selected_messages sm
        OFFSET v_limit
      ) AS has_more,
      (
        SELECT jsonb_build_object(
          'before_created_at', om.created_at,
          'before_message_id', om.id
        )
        FROM ordered_messages om
        ORDER BY om.created_at ASC, om.id ASC
        LIMIT 1
      ) AS next_cursor
  )
  SELECT
    COALESCE((
      SELECT jsonb_agg(
        internal.shape_message_sync_payload_v2(
          internal.build_message_sync_payload_v2(om.id),
          v_uid
        )
        ORDER BY om.created_at ASC, om.id ASC
      )
      FROM ordered_messages om
    ), '[]'::jsonb),
    (
      SELECT pb.next_cursor
      FROM page_bounds pb
    ),
    COALESCE((
      SELECT pb.has_more
      FROM page_bounds pb
    ), false)
  INTO
    v_messages_payload,
    v_next_cursor,
    v_has_more;

  RETURN jsonb_build_object(
    'thread', v_thread_payload,
    'viewer_state', v_viewer_state_payload,
    'counterpart_state', v_counterpart_payload,
    'messages', v_messages_payload,
    'next_cursor', CASE
      WHEN v_has_more THEN v_next_cursor
      ELSE NULL
    END,
    'snapshot_version', COALESCE(v_snapshot_version, 0),
    'retained_from_version', COALESCE(v_retained_from_version, 0),
    'has_more', v_has_more
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) TO authenticated;

-- Source: supabase/sql/functions/messaging/list_thread_events_v2.sql
CREATE OR REPLACE FUNCTION public.list_thread_events_v2(
  p_thread_id uuid,
  p_after_version bigint,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
  v_latest_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_requires_snapshot boolean := false;
  v_has_more boolean := false;
  v_events jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_after_version IS NULL OR p_after_version < 0 THEN
    RAISE EXCEPTION 'after_version must be a non-negative bigint';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT
    COALESCE(t.state_version, 0),
    COALESCE(t.retained_from_version, 0)
  INTO
    v_latest_version,
    v_retained_from_version
  FROM public.threads t
  WHERE t.id = p_thread_id;

  v_requires_snapshot := v_latest_version > 0
    AND p_after_version < GREATEST(v_retained_from_version - 1, 0);

  IF NOT v_requires_snapshot THEN
    WITH selected_events AS (
      SELECT
        te.id,
        te.version,
        te.event_type,
        te.entity_type,
        te.entity_id,
        te.payload,
        te.actor_user_id,
        te.created_at
      FROM internal.thread_events te
      WHERE te.thread_id = p_thread_id
        AND te.version > p_after_version
      ORDER BY te.version ASC
      LIMIT v_limit + 1
    ),
    page_events AS (
      SELECT se.*
      FROM selected_events se
      ORDER BY se.version ASC
      LIMIT v_limit
    )
    SELECT
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', pe.id,
            'version', pe.version,
            'event_type', pe.event_type,
            'entity_type', pe.entity_type,
            'entity_id', pe.entity_id,
            'created_at', pe.created_at,
            'actor_user_id', pe.actor_user_id,
            'payload', CASE
              WHEN pe.event_type = 'message_upserted' THEN
                internal.shape_message_sync_payload_v2(pe.payload, v_uid)
              ELSE
                pe.payload
            END
          )
          ORDER BY pe.version ASC
        ),
        '[]'::jsonb
      ),
      EXISTS (
        SELECT 1
        FROM selected_events se
        OFFSET v_limit
      )
    INTO
      v_events,
      v_has_more
    FROM page_events pe;
  END IF;

  RETURN jsonb_build_object(
    'requires_snapshot', v_requires_snapshot,
    'latest_version', v_latest_version,
    'retained_from_version', v_retained_from_version,
    'has_more', CASE
      WHEN v_requires_snapshot THEN false
      ELSE v_has_more
    END,
    'events', CASE
      WHEN v_requires_snapshot THEN '[]'::jsonb
      ELSE v_events
    END
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) TO authenticated;

-- Source: supabase/sql/functions/messaging/get_inbox_sync_snapshot_v2.sql
CREATE OR REPLACE FUNCTION public.get_inbox_sync_snapshot_v2(
  p_limit integer DEFAULT 30,
  p_before_last_message_at timestamptz DEFAULT NULL,
  p_before_thread_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_snapshot_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_threads jsonb := '[]'::jsonb;
  v_next_cursor jsonb;
  v_has_more boolean := false;
  v_unread_direct_message_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF (p_before_last_message_at IS NULL) <> (p_before_thread_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both before_last_message_at and before_thread_id';
  END IF;

  SELECT
    COALESCE(uiss.version, 0),
    COALESCE(uiss.retained_from_version, 0)
  INTO
    v_snapshot_version,
    v_retained_from_version
  FROM internal.user_inbox_sync_state uiss
  WHERE uiss.user_id = v_uid;

  WITH visible_threads AS (
    SELECT t.id, t.last_message_at
    FROM public.thread_memberships tm
    JOIN public.threads t
      ON t.id = tm.thread_id
    WHERE tm.user_id = v_uid
      AND tm.status = 'active'
      AND internal.can_access_thread_as_user(t.id, v_uid)
      AND (
        p_before_last_message_at IS NULL
        OR (t.last_message_at, t.id) < (p_before_last_message_at, p_before_thread_id)
      )
    ORDER BY t.last_message_at DESC, t.id DESC
    LIMIT v_limit + 1
  ),
  page_threads AS (
    SELECT vt.id, vt.last_message_at
    FROM visible_threads vt
    ORDER BY vt.last_message_at DESC, vt.id DESC
    LIMIT v_limit
  ),
  last_page_row AS (
    SELECT pt.last_message_at, pt.id
    FROM page_threads pt
    ORDER BY pt.last_message_at ASC, pt.id ASC
    LIMIT 1
  )
  SELECT
    COALESCE(
      jsonb_agg(
        internal.build_thread_summary_sync_payload_v2(pt.id, v_uid)
        ORDER BY pt.last_message_at DESC, pt.id DESC
      ),
      '[]'::jsonb
    ),
    EXISTS (
      SELECT 1
      FROM visible_threads vt
      OFFSET v_limit
    ),
    (
      SELECT jsonb_build_object(
        'before_last_message_at', lpr.last_message_at,
        'before_thread_id', lpr.id
      )
      FROM last_page_row lpr
    )
  INTO
    v_threads,
    v_has_more,
    v_next_cursor
  FROM page_threads pt;

  SELECT COALESCE(SUM(COALESCE(tus.unread_count, 0)), 0)::integer
  INTO v_unread_direct_message_count
  FROM public.threads t
  JOIN public.thread_memberships tm
    ON tm.thread_id = t.id
   AND tm.user_id = v_uid
   AND tm.status = 'active'
  LEFT JOIN public.thread_user_state tus
    ON tus.thread_id = t.id
   AND tus.user_id = v_uid
  WHERE t.kind = 'direct'
    AND internal.can_access_thread_as_user(t.id, v_uid);

  RETURN jsonb_build_object(
    'threads', v_threads,
    'unread_direct_message_count', v_unread_direct_message_count,
    'next_cursor', CASE
      WHEN v_has_more THEN v_next_cursor
      ELSE NULL
    END,
    'snapshot_version', v_snapshot_version,
    'retained_from_version', v_retained_from_version,
    'has_more', v_has_more
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamptz, uuid) TO authenticated;

-- Source: supabase/sql/functions/messaging/list_inbox_events_v2.sql
CREATE OR REPLACE FUNCTION public.list_inbox_events_v2(
  p_after_version bigint,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
  v_latest_version bigint := 0;
  v_retained_from_version bigint := 0;
  v_requires_snapshot boolean := false;
  v_has_more boolean := false;
  v_events jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_after_version IS NULL OR p_after_version < 0 THEN
    RAISE EXCEPTION 'after_version must be a non-negative bigint';
  END IF;

  SELECT
    COALESCE(uiss.version, 0),
    COALESCE(uiss.retained_from_version, 0)
  INTO
    v_latest_version,
    v_retained_from_version
  FROM internal.user_inbox_sync_state uiss
  WHERE uiss.user_id = v_uid;

  v_requires_snapshot := v_latest_version > 0
    AND p_after_version < GREATEST(v_retained_from_version - 1, 0);

  IF NOT v_requires_snapshot THEN
    WITH selected_events AS (
      SELECT
        ie.id,
        ie.version,
        ie.thread_id,
        ie.event_type,
        ie.payload,
        ie.created_at
      FROM internal.inbox_events ie
      WHERE ie.user_id = v_uid
        AND ie.version > p_after_version
      ORDER BY ie.version ASC
      LIMIT v_limit + 1
    ),
    page_events AS (
      SELECT se.*
      FROM selected_events se
      ORDER BY se.version ASC
      LIMIT v_limit
    )
    SELECT
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', pe.id,
            'version', pe.version,
            'thread_id', pe.thread_id,
            'event_type', pe.event_type,
            'created_at', pe.created_at,
            'payload', pe.payload
          )
          ORDER BY pe.version ASC
        ),
        '[]'::jsonb
      ),
      EXISTS (
        SELECT 1
        FROM selected_events se
        OFFSET v_limit
      )
    INTO
      v_events,
      v_has_more
    FROM page_events pe;
  END IF;

  RETURN jsonb_build_object(
    'requires_snapshot', v_requires_snapshot,
    'latest_version', v_latest_version,
    'retained_from_version', v_retained_from_version,
    'has_more', CASE
      WHEN v_requires_snapshot THEN false
      ELSE v_has_more
    END,
    'events', CASE
      WHEN v_requires_snapshot THEN '[]'::jsonb
      ELSE v_events
    END
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) TO authenticated;

-- Source: supabase/sql/functions/messaging/send_message.sql
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, uuid, jsonb);
DROP FUNCTION IF EXISTS public.send_message(uuid, uuid, text, jsonb);

CREATE FUNCTION public.send_message(
  p_thread_id uuid,
  p_client_id uuid,
  p_body text,
  p_reply_to_message_id uuid DEFAULT NULL,
  p_attachments jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
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
  v_normalized_body text;
  v_attachment_count integer := 0;
  v_existing_message_id uuid;
  v_message_id uuid;
  v_message_created_at timestamptz;
  v_attachment record;
  v_object record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'client_id is required';
  END IF;

  IF NOT public.can_post_to_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Posting is not allowed for this thread';
  END IF;

  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_reply_to_message_id
      AND m.thread_id = p_thread_id
      AND m.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reply target must exist in the same thread';
  END IF;

  IF p_attachments IS NULL THEN
    p_attachments := '[]'::jsonb;
  END IF;

  IF p_metadata IS NULL THEN
    p_metadata := '{}'::jsonb;
  END IF;

  IF jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Attachments must be a JSON array';
  END IF;

  PERFORM public.assert_message_metadata_validity(p_metadata);

  SELECT m.id
  INTO v_existing_message_id
  FROM public.messages m
  WHERE m.thread_id = p_thread_id
    AND m.sender_user_id = v_uid
    AND m.client_id = p_client_id
  LIMIT 1;

  IF v_existing_message_id IS NOT NULL THEN
    RETURN QUERY
    SELECT *
    FROM public.get_message_payload(v_existing_message_id);
    RETURN;
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NOT NULL AND char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  SELECT count(*)
  INTO v_attachment_count
  FROM jsonb_array_elements(p_attachments);

  IF NOT public.message_has_renderable_content(v_normalized_body, p_attachments, p_metadata) THEN
    RAISE EXCEPTION 'A message must include text, at least one attachment, or supported rich content';
  END IF;

  IF v_attachment_count > 4 THEN
    RAISE EXCEPTION 'Too many attachments';
  END IF;

  FOR v_attachment IN
    SELECT
      ordinality - 1 AS attachment_index,
      (value->>'attachment_id')::uuid AS attachment_id,
      value->>'storage_path' AS storage_path,
      value->>'mime_type' AS mime_type,
      NULLIF(value->>'byte_size', '')::bigint AS byte_size,
      NULLIF(value->>'width', '')::integer AS width,
      NULLIF(value->>'height', '')::integer AS height
    FROM jsonb_array_elements(p_attachments) WITH ORDINALITY
  LOOP
    IF v_attachment.attachment_id IS NULL
       OR v_attachment.storage_path IS NULL
       OR v_attachment.mime_type IS NULL
       OR v_attachment.byte_size IS NULL THEN
      RAISE EXCEPTION 'Attachment descriptors must include attachment_id, storage_path, mime_type, and byte_size';
    END IF;

    IF v_attachment.mime_type NOT IN (
      'image/webp',
      'image/heic',
      'image/heif',
      'image/jpeg',
      'image/png'
    ) THEN
      RAISE EXCEPTION 'Unsupported attachment mime type: %', v_attachment.mime_type;
    END IF;

    IF NOT public.can_upload_message_attachment_object(v_attachment.storage_path) THEN
      RAISE EXCEPTION 'Invalid attachment path for this thread or user';
    END IF;

    IF split_part(split_part(v_attachment.storage_path, '/', 3), '.', 1)::uuid <> v_attachment.attachment_id THEN
      RAISE EXCEPTION 'Attachment path must contain the attachment_id in the file name';
    END IF;

    SELECT o.owner_id, o.metadata
    INTO v_object
    FROM storage.objects o
    WHERE o.bucket_id = 'message-attachments'
      AND o.name = v_attachment.storage_path
    LIMIT 1;

    IF v_object.owner_id IS NULL THEN
      RAISE EXCEPTION 'Attachment object not found';
    END IF;

    IF v_object.owner_id <> v_uid::text THEN
      RAISE EXCEPTION 'Attachment object owner mismatch';
    END IF;

    IF COALESCE(v_object.metadata->>'mimetype', '') <> v_attachment.mime_type THEN
      RAISE EXCEPTION 'Attachment mime type does not match stored object metadata';
    END IF;

    IF COALESCE((v_object.metadata->>'size')::bigint, -1) <> v_attachment.byte_size THEN
      RAISE EXCEPTION 'Attachment size does not match stored object metadata';
    END IF;

    IF v_attachment.byte_size <= 0 OR v_attachment.byte_size > 5242880 THEN
      RAISE EXCEPTION 'Attachment size exceeds the 5 MB limit';
    END IF;

    IF v_attachment.width IS NOT NULL AND v_attachment.width <= 0 THEN
      RAISE EXCEPTION 'Attachment width must be positive';
    END IF;

    IF v_attachment.height IS NOT NULL AND v_attachment.height <= 0 THEN
      RAISE EXCEPTION 'Attachment height must be positive';
    END IF;
  END LOOP;

  -- Emit the V2 sync payload after attachments have been persisted.
  PERFORM set_config('tidex.messaging_v2_emit_message_insert', 'false', true);

  INSERT INTO public.messages (
    thread_id,
    sender_user_id,
    message_type,
    body,
    client_id,
    reply_to_message_id,
    metadata
  )
  VALUES (
    p_thread_id,
    v_uid,
    'user',
    v_normalized_body,
    p_client_id,
    p_reply_to_message_id,
    p_metadata
  )
  RETURNING messages.id, messages.created_at INTO v_message_id, v_message_created_at;

  INSERT INTO public.message_attachments (
    id,
    message_id,
    attachment_index,
    kind,
    storage_bucket,
    storage_path,
    mime_type,
    byte_size,
    width,
    height
  )
  SELECT
    (value->>'attachment_id')::uuid,
    v_message_id,
    ordinality - 1,
    'image',
    'message-attachments',
    value->>'storage_path',
    value->>'mime_type',
    NULLIF(value->>'byte_size', '')::bigint,
    NULLIF(value->>'width', '')::integer,
    NULLIF(value->>'height', '')::integer
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY;

  UPDATE public.threads
  SET
    last_message_id = v_message_id,
    last_message_sender_id = v_uid,
    last_message_at = v_message_created_at
  WHERE threads.id = p_thread_id;

  PERFORM internal.append_thread_event(
    p_thread_id,
    'message_upserted',
    'message',
    v_message_id,
    internal.build_message_sync_payload_v2(v_message_id),
    v_uid
  );

  PERFORM internal.emit_thread_upserted_inbox_event_v2(
    tm.user_id,
    p_thread_id,
    true,
    v_message_id,
    v_uid,
    v_message_created_at
  )
  FROM public.thread_memberships tm
  WHERE tm.thread_id = p_thread_id
    AND tm.status = 'active'
    AND internal.can_access_thread_as_user(p_thread_id, tm.user_id);

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(v_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM public;
REVOKE EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) TO authenticated;

-- Source: supabase/sql/functions/messaging/edit_message.sql
CREATE OR REPLACE FUNCTION public.edit_message(
  p_message_id uuid,
  p_body text
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
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_existing_body text;
  v_normalized_body text;
  v_is_preview_source boolean := false;
  v_did_update boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at,
    NULLIF(regexp_replace(COALESCE(m.body, ''), '^\s+|\s+$', '', 'g'), '')
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at,
    v_existing_body
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can edit this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be edited';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Deleted messages cannot be edited';
  END IF;

  IF v_existing_body IS NULL THEN
    RAISE EXCEPTION 'Only text messages can be edited';
  END IF;

  v_normalized_body := NULLIF(
    regexp_replace(COALESCE(p_body, ''), '^\s+|\s+$', '', 'g'),
    ''
  );

  IF v_normalized_body IS NULL THEN
    RAISE EXCEPTION 'Message body cannot be empty';
  END IF;

  IF char_length(v_normalized_body) > 2000 THEN
    RAISE EXCEPTION 'Message body exceeds the 2000 character limit';
  END IF;

  IF v_normalized_body IS DISTINCT FROM v_existing_body THEN
    SELECT t.last_message_id = p_message_id
    INTO v_is_preview_source
    FROM public.threads t
    WHERE t.id = v_thread_id;

    UPDATE public.messages
    SET
      body = v_normalized_body,
      edited_at = now()
    WHERE messages.id = p_message_id;

    v_did_update := FOUND;
  END IF;

  IF v_did_update THEN
    PERFORM internal.append_thread_event(
      v_thread_id,
      'message_upserted',
      'message',
      p_message_id,
      internal.build_message_sync_payload_v2(p_message_id),
      v_uid
    );

    IF COALESCE(v_is_preview_source, false) THEN
      PERFORM internal.emit_thread_upserted_inbox_event_v2(tm.user_id, v_thread_id)
      FROM public.thread_memberships tm
      WHERE tm.thread_id = v_thread_id
        AND tm.status = 'active'
        AND internal.can_access_thread_as_user(v_thread_id, tm.user_id);
    END IF;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.get_message_payload(p_message_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.edit_message(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;

-- Source: supabase/sql/functions/messaging/delete_message.sql
CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_message_type text;
  v_deleted_at timestamptz;
  v_latest_message_id uuid;
  v_latest_sender_user_id uuid;
  v_latest_created_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT
    m.thread_id,
    m.sender_user_id,
    m.message_type,
    m.deleted_at
  INTO
    v_thread_id,
    v_sender_user_id,
    v_message_type,
    v_deleted_at
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF v_sender_user_id <> v_uid THEN
    RAISE EXCEPTION 'Only the sender can delete this message';
  END IF;

  IF v_message_type <> 'user' THEN
    RAISE EXCEPTION 'Only user messages can be deleted';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Message is already deleted';
  END IF;

  PERFORM set_config('tidex.messaging_v2_emit_message_soft_delete', 'true', true);

  UPDATE public.messages
  SET deleted_at = now()
  WHERE messages.id = p_message_id;

  SELECT
    m.id,
    m.sender_user_id,
    m.created_at
  INTO
    v_latest_message_id,
    v_latest_sender_user_id,
    v_latest_created_at
  FROM public.messages m
  WHERE m.thread_id = v_thread_id
    AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  UPDATE public.threads t
  SET
    last_message_id = v_latest_message_id,
    last_message_sender_id = v_latest_sender_user_id,
    last_message_at = COALESCE(v_latest_created_at, t.created_at)
  WHERE t.id = v_thread_id;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.delete_message(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.delete_message(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;

-- Source: supabase/sql/functions/messaging/mark_thread_read.sql
CREATE OR REPLACE FUNCTION public.mark_thread_read(
  p_thread_id uuid,
  p_through_message_id uuid
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_target_message public.messages%ROWTYPE;
  v_existing_state public.thread_user_state%ROWTYPE;
  v_existing_message public.messages%ROWTYPE;
  v_result public.thread_user_state%ROWTYPE;
  v_newly_read_count integer := 0;
  v_did_advance boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT *
  INTO v_target_message
  FROM public.messages m
  WHERE m.id = p_through_message_id
    AND m.thread_id = p_thread_id
  LIMIT 1;

  IF v_target_message.id IS NULL THEN
    RAISE EXCEPTION 'Read marker message does not belong to the thread';
  END IF;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    unread_count,
    updated_at
  )
  VALUES (
    p_thread_id,
    v_uid,
    0,
    now()
  )
  ON CONFLICT (thread_id, user_id) DO NOTHING;

  SELECT *
  INTO v_existing_state
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1
  FOR UPDATE;

  IF v_existing_state.last_read_message_id IS NOT NULL THEN
    SELECT *
    INTO v_existing_message
    FROM public.messages m
    WHERE m.id = v_existing_state.last_read_message_id
    LIMIT 1;
  END IF;

  IF v_existing_message.id IS NULL
     OR (v_target_message.created_at, v_target_message.id) > (v_existing_message.created_at, v_existing_message.id) THEN
    v_did_advance := true;

    SELECT COUNT(*)::integer
    INTO v_newly_read_count
    FROM public.messages m
    WHERE m.thread_id = p_thread_id
      AND m.sender_user_id <> v_uid
      AND m.deleted_at IS NULL
      AND (m.created_at, m.id) <= (v_target_message.created_at, v_target_message.id)
      AND (
        v_existing_message.id IS NULL
        OR (m.created_at, m.id) > (v_existing_message.created_at, v_existing_message.id)
      );

    UPDATE public.thread_user_state
    SET
      last_read_message_id = v_target_message.id,
      last_read_at = v_target_message.created_at,
      unread_count = GREATEST(COALESCE(unread_count, 0) - v_newly_read_count, 0),
      updated_at = now()
    WHERE thread_id = p_thread_id
      AND user_id = v_uid;
  END IF;

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  IF v_did_advance THEN
    PERFORM internal.emit_thread_upserted_inbox_event_v2(v_uid, p_thread_id);
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) TO authenticated;

-- Source: supabase/sql/functions/messaging/set_thread_muted.sql
CREATE OR REPLACE FUNCTION public.set_thread_muted(
  p_thread_id uuid,
  p_muted boolean
)
RETURNS public.thread_user_state
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result public.thread_user_state%ROWTYPE;
  v_existing_muted boolean;
  v_requested_muted boolean := COALESCE(p_muted, false);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  SELECT tus.muted
  INTO v_existing_muted
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id,
    muted,
    updated_at
  )
  VALUES (
    p_thread_id,
    v_uid,
    v_requested_muted,
    now()
  )
  ON CONFLICT (thread_id, user_id) DO UPDATE
  SET
    muted = EXCLUDED.muted,
    updated_at = now();

  SELECT *
  INTO v_result
  FROM public.thread_user_state tus
  WHERE tus.thread_id = p_thread_id
    AND tus.user_id = v_uid
  LIMIT 1;

  IF v_existing_muted IS DISTINCT FROM v_requested_muted OR v_existing_muted IS NULL THEN
    PERFORM internal.emit_thread_upserted_inbox_event_v2(v_uid, p_thread_id);
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM public;
REVOKE EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) TO authenticated;

-- Source: supabase/sql/functions/messaging/get_or_create_direct_thread.sql
CREATE OR REPLACE FUNCTION public.get_or_create_direct_thread(p_other_user_id uuid)
RETURNS TABLE (
  thread_id uuid,
  kind text,
  title text,
  avatar_url text,
  metadata jsonb,
  counterpart_user_id uuid,
  counterpart_display_name text,
  counterpart_profile_picture_url text,
  counterpart_oauth_avatar_url text,
  last_message_id uuid,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_body text,
  last_message_preview_kind text,
  last_message_has_image boolean,
  unread_count bigint,
  muted boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_user_low_id uuid;
  v_user_high_id uuid;
  v_was_visible_low boolean := false;
  v_was_visible_high boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_create_direct_thread(p_other_user_id) THEN
    RAISE EXCEPTION 'Direct thread creation is not allowed for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  LOOP
    SELECT dt.thread_id
    INTO v_thread_id
    FROM public.direct_threads dt
    WHERE dt.user_low_id = v_user_low_id
      AND dt.user_high_id = v_user_high_id
    LIMIT 1;

    EXIT WHEN v_thread_id IS NOT NULL;

    BEGIN
      INSERT INTO public.threads (
        kind,
        created_by_user_id
      )
      VALUES (
        'direct',
        v_uid
      )
      RETURNING id INTO v_thread_id;

      INSERT INTO public.direct_threads (
        thread_id,
        user_low_id,
        user_high_id
      )
      VALUES (
        v_thread_id,
        v_user_low_id,
        v_user_high_id
      );

      EXIT;
    EXCEPTION
      WHEN unique_violation THEN
        v_thread_id := NULL;
    END;
  END LOOP;

  IF v_thread_id IS NOT NULL THEN
    v_was_visible_low := internal.can_access_thread_as_user(v_thread_id, v_user_low_id);
    v_was_visible_high := internal.can_access_thread_as_user(v_thread_id, v_user_high_id);
  END IF;

  INSERT INTO public.thread_memberships (
    thread_id,
    user_id,
    role,
    status
  )
  VALUES
    (v_thread_id, v_user_low_id, 'member', 'active'),
    (v_thread_id, v_user_high_id, 'member', 'active')
  ON CONFLICT ON CONSTRAINT thread_memberships_pkey DO UPDATE
  SET
    role = EXCLUDED.role,
    status = 'active',
    left_at = NULL;

  INSERT INTO public.thread_user_state (
    thread_id,
    user_id
  )
  VALUES
    (v_thread_id, v_user_low_id),
    (v_thread_id, v_user_high_id)
  ON CONFLICT ON CONSTRAINT thread_user_state_pkey DO NOTHING;

  IF NOT v_was_visible_low AND internal.can_access_thread_as_user(v_thread_id, v_user_low_id) THEN
    PERFORM internal.emit_thread_upserted_inbox_event_v2(v_user_low_id, v_thread_id);
  END IF;

  IF NOT v_was_visible_high AND internal.can_access_thread_as_user(v_thread_id, v_user_high_id) THEN
    PERFORM internal.emit_thread_upserted_inbox_event_v2(v_user_high_id, v_thread_id);
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.get_thread_summary(v_thread_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;

-- Source: supabase/sql/functions/messaging/toggle_message_reaction.sql
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
    PERFORM set_config('tidex.messaging_v2_emit_message_reaction', 'true', true);

    DELETE FROM public.message_reactions mr
    WHERE mr.message_id = p_message_id
      AND mr.user_id = v_uid
      AND mr.emoji = v_emoji;
  ELSE
    PERFORM set_config('tidex.messaging_v2_emit_message_reaction', 'true', true);

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

-- Source: supabase/sql/functions/messaging/block_user_pair.sql
CREATE OR REPLACE FUNCTION public.block_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_visible_before_low boolean := false;
  v_visible_before_high boolean := false;
  v_user_low_id uuid;
  v_user_high_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_other_user_id IS NULL THEN
    RAISE EXCEPTION 'Blocked user is required';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot block yourself';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
       OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
  ) THEN
    RAISE EXCEPTION 'No sharing relationship exists for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  SELECT dt.thread_id
  INTO v_thread_id
  FROM public.direct_threads dt
  WHERE dt.user_low_id = v_user_low_id
    AND dt.user_high_id = v_user_high_id
  LIMIT 1;

  IF v_thread_id IS NOT NULL THEN
    v_visible_before_low := internal.can_access_thread_as_user(v_thread_id, v_user_low_id);
    v_visible_before_high := internal.can_access_thread_as_user(v_thread_id, v_user_high_id);
  END IF;

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = true,
      blocked_by_user_id = v_uid
  WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
     OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid);

  IF v_thread_id IS NOT NULL THEN
    IF v_visible_before_low THEN
      PERFORM internal.emit_thread_removed_inbox_event_v2(v_user_low_id, v_thread_id);
    END IF;

    IF v_visible_before_high THEN
      PERFORM internal.emit_thread_removed_inbox_event_v2(v_user_high_id, v_thread_id);
    END IF;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.block_user_pair(uuid) TO authenticated;

-- Source: supabase/sql/functions/messaging/unblock_user_pair.sql
CREATE OR REPLACE FUNCTION public.unblock_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_visible_before_low boolean := false;
  v_visible_before_high boolean := false;
  v_visible_after_low boolean := false;
  v_visible_after_high boolean := false;
  v_user_low_id uuid;
  v_user_high_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_other_user_id IS NULL THEN
    RAISE EXCEPTION 'Blocked user is required';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot unblock yourself';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.shift_shares ss
    WHERE (
      (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
      OR
      (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
    )
      AND ss.blocked_by_user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'No active block exists for this user pair';
  END IF;

  v_user_low_id := LEAST(v_uid, p_other_user_id);
  v_user_high_id := GREATEST(v_uid, p_other_user_id);

  SELECT dt.thread_id
  INTO v_thread_id
  FROM public.direct_threads dt
  WHERE dt.user_low_id = v_user_low_id
    AND dt.user_high_id = v_user_high_id
  LIMIT 1;

  IF v_thread_id IS NOT NULL THEN
    v_visible_before_low := internal.can_access_thread_as_user(v_thread_id, v_user_low_id);
    v_visible_before_high := internal.can_access_thread_as_user(v_thread_id, v_user_high_id);
  END IF;

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = false,
      blocked_by_user_id = NULL
  WHERE (
    (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
    OR
    (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid)
  )
    AND ss.blocked_by_user_id = v_uid;

  IF v_thread_id IS NOT NULL THEN
    v_visible_after_low := internal.can_access_thread_as_user(v_thread_id, v_user_low_id);
    v_visible_after_high := internal.can_access_thread_as_user(v_thread_id, v_user_high_id);

    IF NOT v_visible_before_low AND v_visible_after_low THEN
      PERFORM internal.emit_thread_upserted_inbox_event_v2(v_user_low_id, v_thread_id);
    END IF;

    IF NOT v_visible_before_high AND v_visible_after_high THEN
      PERFORM internal.emit_thread_upserted_inbox_event_v2(v_user_high_id, v_thread_id);
    END IF;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.unblock_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.unblock_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.unblock_user_pair(uuid) TO authenticated;

CREATE OR REPLACE VIEW internal.thread_stream_health_v2 AS
SELECT
  t.id AS thread_id,
  t.state_version AS latest_version,
  t.retained_from_version,
  COUNT(te.id) AS retained_event_count,
  MIN(te.created_at) AS oldest_retained_created_at,
  MAX(te.created_at) AS newest_retained_created_at
FROM public.threads t
LEFT JOIN internal.thread_events te
  ON te.thread_id = t.id
GROUP BY t.id, t.state_version, t.retained_from_version;

COMMENT ON VIEW internal.thread_stream_health_v2 IS
  'Replay gap inspection: compare a client cursor to retained_from_version and latest_version. Example: SELECT * FROM internal.thread_stream_health_v2 WHERE thread_id = <thread_uuid>;';

CREATE OR REPLACE VIEW internal.inbox_stream_health_v2 AS
SELECT
  uiss.user_id,
  uiss.version AS latest_version,
  uiss.retained_from_version,
  COUNT(ie.id) AS retained_event_count,
  MIN(ie.created_at) AS oldest_retained_created_at,
  MAX(ie.created_at) AS newest_retained_created_at
FROM internal.user_inbox_sync_state uiss
LEFT JOIN internal.inbox_events ie
  ON ie.user_id = uiss.user_id
GROUP BY uiss.user_id, uiss.version, uiss.retained_from_version;

COMMENT ON VIEW internal.inbox_stream_health_v2 IS
  'Replay gap inspection: compare a client cursor to retained_from_version and latest_version. Example: SELECT * FROM internal.inbox_stream_health_v2 WHERE user_id = <user_uuid>;';

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'purge-messaging-sync-events-v2';

SELECT cron.schedule(
  'purge-messaging-sync-events-v2',
  '0 4 * * *',
  $$SELECT internal.purge_messaging_sync_events_v2();$$
);

DROP TRIGGER IF EXISTS zz_emit_thread_message_insert_sync_v2 ON public.messages;
CREATE TRIGGER zz_emit_thread_message_insert_sync_v2
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION internal.emit_thread_message_insert_sync_v2();

DROP TRIGGER IF EXISTS zz_emit_thread_message_soft_delete_sync_v2 ON public.messages;
CREATE TRIGGER zz_emit_thread_message_soft_delete_sync_v2
  AFTER UPDATE OF deleted_at ON public.messages
  FOR EACH ROW
  WHEN (OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL)
  EXECUTE FUNCTION internal.emit_thread_message_soft_delete_sync_v2();

DROP TRIGGER IF EXISTS zz_emit_message_reaction_sync_v2 ON public.message_reactions;
CREATE TRIGGER zz_emit_message_reaction_sync_v2
  AFTER INSERT OR DELETE ON public.message_reactions
  FOR EACH ROW
  EXECUTE FUNCTION internal.emit_message_reaction_sync_v2();

-- Source: supabase/sql/functions/messaging/get_message_sync_payload_v2.sql
CREATE OR REPLACE FUNCTION public.get_message_sync_payload_v2(p_message_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_thread_id uuid;
  v_payload jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT m.thread_id
  INTO v_thread_id
  FROM public.messages m
  WHERE m.id = p_message_id;

  IF v_thread_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT public.can_access_thread(v_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  v_payload := internal.build_message_sync_payload_v2(p_message_id);

  IF v_payload IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN internal.shape_message_sync_payload_v2(v_payload, v_uid);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) TO authenticated;

-- Source: supabase/sql/functions/messaging/list_thread_messages_v2.sql
CREATE OR REPLACE FUNCTION public.list_thread_messages_v2(
  p_thread_id uuid,
  p_limit integer DEFAULT 50,
  p_before_created_at timestamptz DEFAULT NULL,
  p_before_message_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_messages_payload jsonb := '[]'::jsonb;
  v_next_cursor jsonb;
  v_has_more boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.can_access_thread(p_thread_id) THEN
    RAISE EXCEPTION 'Thread access denied';
  END IF;

  IF (p_before_created_at IS NULL) <> (p_before_message_id IS NULL) THEN
    RAISE EXCEPTION 'Pagination cursor requires both before_created_at and before_message_id';
  END IF;

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
    LIMIT v_limit + 1
  ),
  page_messages AS (
    SELECT sm.id, sm.created_at
    FROM selected_messages sm
    ORDER BY sm.created_at DESC, sm.id DESC
    LIMIT v_limit
  ),
  ordered_messages AS (
    SELECT pm.id, pm.created_at
    FROM page_messages pm
    ORDER BY pm.created_at ASC, pm.id ASC
  ),
  page_bounds AS (
    SELECT
      EXISTS (
        SELECT 1
        FROM selected_messages sm
        OFFSET v_limit
      ) AS has_more,
      (
        SELECT jsonb_build_object(
          'before_created_at', om.created_at,
          'before_message_id', om.id
        )
        FROM ordered_messages om
        ORDER BY om.created_at ASC, om.id ASC
        LIMIT 1
      ) AS next_cursor
  )
  SELECT
    COALESCE((
      SELECT jsonb_agg(
        internal.shape_message_sync_payload_v2(
          internal.build_message_sync_payload_v2(om.id),
          v_uid
        )
        ORDER BY om.created_at ASC, om.id ASC
      )
      FROM ordered_messages om
    ), '[]'::jsonb),
    (
      SELECT pb.next_cursor
      FROM page_bounds pb
    ),
    COALESCE((
      SELECT pb.has_more
      FROM page_bounds pb
    ), false)
  INTO
    v_messages_payload,
    v_next_cursor,
    v_has_more;

  RETURN jsonb_build_object(
    'messages', v_messages_payload,
    'next_cursor', CASE
      WHEN v_has_more THEN v_next_cursor
      ELSE NULL
    END,
    'has_more', v_has_more
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamptz, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamptz, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamptz, uuid) TO authenticated;
