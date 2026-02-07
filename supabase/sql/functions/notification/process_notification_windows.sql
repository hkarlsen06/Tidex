-- Function: process_notification_windows
-- Description: Processes completed 15-minute windows and fans out to notifications_outbox
-- Used by: run_notification_workers (called by pg_cron every 15 minutes)
-- Schema: internal
--
-- This function processes notification windows where window_end has passed (window_start + 15 min).
-- For each window, it:
--   1. Marks the window as 'processing'
--   2. Computes net effects from shift_operations JSONB (or falls back to stored counts)
--   3. Builds LOCALIZED notification messages based on each recipient's locale
--   4. Fans out to each non-muted recipient with shared_shifts_enabled
--   5. Includes 'changes' array with shift IDs for app highlighting
--   6. Marks the window as 'finalized'
--
-- Returns:
--   windows_processed: Number of windows processed
--   outbox_rows_created: Number of outbox rows inserted
--
-- Data payload includes:
--   - changes: Array of {shift_id, date, op} for app highlighting
--   - shift_dates: Legacy array of dates for backward compatibility
--   - added_count, updated_count, deleted_count: Net counts

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
      -- Title: "{first name} - Last 15 minutes:" / "{first name} - Siste 15 minutter:"
      -- Use only the first word of the name for brevity in notifications
      split_part(v_owner_name, ' ', 1) || CASE
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
      AND ss.owner_muted = FALSE
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

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION internal.process_notification_windows TO service_role;
