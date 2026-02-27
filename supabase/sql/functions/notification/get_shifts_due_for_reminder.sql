-- Function: get_shifts_due_for_reminder
-- Description: Returns shifts that are due for reminder notifications based on user preferences
-- Used by: process-shift-reminders edge function

CREATE OR REPLACE FUNCTION public.get_shifts_due_for_reminder()
 RETURNS TABLE(
   user_id uuid,
   shift_instance_key text,
   shift_date date,
   start_time time without time zone,
   end_time time without time zone,
   reminder_minutes integer,
   minutes_until_shift integer,
   job_id uuid,
   job_name text
 )
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  cron_interval_minutes CONSTANT INTEGER := 1;  -- Cron runs every 1 minute
BEGIN
  RETURN QUERY
  WITH user_prefs AS (
    SELECT DISTINCT
      pd.user_id,
      COALESCE(np.shift_reminders_enabled, true) AS enabled,
      COALESCE(np.shift_reminder_minutes_array, ARRAY[300]) AS reminder_mins_array
    FROM internal.push_devices pd
    LEFT JOIN public.notification_preferences np ON np.user_id = pd.user_id
    WHERE COALESCE(np.shift_reminders_enabled, true) = true
  ),
  user_reminders AS (
    SELECT
      up.user_id,
      unnest(up.reminder_mins_array) AS reminder_mins
    FROM user_prefs up
  ),
  single_shifts AS (
    SELECT
      us.user_id,
      us.job_id,
      COALESCE(j.name, 'Jobb') AS job_name,
      'single:' || us.id || ':' || us.shift_date || ':' || us.start_time AS instance_key,
      us.shift_date,
      us.start_time::TIME AS start_time,
      us.end_time::TIME AS end_time,
      ((us.shift_date::TEXT || ' ' || us.start_time)::TIMESTAMP AT TIME ZONE 'Europe/Oslo') AS shift_start_ts
    FROM public.user_shifts us
    LEFT JOIN public.jobs j ON j.id = us.job_id
    WHERE us.shift_date >= CURRENT_DATE
      AND us.shift_date <= CURRENT_DATE + INTERVAL '3 days'
      AND us.deleted_at IS NULL
  ),
  shift_reminders AS (
    SELECT
      ss.user_id,
      ss.job_id,
      ss.job_name,
      ss.instance_key,
      ss.shift_date,
      ss.start_time,
      ss.end_time,
      ss.shift_start_ts,
      ur.reminder_mins
    FROM single_shifts ss
    JOIN user_reminders ur ON ur.user_id = ss.user_id
  ),
  due_shifts AS (
    SELECT
      sr.*,
      EXTRACT(EPOCH FROM (sr.shift_start_ts - NOW())) / 60 AS mins_until
    FROM shift_reminders sr
    WHERE sr.shift_start_ts > NOW()
  )
  SELECT
    ds.user_id,
    ds.instance_key AS shift_instance_key,
    ds.shift_date,
    ds.start_time,
    ds.end_time,
    ds.reminder_mins AS reminder_minutes,
    CEIL(ds.mins_until)::INTEGER AS minutes_until_shift,
    ds.job_id,
    ds.job_name
  FROM due_shifts ds
  WHERE ds.mins_until <= ds.reminder_mins
    AND ds.mins_until >= (ds.reminder_mins - cron_interval_minutes);
END;
$function$;
