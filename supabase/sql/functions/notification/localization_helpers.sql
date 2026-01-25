-- Functions: Notification Localization Helpers
-- Description: Helper functions for building localized notification messages
-- Used by: enqueue_shift_notification RPC, process_notification_windows
-- Schema: internal
--
-- These functions generate localized notification titles and bodies
-- based on the recipient's locale preference (stored in auth.users.raw_user_meta_data->>'locale').
-- Supported locales: 'no' (Norwegian, default), 'en' (English)

-- ============================================================================
-- Format a date in the user's locale
-- ============================================================================
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


-- ============================================================================
-- Build localized title for a single shift event
-- ============================================================================
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


-- ============================================================================
-- Build localized body for a single shift event
-- ============================================================================
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


-- ============================================================================
-- Build localized body for batched notifications
-- ============================================================================
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


-- Grant permissions
GRANT EXECUTE ON FUNCTION internal.format_shift_date TO service_role;
GRANT EXECUTE ON FUNCTION internal.build_shift_title TO service_role;
GRANT EXECUTE ON FUNCTION internal.build_shift_body TO service_role;
GRANT EXECUTE ON FUNCTION internal.build_batched_body TO service_role;
