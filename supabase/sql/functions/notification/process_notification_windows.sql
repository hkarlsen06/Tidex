-- Function: process_notification_windows
-- Description: Processes completed 15-minute windows and fans out to notifications_outbox
-- Used by: run_notification_workers (called by pg_cron every minute)
-- Schema: internal
--
-- This function processes notification windows where window_end has passed (window_start + 15 min).
-- For each window, it:
--   1. Marks the window as 'processing'
--   2. Builds LOCALIZED notification messages based on each recipient's locale
--   3. Fans out to each non-muted recipient with shared_shifts_enabled
--   4. Marks the window as 'finalized'
--
-- Returns:
--   windows_processed: Number of windows processed
--   outbox_rows_created: Number of outbox rows inserted
--
-- Message format examples (Norwegian):
--   Title: "Alvilde"
--   Body: "La til 2 vakter, endret 1 vakt, og slettet 3 vakter"
--
-- Message format examples (English):
--   Title: "Alvilde"
--   Body: "Added 2 shifts, updated 1 shift, and deleted 3 shifts"

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

    -- Fan out to each non-muted recipient WITH LOCALIZED MESSAGES
    -- Each recipient gets a message in their preferred locale
    INSERT INTO internal.notifications_outbox (
      owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key
    )
    SELECT
      v_window.owner_id,
      ss.viewer_id,
      'shared_shift_changes',
      v_window_end,
      -- Title is just owner name (same in both languages)
      v_owner_name,
      -- Body is localized based on recipient's locale (defaults to 'en' for English)
      internal.build_batched_body(
        v_window.added_count,
        v_window.updated_count,
        v_window.deleted_count,
        COALESCE(u.raw_user_meta_data->>'locale', 'en')
      ),
      jsonb_build_object(
        'type', 'shared_shift_changes',
        'owner_id', v_window.owner_id,
        'shift_dates', to_jsonb(v_window.affected_dates),
        'added_count', v_window.added_count,
        'updated_count', v_window.updated_count,
        'deleted_count', v_window.deleted_count
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

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION internal.process_notification_windows TO service_role;
