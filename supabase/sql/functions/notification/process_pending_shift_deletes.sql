-- Function: process_pending_shift_deletes
-- Description: Processes pending shift deletes, detecting delete-then-recreate patterns
-- Used by: run_shift_notification_workers (cron job)
--
-- Notification routing based on notification_frequency:
-- - 'instant': Queue to notification_queue for immediate delivery
-- - 'summary': Queue to pending_summary_notifications for daily digest (splits by same-day exception)
-- - 'muted': Skip notification entirely

CREATE OR REPLACE FUNCTION public.process_pending_shift_deletes()
 RETURNS TABLE(owners_processed integer, total_updated integer, total_deleted integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  owner_rec RECORD;
  delete_rec RECORD;
  replacement_shift RECORD;
  owner_name TEXT;
  changes_hash TEXT;
  v_owners_processed INT := 0;
  v_total_updated INT := 0;
  v_total_deleted INT := 0;
  v_today DATE;

  -- Aggregated data per owner
  updated_shifts JSONB;
  deleted_shifts JSONB;
  all_dates TEXT[];
  updated_count INT;
  deleted_count INT;
BEGIN
  v_today := CURRENT_DATE;

  -- Claim pending deletes that are ready to process
  UPDATE pending_shift_deletes
  SET status = 'processing',
      processing_started_at = now()
  WHERE status = 'pending'
    AND check_at <= now();

  -- Process by OWNER (aggregate all deletes for same owner)
  FOR owner_rec IN
    SELECT DISTINCT owner_id
    FROM pending_shift_deletes
    WHERE status = 'processing'
      AND processing_started_at >= now() - INTERVAL '5 minutes'
  LOOP
    v_owners_processed := v_owners_processed + 1;

    -- Reset aggregation for this owner
    updated_shifts := '[]'::jsonb;
    deleted_shifts := '[]'::jsonb;
    all_dates := '{}';
    updated_count := 0;
    deleted_count := 0;

    -- Get owner name
    SELECT
      COALESCE(
        raw_user_meta_data->>'full_name',
        raw_user_meta_data->>'name',
        email,
        'Noen'
      )
    INTO owner_name
    FROM auth.users
    WHERE id = owner_rec.owner_id;

    IF owner_name IS NULL THEN
      owner_name := 'Noen';
    END IF;

    -- Process each delete for this owner
    FOR delete_rec IN
      SELECT *
      FROM pending_shift_deletes
      WHERE owner_id = owner_rec.owner_id
        AND status = 'processing'
        AND processing_started_at >= now() - INTERVAL '5 minutes'
    LOOP
      -- Check if a replacement shift was created on the same date
      SELECT id, shift_date, start_time, end_time INTO replacement_shift
      FROM user_shifts
      WHERE user_id = delete_rec.owner_id
        AND shift_date = delete_rec.shift_date
        AND created_at > delete_rec.deleted_at
      ORDER BY created_at DESC
      LIMIT 1;

      -- Add date to all_dates for deep linking
      all_dates := array_append(all_dates, delete_rec.shift_date::text);

      IF replacement_shift.id IS NOT NULL THEN
        -- This was a delete-then-recreate: count as updated
        updated_count := updated_count + 1;
        v_total_updated := v_total_updated + 1;

        updated_shifts := updated_shifts || jsonb_build_array(
          jsonb_build_object(
            'shift_id', replacement_shift.id,
            'shift_date', replacement_shift.shift_date,
            'start_time', replacement_shift.start_time,
            'end_time', replacement_shift.end_time
          )
        );

        -- Mark as resolved with 'updated' resolution
        UPDATE pending_shift_deletes
        SET status = 'resolved',
            resolution = 'updated'
        WHERE id = delete_rec.id;
      ELSE
        -- No replacement: count as deleted
        deleted_count := deleted_count + 1;
        v_total_deleted := v_total_deleted + 1;

        deleted_shifts := deleted_shifts || jsonb_build_array(
          jsonb_build_object(
            'shift_id', delete_rec.deleted_shift_id,
            'shift_date', delete_rec.shift_date,
            'start_time', delete_rec.start_time,
            'end_time', delete_rec.end_time
          )
        );

        -- Mark as resolved with 'deleted' resolution
        UPDATE pending_shift_deletes
        SET status = 'resolved',
            resolution = 'deleted'
        WHERE id = delete_rec.id;
      END IF;
    END LOOP;

    -- Only queue notification if there were any changes
    IF updated_count > 0 OR deleted_count > 0 THEN
      -- Generate hash for idempotency (based on all processed delete IDs)
      changes_hash := md5(owner_rec.owner_id::text || now()::text || random()::text);

      -- Route instant notifications
      -- Note: ss.blocked controls visibility ONLY (hides from /sharing list), NOT notifications
      -- notification_frequency controls whether user gets notified (instant/summary/muted)
      -- Blocked users still receive notifications - they just don't see the sharer in their list
      INSERT INTO internal.notification_queue (
        type,
        recipient_id,
        sender_id,
        payload,
        idempotency_key
      )
      SELECT
        'shared_shift_changes',
        ss.viewer_id,
        owner_rec.owner_id,
        jsonb_build_object(
          'owner_id', owner_rec.owner_id,
          'owner_name', owner_name,
          'updated_count', updated_count,
          'deleted_count', deleted_count,
          'shift_dates', array_to_string(all_dates, ','),
          'updated_shifts', updated_shifts,
          'deleted_shifts', deleted_shifts
        ),
        'shift_changes:' || owner_rec.owner_id || ':' || ss.viewer_id || ':' || changes_hash
      FROM shift_shares ss
      LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
      WHERE ss.owner_id = owner_rec.owner_id
        AND COALESCE(np.shared_shifts_enabled, true) = true
        AND COALESCE(ss.notification_frequency, 'instant') = 'instant'
      ON CONFLICT (idempotency_key) DO NOTHING;

      -- Route summary notifications (with same-day exception)
      -- Same-day shifts go to instant queue even for summary users
      INSERT INTO internal.notification_queue (
        type,
        recipient_id,
        sender_id,
        payload,
        idempotency_key
      )
      SELECT
        'shared_shift_changes',
        ss.viewer_id,
        owner_rec.owner_id,
        jsonb_build_object(
          'owner_id', owner_rec.owner_id,
          'owner_name', owner_name,
          'updated_count', (SELECT count(*) FROM jsonb_array_elements(updated_shifts) s WHERE (s->>'shift_date')::date = v_today),
          'deleted_count', (SELECT count(*) FROM jsonb_array_elements(deleted_shifts) s WHERE (s->>'shift_date')::date = v_today),
          'shift_dates', (
            SELECT string_agg(s->>'shift_date', ',')
            FROM (
              SELECT s FROM jsonb_array_elements(updated_shifts) s WHERE (s->>'shift_date')::date = v_today
              UNION ALL
              SELECT s FROM jsonb_array_elements(deleted_shifts) s WHERE (s->>'shift_date')::date = v_today
            ) sq
          ),
          'updated_shifts', (SELECT COALESCE(jsonb_agg(s), '[]'::jsonb) FROM jsonb_array_elements(updated_shifts) s WHERE (s->>'shift_date')::date = v_today),
          'deleted_shifts', (SELECT COALESCE(jsonb_agg(s), '[]'::jsonb) FROM jsonb_array_elements(deleted_shifts) s WHERE (s->>'shift_date')::date = v_today)
        ),
        'shift_changes_sameday:' || owner_rec.owner_id || ':' || ss.viewer_id || ':' || changes_hash
      FROM shift_shares ss
      LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
      WHERE ss.owner_id = owner_rec.owner_id
        AND COALESCE(np.shared_shifts_enabled, true) = true
        AND ss.notification_frequency = 'summary'
        AND (
          EXISTS (SELECT 1 FROM jsonb_array_elements(updated_shifts) s WHERE (s->>'shift_date')::date = v_today)
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(deleted_shifts) s WHERE (s->>'shift_date')::date = v_today)
        )
      ON CONFLICT (idempotency_key) DO NOTHING;

      -- Non-same-day shifts go to summary queue
      INSERT INTO pending_summary_notifications (recipient_id, sender_id, shift_id, shift_date, start_time, end_time, owner_name, notification_type)
      SELECT
        ss.viewer_id,
        owner_rec.owner_id,
        (s->>'shift_id')::uuid,
        (s->>'shift_date')::date,
        (s->>'start_time')::time,
        (s->>'end_time')::time,
        owner_name,
        'updated'
      FROM shift_shares ss
      LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
      CROSS JOIN jsonb_array_elements(updated_shifts) s
      WHERE ss.owner_id = owner_rec.owner_id
        AND COALESCE(np.shared_shifts_enabled, true) = true
        AND ss.notification_frequency = 'summary'
        AND (s->>'shift_date')::date != v_today
      ON CONFLICT (recipient_id, sender_id, shift_id) DO NOTHING;

      INSERT INTO pending_summary_notifications (recipient_id, sender_id, shift_id, shift_date, start_time, end_time, owner_name, notification_type)
      SELECT
        ss.viewer_id,
        owner_rec.owner_id,
        (s->>'shift_id')::uuid,
        (s->>'shift_date')::date,
        (s->>'start_time')::time,
        (s->>'end_time')::time,
        owner_name,
        'deleted'
      FROM shift_shares ss
      LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
      CROSS JOIN jsonb_array_elements(deleted_shifts) s
      WHERE ss.owner_id = owner_rec.owner_id
        AND COALESCE(np.shared_shifts_enabled, true) = true
        AND ss.notification_frequency = 'summary'
        AND (s->>'shift_date')::date != v_today
      ON CONFLICT (recipient_id, sender_id, shift_id) DO NOTHING;
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_owners_processed, v_total_updated, v_total_deleted;
END;
$function$;
