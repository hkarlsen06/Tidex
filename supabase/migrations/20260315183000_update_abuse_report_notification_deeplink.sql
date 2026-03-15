-- Update abuse report notifications to open the native admin reports flow.

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
      'deeplink', 'tidex://admin?tab=reports&reportId=' || NEW.id::text
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
