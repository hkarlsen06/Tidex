-- Function: process_shift_update_events
-- Description: Processes direct shift update events and queues notifications
-- Used by: run_shift_notification_workers (cron job)
--
-- Notification routing based on notification_frequency:
-- - 'instant': Queue to notification_queue for immediate delivery
-- - 'summary': Queue to pending_summary_notifications for daily digest (splits by same-day exception)
-- - 'muted': Skip notification entirely

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
  v_today DATE;
BEGIN
  v_today := CURRENT_DATE;

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

    -- Route instant notifications
    -- Note: ss.blocked controls visibility ONLY (hides from /sharing list), NOT notifications
    -- notification_frequency controls whether user gets notified (instant/summary/muted)
    -- Blocked users still receive notifications - they just don't see the sharer in their list
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
      'shift_direct_updates:' || v_owner_id || ':' || ss.viewer_id || ':' || md5(v_claimed_ids)
    FROM shift_shares ss
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = v_owner_id
      AND COALESCE(np.shared_shifts_enabled, true) = true
      AND COALESCE(ss.notification_frequency, 'instant') = 'instant'
    ON CONFLICT (idempotency_key) DO NOTHING;

    -- Route summary notifications (with same-day exception: today's shifts go instant)
    -- Same-day shifts to instant
    INSERT INTO notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
    SELECT
      'shared_shift_changes',
      ss.viewer_id,
      v_owner_id,
      jsonb_build_object(
        'updated_shifts', (SELECT jsonb_agg(s) FROM jsonb_array_elements(v_updated_shifts) s WHERE (s->>'shift_date')::date = v_today),
        'deleted_shifts', '[]'::jsonb,
        'updated_count', (SELECT count(*) FROM jsonb_array_elements(v_updated_shifts) s WHERE (s->>'shift_date')::date = v_today),
        'deleted_count', 0,
        'owner_id', v_owner_id,
        'owner_name', v_owner_name
      ),
      'shift_direct_updates_sameday:' || v_owner_id || ':' || ss.viewer_id || ':' || md5(v_claimed_ids)
    FROM shift_shares ss
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = v_owner_id
      AND COALESCE(np.shared_shifts_enabled, true) = true
      AND ss.notification_frequency = 'summary'
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_updated_shifts) s WHERE (s->>'shift_date')::date = v_today)
    ON CONFLICT (idempotency_key) DO NOTHING;

    -- Non-same-day shifts to summary
    INSERT INTO pending_summary_notifications (recipient_id, sender_id, shift_id, shift_date, notification_type)
    SELECT
      ss.viewer_id,
      v_owner_id,
      (s->>'shift_id')::uuid,
      (s->>'shift_date')::date,
      'updated'
    FROM shift_shares ss
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    CROSS JOIN jsonb_array_elements(v_updated_shifts) s
    WHERE ss.owner_id = v_owner_id
      AND COALESCE(np.shared_shifts_enabled, true) = true
      AND ss.notification_frequency = 'summary'
      AND (s->>'shift_date')::date != v_today
    ON CONFLICT (recipient_id, sender_id, shift_id) DO NOTHING;

    v_total_updated := v_total_updated + v_updated_count;
    v_owners_processed := v_owners_processed + 1;
  END LOOP;

  RETURN QUERY SELECT v_owners_processed, v_total_updated;
END;
$function$;
