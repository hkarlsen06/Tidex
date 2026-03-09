-- Remove obsolete server-side shift reminder infrastructure.
-- Shift reminders are scheduled locally in the iOS app.

DO $$
DECLARE
  v_job_id bigint;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname IN ('process-shift-reminders', 'cleanup-shift-reminders-sent')
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.get_shifts_due_for_reminder();
DROP TABLE IF EXISTS public.shift_reminders_sent;
