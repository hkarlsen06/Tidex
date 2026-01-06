-- Function: process_notification_windows
-- Description: Processes completed 15-minute windows and fans out to notifications_outbox
-- Used by: run_notification_workers (called by pg_cron every minute)
-- Schema: internal
--
-- This function processes notification windows where window_end has passed (window_start + 15 min).
-- For each window, it:
--   1. Marks the window as 'processing'
--   2. Builds a Norwegian notification message from the aggregated counts
--   3. Fans out to each non-muted recipient with shared_shifts_enabled
--   4. Marks the window as 'finalized'
--
-- Returns:
--   windows_processed: Number of windows processed
--   outbox_rows_created: Number of outbox rows inserted
--
-- Message format examples:
--   Title: "Alvilde"
--   Body: "La til 2 vakter, endret 1 vakt, og slettet 3 vakter"

CREATE OR REPLACE FUNCTION internal.process_notification_windows()
RETURNS TABLE(windows_processed INT, outbox_rows_created INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window RECORD;
  v_owner_name TEXT;
  v_title TEXT;
  v_body TEXT;
  v_action_parts TEXT[];
  v_windows_processed INT := 0;
  v_outbox_created INT := 0;
  v_rows_inserted INT;
  v_window_end TIMESTAMPTZ;
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

    -- Get owner name
    SELECT COALESCE(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name',
      email,
      'Noen'
    ) INTO v_owner_name
    FROM auth.users WHERE id = v_window.owner_id;

    IF v_owner_name IS NULL THEN
      v_owner_name := 'Noen';
    END IF;

    -- Title is just the owner name
    v_title := v_owner_name;

    -- Build Norwegian body message
    -- Order: added, updated, deleted
    -- Format: "La til 2 vakter, endret 1 vakt, og slettet 3 vakter"
    v_action_parts := '{}';

    IF v_window.added_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'la til ' || v_window.added_count ||
        CASE WHEN v_window.added_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    IF v_window.updated_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'endret ' || v_window.updated_count ||
        CASE WHEN v_window.updated_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    IF v_window.deleted_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'slettet ' || v_window.deleted_count ||
        CASE WHEN v_window.deleted_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    -- Build body with Norwegian conjunction rules
    IF array_length(v_action_parts, 1) = 1 THEN
      -- Capitalize first letter
      v_body := initcap(substring(v_action_parts[1] from 1 for 1)) || substring(v_action_parts[1] from 2);
    ELSIF array_length(v_action_parts, 1) = 2 THEN
      v_body := initcap(substring(v_action_parts[1] from 1 for 1)) || substring(v_action_parts[1] from 2) ||
                ' og ' || v_action_parts[2];
    ELSE
      v_body := initcap(substring(v_action_parts[1] from 1 for 1)) || substring(v_action_parts[1] from 2) ||
                ', ' || v_action_parts[2] || ', og ' || v_action_parts[3];
    END IF;

    -- Fan out to each non-muted recipient
    INSERT INTO internal.notifications_outbox (
      owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key
    )
    SELECT
      v_window.owner_id,
      ss.viewer_id,
      'shared_shift_changes',
      v_window_end,  -- due_at = window_end for clarity
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'shared_shift_changes',
        'owner_id', v_window.owner_id,
        'shift_dates', to_jsonb(v_window.affected_dates),  -- JSON array, not comma string
        'added_count', v_window.added_count,
        'updated_count', v_window.updated_count,
        'deleted_count', v_window.deleted_count
      ),
      -- Stable idempotency: owner_id:recipient_id:window_start
      v_window.owner_id || ':' || ss.viewer_id || ':' || v_window.window_start::text
    FROM shift_shares ss
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

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION internal.process_notification_windows TO service_role;
