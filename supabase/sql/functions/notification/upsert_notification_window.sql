-- Function: upsert_notification_window
-- Description: Atomically upserts a shift mutation into a 15-minute notification window
-- Used by: lib/notifications/enqueue.ts (enqueueShiftNotification)
-- Schema: internal
--
-- This function aggregates non-today shift mutations into time windows for batched delivery.
-- Windows are clock-aligned (:00, :15, :30, :45) and processed when they end.
--
-- Parameters:
--   p_owner_id: UUID of the shift owner
--   p_window_start: Start of the 15-minute window (TIMESTAMPTZ)
--   p_event_type: Type of mutation ('added', 'updated', 'deleted')
--   p_shift_date: Date of the affected shift (DATE)
--
-- Behavior:
--   - Creates new window row if none exists for owner+window_start
--   - Updates existing window: increments count, adds date to array (up to 31 dates)
--   - Sets truncated_dates flag if date array reaches 31

CREATE OR REPLACE FUNCTION internal.upsert_notification_window(
  p_owner_id UUID,
  p_window_start TIMESTAMPTZ,
  p_event_type TEXT,
  p_shift_date DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
BEGIN
  INSERT INTO notification_time_windows (
    owner_id, window_start,
    added_count, updated_count, deleted_count,
    affected_dates
  )
  VALUES (
    p_owner_id, p_window_start,
    CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
    ARRAY[p_shift_date]
  )
  ON CONFLICT (owner_id, window_start) DO UPDATE SET
    added_count = notification_time_windows.added_count +
      CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
    updated_count = notification_time_windows.updated_count +
      CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
    deleted_count = notification_time_windows.deleted_count +
      CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
    affected_dates = CASE
      WHEN array_length(notification_time_windows.affected_dates, 1) >= 31 THEN
        notification_time_windows.affected_dates
      WHEN p_shift_date = ANY(notification_time_windows.affected_dates) THEN
        notification_time_windows.affected_dates
      ELSE
        array_append(notification_time_windows.affected_dates, p_shift_date)
    END,
    truncated_dates = CASE
      WHEN array_length(notification_time_windows.affected_dates, 1) >= 31 THEN TRUE
      ELSE notification_time_windows.truncated_dates
    END,
    updated_at = now();
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION internal.upsert_notification_window TO service_role;
