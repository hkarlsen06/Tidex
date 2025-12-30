-- Migration: Create function to find shifts due for reminder notifications
-- Returns shifts within the narrow "due" window based on user preferences

CREATE OR REPLACE FUNCTION get_shifts_due_for_reminder()
RETURNS TABLE (
  user_id UUID,
  shift_instance_key TEXT,
  shift_date DATE,
  start_time TEXT,
  end_time TEXT,
  reminder_minutes INTEGER,
  minutes_until_shift INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  cron_interval_minutes INTEGER := 10;  -- Must match cron schedule
BEGIN
  RETURN QUERY
  WITH user_prefs AS (
    -- Get all users with push devices, using COALESCE for defaults
    -- This ensures users without a notification_preferences row still get reminders
    SELECT DISTINCT
      pd.user_id,
      COALESCE(np.shift_reminders_enabled, true) AS enabled,
      COALESCE(np.shift_reminder_minutes, 300) AS reminder_mins
    FROM push_devices pd
    LEFT JOIN notification_preferences np ON np.user_id = pd.user_id
    WHERE COALESCE(np.shift_reminders_enabled, true) = true
  ),
  -- Get single shifts with explicit Europe/Oslo timezone
  -- shift_start_ts is timestamptz, so we compare against NOW() (also timestamptz) directly
  single_shifts AS (
    SELECT
      us.user_id,
      'single:' || us.id || ':' || us.shift_date || ':' || us.start_time AS instance_key,
      us.shift_date,
      us.start_time,
      us.end_time,
      up.reminder_mins,
      -- Convert to timestamptz in Europe/Oslo timezone
      ((us.shift_date::TEXT || ' ' || us.start_time)::TIMESTAMP AT TIME ZONE 'Europe/Oslo') AS shift_start_ts
    FROM user_shifts us
    JOIN user_prefs up ON up.user_id = us.user_id
    WHERE us.shift_date >= CURRENT_DATE
      AND us.shift_date <= CURRENT_DATE + INTERVAL '3 days'  -- +3 days for DST/cron safety margin
  ),
  -- Calculate minutes until shift
  -- Both shift_start_ts (timestamptz) and NOW() (timestamptz) are the same type
  due_shifts AS (
    SELECT
      ss.*,
      EXTRACT(EPOCH FROM (ss.shift_start_ts - NOW())) / 60 AS mins_until
    FROM single_shifts ss
    WHERE ss.shift_start_ts > NOW()  -- Shift hasn't started
  )
  SELECT
    ds.user_id,
    ds.instance_key,
    ds.shift_date,
    ds.start_time,
    ds.end_time,
    ds.reminder_mins,
    CEIL(ds.mins_until)::INTEGER
  FROM due_shifts ds
  WHERE
    -- Narrow window: only send when within [reminder_minutes - cron_interval, reminder_minutes]
    -- Using >= on lower bound to avoid missing shifts that land exactly on the boundary
    ds.mins_until <= ds.reminder_mins
    AND ds.mins_until >= (ds.reminder_mins - cron_interval_minutes);
END;
$$;

COMMENT ON FUNCTION get_shifts_due_for_reminder IS
  'Returns shifts that are due for reminder notifications. Uses a narrow window to avoid early sends.';

-- Grant execute to service role (Edge Function uses this)
GRANT EXECUTE ON FUNCTION get_shifts_due_for_reminder TO service_role;
