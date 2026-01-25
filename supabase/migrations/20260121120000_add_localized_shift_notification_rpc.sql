-- Migration: Add Localized Shift Notification RPC for iOS
--
-- This migration adds:
-- 1. Helper functions for building localized notification messages (Norwegian/English)
-- 2. RPC function for iOS to call after syncing shift changes
-- 3. Updated process_notification_windows function with locale support
--
-- The RPC allows iOS to trigger notifications for shared users when shifts
-- are created, updated, or deleted - matching the behavior of the web app.

-- ============================================================================
-- PHASE 1: Helper Functions for Localized Message Building
-- ============================================================================

-- A. Format a date in the user's locale
-- Returns: "I dag" / "Today" for same-day, or localized date like "mandag 15. januar" / "Monday, January 15"
CREATE OR REPLACE FUNCTION internal.format_shift_date(
  p_shift_date DATE,
  p_is_today BOOLEAN,
  p_locale TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_day_name TEXT;
  v_day INT;
  v_month_name TEXT;
BEGIN
  IF p_is_today THEN
    RETURN CASE WHEN p_locale = 'en' THEN 'Today' ELSE 'I dag' END;
  END IF;

  v_day := EXTRACT(DAY FROM p_shift_date);

  IF p_locale = 'en' THEN
    -- English: "Monday, January 15"
    v_day_name := CASE EXTRACT(DOW FROM p_shift_date)
      WHEN 0 THEN 'Sunday'
      WHEN 1 THEN 'Monday'
      WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday'
      WHEN 4 THEN 'Thursday'
      WHEN 5 THEN 'Friday'
      WHEN 6 THEN 'Saturday'
    END;
    v_month_name := CASE EXTRACT(MONTH FROM p_shift_date)
      WHEN 1 THEN 'January'
      WHEN 2 THEN 'February'
      WHEN 3 THEN 'March'
      WHEN 4 THEN 'April'
      WHEN 5 THEN 'May'
      WHEN 6 THEN 'June'
      WHEN 7 THEN 'July'
      WHEN 8 THEN 'August'
      WHEN 9 THEN 'September'
      WHEN 10 THEN 'October'
      WHEN 11 THEN 'November'
      WHEN 12 THEN 'December'
    END;
    RETURN v_day_name || ', ' || v_month_name || ' ' || v_day;
  ELSE
    -- Norwegian: "mandag 15. januar"
    v_day_name := CASE EXTRACT(DOW FROM p_shift_date)
      WHEN 0 THEN 'søndag'
      WHEN 1 THEN 'mandag'
      WHEN 2 THEN 'tirsdag'
      WHEN 3 THEN 'onsdag'
      WHEN 4 THEN 'torsdag'
      WHEN 5 THEN 'fredag'
      WHEN 6 THEN 'lørdag'
    END;
    v_month_name := CASE EXTRACT(MONTH FROM p_shift_date)
      WHEN 1 THEN 'januar'
      WHEN 2 THEN 'februar'
      WHEN 3 THEN 'mars'
      WHEN 4 THEN 'april'
      WHEN 5 THEN 'mai'
      WHEN 6 THEN 'juni'
      WHEN 7 THEN 'juli'
      WHEN 8 THEN 'august'
      WHEN 9 THEN 'september'
      WHEN 10 THEN 'oktober'
      WHEN 11 THEN 'november'
      WHEN 12 THEN 'desember'
    END;
    RETURN v_day_name || ' ' || v_day || '. ' || v_month_name;
  END IF;
END;
$$;


-- B. Build localized title for a single shift event
-- Returns: "{ownerName} added a shift" / "{ownerName} la til en vakt"
CREATE OR REPLACE FUNCTION internal.build_shift_title(
  p_owner_name TEXT,
  p_event_type TEXT,
  p_locale TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_locale = 'en' THEN
    RETURN p_owner_name || CASE p_event_type
      WHEN 'added' THEN ' added a shift'
      WHEN 'updated' THEN ' updated a shift'
      WHEN 'deleted' THEN ' deleted a shift'
      ELSE ' changed a shift'
    END;
  ELSE
    RETURN p_owner_name || CASE p_event_type
      WHEN 'added' THEN ' la til en vakt'
      WHEN 'updated' THEN ' endret en vakt'
      WHEN 'deleted' THEN ' slettet en vakt'
      ELSE ' endret en vakt'
    END;
  END IF;
END;
$$;


-- C. Build localized body for a single shift event
-- Returns: "Today 08:00–16:00" with optional "(was 07:00–15:00)" for updates
CREATE OR REPLACE FUNCTION internal.build_shift_body(
  p_shift_date DATE,
  p_start_time TEXT,
  p_end_time TEXT,
  p_is_today BOOLEAN,
  p_locale TEXT,
  p_old_start_time TEXT DEFAULT NULL,
  p_old_end_time TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_date_part TEXT;
  v_time_str TEXT;
  v_old_time_str TEXT;
  v_start TEXT;
  v_end TEXT;
  v_old_start TEXT;
  v_old_end TEXT;
BEGIN
  -- Normalize time format (handle both HH:MM and HH:MM:SS)
  v_start := LEFT(p_start_time, 5);
  v_end := LEFT(p_end_time, 5);

  v_date_part := internal.format_shift_date(p_shift_date, p_is_today, p_locale);
  v_time_str := v_start || '–' || v_end;

  -- Check if old times differ (for update events)
  IF p_old_start_time IS NOT NULL AND p_old_end_time IS NOT NULL THEN
    v_old_start := LEFT(p_old_start_time, 5);
    v_old_end := LEFT(p_old_end_time, 5);

    IF v_old_start != v_start OR v_old_end != v_end THEN
      IF p_locale = 'en' THEN
        v_old_time_str := '(was ' || v_old_start || '–' || v_old_end || ')';
      ELSE
        v_old_time_str := '(var ' || v_old_start || '–' || v_old_end || ')';
      END IF;
      RETURN v_date_part || ' ' || v_time_str || E'\n' || v_old_time_str;
    END IF;
  END IF;

  RETURN v_date_part || ' ' || v_time_str;
END;
$$;


-- D. Build localized body for batched notifications (15-min window aggregation)
-- Returns: "Added 2 shifts, updated 1 shift, and deleted 3 shifts"
CREATE OR REPLACE FUNCTION internal.build_batched_body(
  p_added_count INT,
  p_updated_count INT,
  p_deleted_count INT,
  p_locale TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_parts TEXT[];
  v_result TEXT;
BEGIN
  v_parts := '{}';

  IF p_locale = 'en' THEN
    -- English
    IF p_added_count > 0 THEN
      v_parts := array_append(v_parts,
        'added ' || p_added_count || CASE WHEN p_added_count = 1 THEN ' shift' ELSE ' shifts' END);
    END IF;
    IF p_updated_count > 0 THEN
      v_parts := array_append(v_parts,
        'updated ' || p_updated_count || CASE WHEN p_updated_count = 1 THEN ' shift' ELSE ' shifts' END);
    END IF;
    IF p_deleted_count > 0 THEN
      v_parts := array_append(v_parts,
        'deleted ' || p_deleted_count || CASE WHEN p_deleted_count = 1 THEN ' shift' ELSE ' shifts' END);
    END IF;

    -- Join with commas and "and"
    IF array_length(v_parts, 1) IS NULL THEN
      v_result := 'No changes';
    ELSIF array_length(v_parts, 1) = 1 THEN
      v_result := initcap(v_parts[1]);
    ELSIF array_length(v_parts, 1) = 2 THEN
      v_result := initcap(v_parts[1]) || ' and ' || v_parts[2];
    ELSE
      v_result := initcap(v_parts[1]) || ', ' || v_parts[2] || ', and ' || v_parts[3];
    END IF;
  ELSE
    -- Norwegian
    IF p_added_count > 0 THEN
      v_parts := array_append(v_parts,
        'la til ' || p_added_count || CASE WHEN p_added_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;
    IF p_updated_count > 0 THEN
      v_parts := array_append(v_parts,
        'endret ' || p_updated_count || CASE WHEN p_updated_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;
    IF p_deleted_count > 0 THEN
      v_parts := array_append(v_parts,
        'slettet ' || p_deleted_count || CASE WHEN p_deleted_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    -- Join with commas and "og"
    IF array_length(v_parts, 1) IS NULL THEN
      v_result := 'Ingen endringer';
    ELSIF array_length(v_parts, 1) = 1 THEN
      v_result := initcap(substring(v_parts[1] from 1 for 1)) || substring(v_parts[1] from 2);
    ELSIF array_length(v_parts, 1) = 2 THEN
      v_result := initcap(substring(v_parts[1] from 1 for 1)) || substring(v_parts[1] from 2) ||
                  ' og ' || v_parts[2];
    ELSE
      v_result := initcap(substring(v_parts[1] from 1 for 1)) || substring(v_parts[1] from 2) ||
                  ', ' || v_parts[2] || ', og ' || v_parts[3];
    END IF;
  END IF;

  RETURN v_result;
END;
$$;


-- ============================================================================
-- PHASE 2: Main RPC Function for iOS
-- ============================================================================

-- E. RPC function that iOS calls after syncing shift changes
CREATE OR REPLACE FUNCTION public.enqueue_shift_notification(
  p_shift_id UUID,
  p_shift_date TEXT,       -- 'YYYY-MM-DD'
  p_start_time TEXT,       -- 'HH:MM' or 'HH:MM:SS'
  p_end_time TEXT,         -- 'HH:MM' or 'HH:MM:SS'
  p_event_type TEXT,       -- 'added', 'updated', 'deleted'
  p_mutation_id TEXT,      -- Unique ID for this mutation (for idempotency)
  p_old_start_time TEXT DEFAULT NULL,  -- For updates: old start time
  p_old_end_time TEXT DEFAULT NULL     -- For updates: old end time
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
      COALESCE(u.raw_user_meta_data->>'locale', 'no') as locale
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


-- ============================================================================
-- PHASE 3: Update process_notification_windows for Locale Support
-- ============================================================================

-- F. Replace process_notification_windows to support localized messages
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
      -- Body is localized based on recipient's locale
      internal.build_batched_body(
        v_window.added_count,
        v_window.updated_count,
        v_window.deleted_count,
        COALESCE(u.raw_user_meta_data->>'locale', 'no')
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


-- ============================================================================
-- PHASE 4: Grant permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION internal.format_shift_date TO service_role;
GRANT EXECUTE ON FUNCTION internal.build_shift_title TO service_role;
GRANT EXECUTE ON FUNCTION internal.build_shift_body TO service_role;
GRANT EXECUTE ON FUNCTION internal.build_batched_body TO service_role;
