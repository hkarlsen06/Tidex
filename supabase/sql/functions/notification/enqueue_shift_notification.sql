-- Function: enqueue_shift_notification
-- Description: RPC for iOS app to enqueue shift notifications after syncing
-- Used by: iOS SyncCoordinator after shift create/update/delete operations
-- Schema: public (to allow RPC call from authenticated users)
--
-- This function allows the iOS app to trigger notifications to shared users
-- when shifts are created, updated, or deleted. It matches the behavior of
-- the web app's enqueueShiftNotification() in lib/notifications/enqueue.ts.
--
-- Key features:
-- - Localizes messages based on each recipient's locale preference
-- - Same-day shifts: immediate delivery via notifications_outbox
-- - Future shifts: 15-minute batched delivery via notification_time_windows
-- - Idempotent via mutation_id parameter
--
-- Parameters:
--   p_shift_id: UUID of the shift
--   p_shift_date: Date string in 'YYYY-MM-DD' format
--   p_start_time: Start time in 'HH:MM' or 'HH:MM:SS' format
--   p_end_time: End time in 'HH:MM' or 'HH:MM:SS' format
--   p_event_type: 'added', 'updated', or 'deleted'
--   p_mutation_id: Unique ID for this mutation (for idempotency)
--   p_old_start_time: (Optional) Previous start time for update events
--   p_old_end_time: (Optional) Previous end time for update events
--
-- Returns:
--   JSON object with:
--     - queued: Number of notifications queued
--     - delivery: 'immediate', 'batched', or 'none'
--     - error: (Only if failed) Error message

CREATE OR REPLACE FUNCTION public.enqueue_shift_notification(
  p_shift_id UUID,
  p_shift_date TEXT,
  p_start_time TEXT,
  p_end_time TEXT,
  p_event_type TEXT,
  p_mutation_id TEXT,
  p_old_start_time TEXT DEFAULT NULL,
  p_old_end_time TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_owner_id UUID;
  v_owner_name TEXT;
  v_shift_date DATE;
  v_today_oslo DATE;
  v_is_today BOOLEAN;
  v_viewer RECORD;
  v_locale TEXT;
  v_title TEXT;
  v_body TEXT;
  v_rows_queued INT := 0;
  v_row_count INT;
  v_delivery_type TEXT;
  v_window_start TIMESTAMPTZ;
BEGIN
  -- Get the calling user's ID
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated', 'queued', 0);
  END IF;

  -- Verify caller owns this shift (except for deleted shifts which may not exist)
  IF p_event_type != 'deleted' THEN
    IF NOT EXISTS (
      SELECT 1 FROM user_shifts
      WHERE id = p_shift_id AND user_id = v_owner_id AND deleted_at IS NULL
    ) THEN
      RETURN jsonb_build_object('error', 'Shift not found or not owned', 'queued', 0);
    END IF;
  END IF;

  -- Get owner name
  SELECT COALESCE(
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'name',
    email,
    'Someone'
  ) INTO v_owner_name
  FROM auth.users WHERE id = v_owner_id;

  IF v_owner_name IS NULL THEN
    v_owner_name := 'Someone';
  END IF;

  -- Parse shift date
  v_shift_date := p_shift_date::DATE;

  -- Get today's date in Oslo timezone
  v_today_oslo := (now() AT TIME ZONE 'Europe/Oslo')::DATE;
  v_is_today := (v_shift_date = v_today_oslo);

  -- Get eligible viewers (non-muted with shared_shifts_enabled)
  -- Loop through each viewer to generate localized messages
  FOR v_viewer IN
    SELECT
      ss.viewer_id,
      COALESCE(u.raw_user_meta_data->>'locale', 'en') as locale
    FROM shift_shares ss
    JOIN auth.users u ON u.id = ss.viewer_id
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = v_owner_id
      AND ss.muted = FALSE
      AND COALESCE(np.shared_shifts_enabled, TRUE) = TRUE
  LOOP
    v_locale := v_viewer.locale;

    -- Build localized message
    v_title := internal.build_shift_title(v_owner_name, p_event_type, v_locale);
    v_body := internal.build_shift_body(
      v_shift_date,
      p_start_time,
      p_end_time,
      v_is_today,
      v_locale,
      p_old_start_time,
      p_old_end_time
    );

    IF v_is_today THEN
      -- SAME-DAY: Insert directly to outbox for immediate delivery
      INSERT INTO internal.notifications_outbox (
        owner_id,
        recipient_id,
        notification_type,
        due_at,
        title,
        body,
        data_payload,
        idempotency_key
      ) VALUES (
        v_owner_id,
        v_viewer.viewer_id,
        'shared_shift_' || p_event_type,
        now(),
        v_title,
        v_body,
        jsonb_build_object(
          'type', 'shared_shift_' || p_event_type,
          'owner_id', v_owner_id,
          'shift_dates', jsonb_build_array(p_shift_date)
        ),
        'shift:' || p_shift_id || ':' || p_event_type || ':' || v_viewer.viewer_id || ':' || p_mutation_id
      )
      ON CONFLICT (idempotency_key) DO NOTHING;

      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_rows_queued := v_rows_queued + v_row_count;
      v_delivery_type := 'immediate';
    ELSE
      -- NON-TODAY: Upsert into time window for batched delivery
      -- Calculate window start (15-minute aligned)
      v_window_start := date_trunc('hour', now()) +
        (floor(EXTRACT(MINUTE FROM now()) / 15) * INTERVAL '15 minutes');

      -- Use existing upsert function
      PERFORM internal.upsert_notification_window(
        v_owner_id,
        v_window_start,
        p_event_type,
        v_shift_date
      );

      v_rows_queued := v_rows_queued + 1;
      v_delivery_type := 'batched';
    END IF;
  END LOOP;

  -- Trigger edge function for immediate delivery if we added outbox rows
  IF v_is_today AND v_rows_queued > 0 THEN
    PERFORM net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url')
             || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' ||
          (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN jsonb_build_object(
    'queued', v_rows_queued,
    'delivery', COALESCE(v_delivery_type, 'none')
  );
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.enqueue_shift_notification TO authenticated;
