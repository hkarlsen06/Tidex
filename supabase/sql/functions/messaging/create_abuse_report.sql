-- Function: create_abuse_report
-- Description: Create a user-generated-content abuse report for a thread or message.

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
