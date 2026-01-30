-- Function: upsert_notification_window
-- Description: Atomically upserts a shift mutation into a 15-minute notification window
-- Used by: lib/notifications/enqueue.ts (enqueueShiftNotification), iOS RPC
-- Schema: internal
--
-- This function aggregates non-today shift mutations into time windows for batched delivery.
-- Windows are clock-aligned (:00, :15, :30, :45) and processed when they end.
--
-- Net-effect state machine (keyed by DATE, not shift_id):
-- If multiple operations happen on the same date, they're aggregated:
-- | Current | + Operation | = Result |
-- |---------|-------------|----------|
-- | (none)  | added       | added    |
-- | (none)  | updated     | updated  |
-- | (none)  | deleted     | deleted  |
-- | added   | updated     | added    | (edit absorbed)
-- | added   | deleted     | null     | (cancels out)
-- | updated | updated     | updated  | (deduplicated)
-- | updated | deleted     | deleted  |
-- | deleted | added       | updated  | (re-created, e.g., delete old shift + add new shift)
--
-- Parameters:
--   p_owner_id: UUID of the shift owner
--   p_window_start: Start of the 15-minute window (TIMESTAMPTZ)
--   p_event_type: Type of mutation ('added', 'updated', 'deleted')
--   p_shift_date: Date of the affected shift (DATE)
--   p_shift_id: UUID of the shift (for net-effect tracking)
--
-- Behavior:
--   - If shift_id provided: tracks per-shift operations in JSONB for net-effect calculation
--   - If no shift_id: falls back to legacy count-based tracking

CREATE OR REPLACE FUNCTION internal.upsert_notification_window(
  p_owner_id UUID,
  p_window_start TIMESTAMPTZ,
  p_event_type TEXT,
  p_shift_date DATE,
  p_shift_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
DECLARE
  v_existing_op TEXT;
  v_new_op TEXT;
  v_shift_key TEXT;
BEGIN
  -- If no shift_id provided, fall back to legacy behavior (just update counts)
  IF p_shift_id IS NULL THEN
    INSERT INTO notification_time_windows (
      owner_id, window_start,
      added_count, updated_count, deleted_count,
      affected_dates, shift_operations
    )
    VALUES (
      p_owner_id, p_window_start,
      CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
      CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
      CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
      ARRAY[p_shift_date],
      '{}'::jsonb
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
    RETURN;
  END IF;

  -- With shift_id: use state machine for net-effect tracking
  -- KEY BY DATE (not shift_id) so delete+add on same date = updated
  v_shift_key := p_shift_date::text;

  -- Get existing operation for this DATE (if any)
  SELECT shift_operations->>v_shift_key INTO v_existing_op
  FROM notification_time_windows
  WHERE owner_id = p_owner_id AND window_start = p_window_start;

  -- Apply state machine to determine net operation
  IF v_existing_op IS NULL THEN
    -- No existing row or no operation for this date
    v_new_op := p_event_type;
  ELSE
    -- Parse existing op (stored as JSON object with "op" and "shift_id" keys)
    SELECT (shift_operations->v_shift_key->>'op') INTO v_existing_op
    FROM notification_time_windows
    WHERE owner_id = p_owner_id AND window_start = p_window_start;

    IF v_existing_op IS NULL THEN
      v_new_op := p_event_type;
    ELSE
      -- State machine transitions
      CASE v_existing_op
        WHEN 'added' THEN
          CASE p_event_type
            WHEN 'updated' THEN v_new_op := 'added';   -- added + updated = added (edit absorbed)
            WHEN 'deleted' THEN v_new_op := NULL;       -- added + deleted = nothing (cancels out)
            ELSE v_new_op := p_event_type;
          END CASE;
        WHEN 'updated' THEN
          CASE p_event_type
            WHEN 'updated' THEN v_new_op := 'updated'; -- updated + updated = updated (dedupe)
            WHEN 'deleted' THEN v_new_op := 'deleted'; -- updated + deleted = deleted
            ELSE v_new_op := p_event_type;
          END CASE;
        WHEN 'deleted' THEN
          CASE p_event_type
            WHEN 'added' THEN v_new_op := 'updated';   -- deleted + added = updated (re-created)
            ELSE v_new_op := p_event_type;
          END CASE;
        ELSE
          v_new_op := p_event_type;
      END CASE;
    END IF;
  END IF;

  -- Upsert the window with new shift operation (keyed by date)
  INSERT INTO notification_time_windows (
    owner_id, window_start,
    added_count, updated_count, deleted_count,
    affected_dates, shift_operations
  )
  VALUES (
    p_owner_id, p_window_start,
    0, 0, 0, -- Counts will be computed from shift_operations at processing time
    ARRAY[p_shift_date],
    CASE
      WHEN v_new_op IS NULL THEN '{}'::jsonb
      ELSE jsonb_build_object(v_shift_key, jsonb_build_object('op', v_new_op, 'shift_id', p_shift_id::text))
    END
  )
  ON CONFLICT (owner_id, window_start) DO UPDATE SET
    shift_operations = CASE
      WHEN v_new_op IS NULL THEN
        -- Remove this date from operations (it cancelled out)
        notification_time_windows.shift_operations - v_shift_key
      ELSE
        -- Add or update this date's operation (keeps latest shift_id for highlighting)
        notification_time_windows.shift_operations ||
          jsonb_build_object(v_shift_key, jsonb_build_object('op', v_new_op, 'shift_id', p_shift_id::text))
    END,
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
