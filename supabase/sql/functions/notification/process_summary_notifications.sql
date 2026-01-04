-- Function: process_summary_notifications
-- Description: Processes pending summary notifications at user's configured summary time
-- Called by: run_shift_notification_workers (cron job)
--
-- This function aggregates all pending summary notifications for each viewer
-- and creates a single combined notification when the user's summary_time is reached.
-- It respects the user's timezone (Europe/Oslo) for summary delivery timing.

CREATE OR REPLACE FUNCTION public.process_summary_notifications()
 RETURNS TABLE(processed_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_viewer_id UUID;
  v_owner_id UUID;
  v_owner_name TEXT;
  v_created_count INT;
  v_updated_count INT;
  v_deleted_count INT;
  v_total_count INT;
  v_shift_dates TEXT[];
  v_processed INT := 0;
  v_current_oslo_time TIME;
BEGIN
  -- Get current time in Europe/Oslo
  v_current_oslo_time := (now() AT TIME ZONE 'Europe/Oslo')::time;

  -- Find viewers whose summary_time has passed today
  FOR v_viewer_id IN
    SELECT DISTINCT psn.viewer_id
    FROM pending_summary_notifications psn
    JOIN notification_preferences np ON np.user_id = psn.viewer_id
    WHERE psn.status = 'pending'
      -- Summary time has passed (with 5 minute window)
      AND np.summary_time <= v_current_oslo_time
      AND np.summary_time > (v_current_oslo_time - INTERVAL '5 minutes')
  LOOP
    -- Process each owner separately for this viewer
    FOR v_owner_id IN
      SELECT DISTINCT owner_id
      FROM pending_summary_notifications
      WHERE viewer_id = v_viewer_id
        AND status = 'pending'
    LOOP
      -- Claim and aggregate pending notifications for this viewer/owner pair
      WITH claimed AS (
        UPDATE pending_summary_notifications
        SET status = 'processing'
        WHERE viewer_id = v_viewer_id
          AND owner_id = v_owner_id
          AND status = 'pending'
        RETURNING *
      ),
      aggregated AS (
        SELECT
          COUNT(*) FILTER (WHERE event_type = 'created') AS created_count,
          COUNT(*) FILTER (WHERE event_type = 'updated') AS updated_count,
          COUNT(*) FILTER (WHERE event_type = 'deleted') AS deleted_count,
          COUNT(*) AS total_count,
          array_agg(DISTINCT shift_date ORDER BY shift_date) AS shift_dates
        FROM claimed
      ),
      -- Mark as processed
      marked AS (
        UPDATE pending_summary_notifications psn
        SET status = 'sent'
        FROM claimed c
        WHERE psn.id = c.id
        RETURNING psn.id
      )
      SELECT a.created_count, a.updated_count, a.deleted_count, a.total_count, a.shift_dates
      INTO v_created_count, v_updated_count, v_deleted_count, v_total_count, v_shift_dates
      FROM aggregated a;

      -- Skip if nothing was claimed
      IF v_total_count IS NULL OR v_total_count = 0 THEN
        CONTINUE;
      END IF;

      -- Get owner name
      SELECT COALESCE(
        raw_user_meta_data->>'full_name',
        raw_user_meta_data->>'name',
        email,
        'Noen'
      ) INTO v_owner_name
      FROM auth.users WHERE id = v_owner_id;

      IF v_owner_name IS NULL THEN
        v_owner_name := 'Noen';
      END IF;

      -- Queue the summary notification
      INSERT INTO internal.notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
      VALUES (
        'shared_shift_summary',
        v_viewer_id,
        v_owner_id,
        jsonb_build_object(
          'owner_id', v_owner_id,
          'owner_name', v_owner_name,
          'created_count', v_created_count,
          'updated_count', v_updated_count,
          'deleted_count', v_deleted_count,
          'total_count', v_total_count,
          'shift_dates', v_shift_dates
        ),
        'summary:' || v_viewer_id || ':' || v_owner_id || ':' || to_char(now(), 'YYYY-MM-DD')
      )
      ON CONFLICT (idempotency_key) DO NOTHING;

      v_processed := v_processed + 1;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT v_processed;
END;
$function$;
