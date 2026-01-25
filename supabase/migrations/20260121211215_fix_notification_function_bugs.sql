-- Migration: Fix notification function bugs
--
-- Fixes:
-- 1. build_batched_body: Handle edge case where all counts are 0 (returns NULL -> localized "No changes")
-- 2. enqueue_shift_notification: Remove unused v_oslo_offset variable (dead code cleanup)

-- ============================================================================
-- Fix 1: build_batched_body - Handle empty array case
-- ============================================================================

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

    -- Join with commas and "and" (handle empty array case)
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

    -- Join with commas and "og" (handle empty array case)
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
-- Fix 2: enqueue_shift_notification - Remove dead code (v_oslo_offset)
-- ============================================================================

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
