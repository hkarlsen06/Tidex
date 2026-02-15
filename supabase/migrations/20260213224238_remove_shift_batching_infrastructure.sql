-- Remove shift-change notification batching infrastructure
-- All shift-change notifications have been removed; only direct notifications remain.

-- 1. Unschedule the 15-minute worker cron
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'process-shift-notifications';

-- 2. Drop public/iOS entrypoint and worker pipeline
DROP FUNCTION IF EXISTS public.enqueue_shift_notification(uuid, text, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.run_notification_workers();
DROP FUNCTION IF EXISTS internal.process_notification_windows();
DROP FUNCTION IF EXISTS internal.upsert_notification_window(uuid, timestamptz, text, date, uuid);

-- 3. Drop localization helpers only used by removed shift pipeline
DROP FUNCTION IF EXISTS internal.format_shift_date(date, boolean, text);
DROP FUNCTION IF EXISTS internal.build_shift_title(text, text, text);
DROP FUNCTION IF EXISTS internal.build_shift_body(date, text, text, boolean, text, text, text);
DROP FUNCTION IF EXISTS internal.build_batched_body(integer, integer, integer, text);

-- 4. Drop aggregation table
DROP TABLE IF EXISTS internal.notification_time_windows;

-- 5. Update prepare_user_for_deletion to remove reference to dropped table
CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal
AS $$
BEGIN
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  INSERT INTO internal.admin_audit_log (
    admin_id, action, target_user_id, admin_email, target_email, metadata
  )
  SELECT
    target_user_id, 'user_deleted_self', target_user_id,
    COALESCE(u.email, u.phone, 'unknown'),
    COALESCE(u.email, u.phone, 'unknown'),
    jsonb_build_object('deletion_type', 'self_service', 'deleted_at', now())
  FROM auth.users u
  WHERE u.id = target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.prepare_user_for_deletion(uuid) TO authenticated;

-- 6. Update cleanup cron to only clean outbox (notification_time_windows no longer exists)
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cleanup-shift-notification-events';
SELECT cron.schedule(
  'cleanup-shift-notification-events',
  '0 4 * * *',
  $$DELETE FROM internal.notifications_outbox WHERE status = 'sent' AND created_at < NOW() - INTERVAL '3 days';$$
);;
