-- Migration: notification_title_and_date_aggregation
-- Description:
--   1. Update batched notification title to include "- Last 15 minutes:" / "- Siste 15 minutter:"
--   2. Fix net-effect tracking to aggregate by DATE instead of shift_id
--      - Before: delete shift A + add shift B on same date = "deleted 1, added 1"
--      - After: delete shift A + add shift B on same date = "updated 1"

-- ============================================================================
-- Update upsert_notification_window to key by DATE instead of shift_id
-- ============================================================================

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

-- ============================================================================
-- Update process_notification_windows with new title and changes array format
-- ============================================================================

CREATE OR REPLACE FUNCTION internal.process_notification_windows()
RETURNS TABLE(windows_processed INT, outbox_rows_created INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window RECORD;
  v_owner_name TEXT;
  v_windows_processed INT := 0;
  v_outbox_created INT := 0;
  v_rows_inserted INT;
  v_window_end TIMESTAMPTZ;
  v_added_count INT;
  v_updated_count INT;
  v_deleted_count INT;
  v_changes JSONB;
  v_has_operations BOOLEAN;
BEGIN
  -- Process windows where window_end has passed (window_start + 15 min)
  FOR v_window IN
    SELECT *
    FROM internal.notification_time_windows
    WHERE status = 'pending'
      AND window_start + INTERVAL '15 minutes' <= now()
    ORDER BY window_start
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Mark as processing
    UPDATE internal.notification_time_windows
    SET status = 'processing'
    WHERE id = v_window.id;

    -- Calculate window end for due_at
    v_window_end := v_window.window_start + INTERVAL '15 minutes';

    -- Check if we have shift_operations data (new format) or just counts (legacy)
    v_has_operations := (v_window.shift_operations IS NOT NULL AND v_window.shift_operations != '{}'::jsonb);

    IF v_has_operations THEN
      -- Compute counts from shift_operations (net effects)
      SELECT
        COUNT(*) FILTER (WHERE value->>'op' = 'added'),
        COUNT(*) FILTER (WHERE value->>'op' = 'updated'),
        COUNT(*) FILTER (WHERE value->>'op' = 'deleted')
      INTO v_added_count, v_updated_count, v_deleted_count
      FROM jsonb_each(v_window.shift_operations);

      -- Build changes array for app highlighting
      -- Note: key is now DATE, value contains {op, shift_id}
      SELECT jsonb_agg(
        jsonb_build_object(
          'shift_id', value->>'shift_id',
          'date', key,
          'op', value->>'op'
        )
      )
      INTO v_changes
      FROM jsonb_each(v_window.shift_operations);
    ELSE
      -- Fall back to stored counts (legacy data)
      v_added_count := v_window.added_count;
      v_updated_count := v_window.updated_count;
      v_deleted_count := v_window.deleted_count;
      v_changes := NULL;
    END IF;

    -- Skip if no net changes (all operations cancelled out)
    IF v_added_count = 0 AND v_updated_count = 0 AND v_deleted_count = 0 THEN
      UPDATE internal.notification_time_windows
      SET status = 'finalized', updated_at = now()
      WHERE id = v_window.id;
      v_windows_processed := v_windows_processed + 1;
      CONTINUE;
    END IF;

    -- Get owner name
    SELECT COALESCE(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name',
      email,
      'Someone'
    ) INTO v_owner_name
    FROM auth.users WHERE id = v_window.owner_id;

    IF v_owner_name IS NULL THEN
      v_owner_name := 'Someone';
    END IF;

    -- Fan out to each non-muted recipient WITH LOCALIZED MESSAGES
    INSERT INTO internal.notifications_outbox (
      owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key
    )
    SELECT
      v_window.owner_id,
      ss.viewer_id,
      'shared_shift_changes',
      v_window_end,
      -- Title: "{name} - Last 15 minutes:" / "{name} - Siste 15 minutter:"
      v_owner_name || CASE
        WHEN COALESCE(u.raw_user_meta_data->>'locale', 'en') IN ('no', 'nb', 'nn')
        THEN ' - Siste 15 minutter:'
        ELSE ' - Last 15 minutes:'
      END,
      -- Body is localized based on recipient's locale
      internal.build_batched_body(
        v_added_count,
        v_updated_count,
        v_deleted_count,
        COALESCE(u.raw_user_meta_data->>'locale', 'en')
      ),
      jsonb_build_object(
        'type', 'shared_shift_changes',
        'owner_id', v_window.owner_id,
        'changes', COALESCE(v_changes, '[]'::jsonb),
        -- Legacy fields for backward compatibility
        'shift_dates', to_jsonb(v_window.affected_dates),
        'added_count', v_added_count,
        'updated_count', v_updated_count,
        'deleted_count', v_deleted_count
      ),
      -- Stable idempotency: owner_id:recipient_id:window_start
      v_window.owner_id || ':' || ss.viewer_id || ':' || v_window.window_start::text
    FROM shift_shares ss
    JOIN auth.users u ON u.id = ss.viewer_id
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = v_window.owner_id
      AND ss.muted = FALSE
      AND COALESCE(np.shared_shifts_enabled, TRUE) = TRUE
    ON CONFLICT (idempotency_key) DO NOTHING;

    GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;
    v_outbox_created := v_outbox_created + v_rows_inserted;

    -- Mark window as finalized
    UPDATE internal.notification_time_windows
    SET status = 'finalized', updated_at = now()
    WHERE id = v_window.id;

    v_windows_processed := v_windows_processed + 1;
  END LOOP;

  RETURN QUERY SELECT v_windows_processed, v_outbox_created;
END;
$$;
