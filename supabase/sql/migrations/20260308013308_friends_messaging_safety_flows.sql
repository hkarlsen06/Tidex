CREATE TABLE IF NOT EXISTS public.abuse_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES auth.users(id),
  reported_user_id uuid NOT NULL REFERENCES auth.users(id),
  thread_id uuid NOT NULL REFERENCES public.threads(id),
  message_id uuid NULL REFERENCES public.messages(id) ON DELETE SET NULL,
  reason text NOT NULL CHECK (
    reason = ANY (
      ARRAY[
        'harassment_or_bullying'::text,
        'sexual_content'::text,
        'hate_or_discriminatory_content'::text,
        'violence_or_threats'::text,
        'spam'::text,
        'inappropriate_profile_or_conduct'::text,
        'other'::text
      ]
    )
  ),
  note text NULL,
  status text NOT NULL DEFAULT 'open' CHECK (
    status = ANY (
      ARRAY[
        'open'::text,
        'in_review'::text,
        'actioned'::text,
        'dismissed'::text
      ]
    )
  ),
  reviewer_notes text NULL,
  reviewed_at timestamptz NULL,
  reviewed_by uuid NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT abuse_reports_reporter_not_reported CHECK (reporter_user_id <> reported_user_id),
  CONSTRAINT abuse_reports_note_length CHECK (note IS NULL OR char_length(note) <= 500)
);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_status_created_at
  ON public.abuse_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_thread_created_at
  ON public.abuse_reports (thread_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_reported_user_created_at
  ON public.abuse_reports (reported_user_id, created_at DESC);

ALTER TABLE public.abuse_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own abuse reports" ON public.abuse_reports;
CREATE POLICY "Users can view own abuse reports"
  ON public.abuse_reports
  FOR SELECT
  TO authenticated
  USING (reporter_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own abuse reports" ON public.abuse_reports;
CREATE POLICY "Users can insert own abuse reports"
  ON public.abuse_reports
  FOR INSERT
  TO authenticated
  WITH CHECK (reporter_user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.enforce_shift_shares_update_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if current_setting('tidex.allow_shift_share_abuse_block_update', true) = 'true' then
    return new;
  end if;

  -- Allow trusted maintenance/service-role updates without an auth user.
  if v_uid is null then
    return new;
  end if;

  -- Immutable columns
  if new.id != old.id then
    raise exception 'Cannot modify id column';
  end if;
  if new.owner_id != old.owner_id then
    raise exception 'Cannot modify owner_id column';
  end if;
  if new.viewer_id != old.viewer_id then
    raise exception 'Cannot modify viewer_id column';
  end if;
  if new.created_at != old.created_at then
    raise exception 'Cannot modify created_at column';
  end if;

  -- Viewer updates
  if v_uid = old.viewer_id then
    if new.show_earnings is distinct from old.show_earnings then
      raise exception 'Viewers cannot modify show_earnings column';
    end if;
    if new.owner_muted is distinct from old.owner_muted then
      raise exception 'Viewers cannot modify owner_muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  -- Owner updates
  if v_uid = old.owner_id then
    if new.blocked is distinct from old.blocked then
      raise exception 'Owners cannot modify blocked column';
    end if;
    if new.hidden is distinct from old.hidden then
      raise exception 'Owners cannot modify hidden column';
    end if;
    if new.muted is distinct from old.muted then
      raise exception 'Owners cannot modify muted column';
    end if;
    if new.blocked_by_user_id is distinct from old.blocked_by_user_id then
      raise exception 'Clients cannot modify blocked_by_user_id directly';
    end if;
  end if;

  -- Direct client writes must not set abuse-block state yet.
  if v_uid is not null and new.blocked_by_user_id is distinct from old.blocked_by_user_id then
    raise exception 'Clients cannot modify blocked_by_user_id directly';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_abuse_report(
  p_thread_id uuid,
  p_reported_user_id uuid,
  p_message_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_reason text := lower(btrim(COALESCE(p_reason, '')));
  v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_thread_id IS NULL THEN
    RAISE EXCEPTION 'Thread is required';
  END IF;

  IF p_reported_user_id IS NULL THEN
    RAISE EXCEPTION 'Reported user is required';
  END IF;

  IF p_reported_user_id = v_uid THEN
    RAISE EXCEPTION 'Cannot report yourself';
  END IF;

  IF v_reason NOT IN (
    'harassment_or_bullying',
    'sexual_content',
    'hate_or_discriminatory_content',
    'violence_or_threats',
    'spam',
    'inappropriate_profile_or_conduct',
    'other'
  ) THEN
    RAISE EXCEPTION 'Invalid abuse report reason';
  END IF;

  IF v_note IS NOT NULL AND char_length(v_note) > 500 THEN
    RAISE EXCEPTION 'Report note must be 500 characters or less';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = v_uid
      AND tm.status = 'active'
      AND tm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Thread not accessible';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.thread_memberships tm
    WHERE tm.thread_id = p_thread_id
      AND tm.user_id = p_reported_user_id
      AND tm.status = 'active'
      AND tm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reported user is not a member of this thread';
  END IF;

  IF p_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.messages m
    WHERE m.id = p_message_id
      AND m.thread_id = p_thread_id
      AND m.sender_user_id = p_reported_user_id
  ) THEN
    RAISE EXCEPTION 'Reported message is invalid for this thread and user';
  END IF;

  INSERT INTO public.abuse_reports (
    reporter_user_id,
    reported_user_id,
    thread_id,
    message_id,
    reason,
    note
  )
  VALUES (
    v_uid,
    p_reported_user_id,
    p_thread_id,
    p_message_id,
    v_reason,
    v_note
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) FROM public;
REVOKE EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.block_user_pair(p_other_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
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

  PERFORM set_config('tidex.allow_shift_share_abuse_block_update', 'true', true);

  UPDATE public.shift_shares ss
  SET hidden = true,
      blocked_by_user_id = v_uid
  WHERE (ss.owner_id = v_uid AND ss.viewer_id = p_other_user_id)
     OR (ss.owner_id = p_other_user_id AND ss.viewer_id = v_uid);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM public;
REVOKE EXECUTE ON FUNCTION public.block_user_pair(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.block_user_pair(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.queue_abuse_report_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_reporter_name text;
  v_summary text;
BEGIN
  SELECT COALESCE(
    au.raw_user_meta_data->>'full_name',
    au.raw_user_meta_data->>'name',
    au.email,
    'Tidex user'
  )
  INTO v_reporter_name
  FROM auth.users au
  WHERE au.id = NEW.reporter_user_id;

  v_summary := CASE
    WHEN NEW.message_id IS NULL THEN 'reporterte en samtale'
    ELSE 'rapporterte en melding'
  END;

  INSERT INTO internal.notifications_outbox (
    owner_id,
    recipient_id,
    notification_type,
    title,
    body,
    data_payload,
    idempotency_key,
    due_at,
    status
  )
  SELECT
    NEW.reporter_user_id,
    admin_user.id,
    'abuse_report_submitted',
    'Ny misbruksrapport',
    v_reporter_name || ' ' || v_summary,
    jsonb_build_object(
      'type', 'abuse_report_submitted',
      'report_id', NEW.id,
      'thread_id', NEW.thread_id,
      'message_id', NEW.message_id,
      'reported_user_id', NEW.reported_user_id,
      'deeplink', 'https://app.tidex.no/settings/admin?tab=reports&reportId=' || NEW.id::text
    ),
    'abuse_report:' || NEW.id::text || ':' || admin_user.id::text,
    NOW(),
    'pending'
  FROM auth.users admin_user
  WHERE admin_user.raw_app_meta_data->>'role' = 'admin'
    AND admin_user.deleted_at IS NULL
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_abuse_report_notify ON public.abuse_reports;
CREATE TRIGGER on_abuse_report_notify
  AFTER INSERT ON public.abuse_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.queue_abuse_report_notification();
