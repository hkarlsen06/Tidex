-- Function: process_shift_update_events
-- Description: Processes direct shift update events and queues notifications
-- Used by: run_shift_notification_workers (cron job)

CREATE OR REPLACE FUNCTION public.process_shift_update_events()
 RETURNS TABLE(owners_processed integer, total_updated integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_owner_id UUID;
  v_owner_name TEXT;
  v_updated_shifts JSONB;
  v_updated_count INT;
  v_claimed_ids TEXT;
  v_owners_processed INT := 0;
  v_total_updated INT := 0;
BEGIN
  -- Process by owner (batch all their update events together)
  FOR v_owner_id IN
    SELECT DISTINCT owner_id
    FROM shift_update_events
    WHERE status = 'pending'
       OR (status = 'processing' AND processing_started_at < now() - INTERVAL '10 minutes')
  LOOP
    -- Atomic claim all update events for this owner
    WITH claimed AS (
      UPDATE shift_update_events
      SET status = 'processing', processing_started_at = now()
      WHERE owner_id = v_owner_id
        AND (status = 'pending'
             OR (status = 'processing' AND processing_started_at < now() - INTERVAL '10 minutes'))
      RETURNING *
    ),
    claimed_ids AS (
      SELECT string_agg(id::text, ',' ORDER BY id) AS ids FROM claimed
    ),
    aggregated AS (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'shift_id', shift_id,
          'shift_date', shift_date,
          'start_time', start_time,
          'end_time', end_time
        ) ORDER BY shift_date, start_time
      ), '[]'::jsonb) AS shifts
      FROM claimed
    ),
    -- Mark all as sent
    marked AS (
      UPDATE shift_update_events sue
      SET status = 'sent'
      FROM claimed c
      WHERE sue.id = c.id
      RETURNING sue.id
    )
    SELECT a.shifts, ci.ids
    INTO v_updated_shifts, v_claimed_ids
    FROM aggregated a, claimed_ids ci;

    -- Skip if nothing was claimed (race condition: another worker got them)
    IF v_claimed_ids IS NULL THEN
      CONTINUE;
    END IF;

    v_updated_count := jsonb_array_length(v_updated_shifts);

    -- Skip if nothing claimed
    IF v_updated_count = 0 THEN
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

    -- Queue ONE combined notification (reuse shared_shift_changes with only updated_shifts)
    INSERT INTO notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
    SELECT
      'shared_shift_changes',
      ss.viewer_id,
      v_owner_id,
      jsonb_build_object(
        'updated_shifts', v_updated_shifts,
        'deleted_shifts', '[]'::jsonb,
        'updated_count', v_updated_count,
        'deleted_count', 0,
        'owner_id', v_owner_id,
        'owner_name', v_owner_name
      ),
      -- Stable idempotency key: hash of sorted claimed event IDs
      'shift_direct_updates:' || v_owner_id || ':' || ss.viewer_id || ':' || md5(v_claimed_ids)
    FROM shift_shares ss
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = v_owner_id
      AND ss.blocked = false
      AND COALESCE(np.shared_shifts_enabled, true) = true
    ON CONFLICT (idempotency_key) DO NOTHING;

    v_total_updated := v_total_updated + v_updated_count;
    v_owners_processed := v_owners_processed + 1;
  END LOOP;

  RETURN QUERY SELECT v_owners_processed, v_total_updated;
END;
$function$;
