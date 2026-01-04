-- Migration: Move selected tables from public to internal schema
-- Purpose: Separate internal/service-role-only tables from public-facing tables
-- Date: 2026-01-04

-- ==============================================================================
-- PHASE 1: Create internal schema with restricted access
-- ==============================================================================

-- Create the internal schema
CREATE SCHEMA IF NOT EXISTS internal;

-- Revoke all access from public roles
REVOKE ALL ON SCHEMA internal FROM public;
REVOKE ALL ON SCHEMA internal FROM anon;
REVOKE ALL ON SCHEMA internal FROM authenticated;

-- Grant full access to service_role and postgres
GRANT ALL ON SCHEMA internal TO service_role;
GRANT USAGE ON SCHEMA internal TO postgres;
GRANT ALL ON SCHEMA internal TO postgres;

-- ==============================================================================
-- PHASE 2: Move tables to internal schema
-- ==============================================================================

-- Note: ALTER TABLE ... SET SCHEMA preserves all data, constraints, indexes,
-- triggers, and foreign keys. The FK from notification_queue.broadcast_id to
-- admin_broadcasts.id will remain valid since both tables move together.

ALTER TABLE public.stripe_events SET SCHEMA internal;
ALTER TABLE public.apple_notifications SET SCHEMA internal;
ALTER TABLE public.apple_orphan_notifications SET SCHEMA internal;
ALTER TABLE public.app_account_tokens SET SCHEMA internal;
ALTER TABLE public.admin_broadcasts SET SCHEMA internal;
ALTER TABLE public.admin_audit_log SET SCHEMA internal;
ALTER TABLE public.impersonation_sessions SET SCHEMA internal;
ALTER TABLE public.impersonation_rate_limits SET SCHEMA internal;
ALTER TABLE public.push_devices SET SCHEMA internal;
ALTER TABLE public.notification_queue SET SCHEMA internal;

-- ==============================================================================
-- PHASE 3: Disable RLS on internal tables (service_role bypasses anyway)
-- ==============================================================================

ALTER TABLE internal.stripe_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.apple_notifications DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.apple_orphan_notifications DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.app_account_tokens DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.admin_broadcasts DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.admin_audit_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.impersonation_sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.impersonation_rate_limits DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.push_devices DISABLE ROW LEVEL SECURITY;
ALTER TABLE internal.notification_queue DISABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- PHASE 4: Drop old RLS policies (no longer needed in internal schema)
-- ==============================================================================

-- stripe_events
DROP POLICY IF EXISTS "no_client_access" ON internal.stripe_events;

-- apple_notifications
DROP POLICY IF EXISTS "Deny all access - server only table" ON internal.apple_notifications;

-- apple_orphan_notifications
DROP POLICY IF EXISTS "Deny all access - server only table" ON internal.apple_orphan_notifications;

-- app_account_tokens
DROP POLICY IF EXISTS "Users can create own app_account_token" ON internal.app_account_tokens;
DROP POLICY IF EXISTS "Users can view own app_account_token" ON internal.app_account_tokens;

-- admin_broadcasts
DROP POLICY IF EXISTS "Admin can delete broadcasts" ON internal.admin_broadcasts;
DROP POLICY IF EXISTS "Admin can insert broadcasts" ON internal.admin_broadcasts;
DROP POLICY IF EXISTS "Admin can read broadcasts" ON internal.admin_broadcasts;
DROP POLICY IF EXISTS "Admin can update broadcasts" ON internal.admin_broadcasts;

-- admin_audit_log
DROP POLICY IF EXISTS "Admins can view audit log" ON internal.admin_audit_log;
DROP POLICY IF EXISTS "Block DELETE from authenticated" ON internal.admin_audit_log;
DROP POLICY IF EXISTS "Block INSERT from authenticated" ON internal.admin_audit_log;
DROP POLICY IF EXISTS "Block UPDATE from authenticated" ON internal.admin_audit_log;

-- impersonation_sessions (may not have policies, but drop if exist)
DROP POLICY IF EXISTS "service_role_only" ON internal.impersonation_sessions;

-- impersonation_rate_limits (may not have policies, but drop if exist)
DROP POLICY IF EXISTS "service_role_only" ON internal.impersonation_rate_limits;

-- push_devices
DROP POLICY IF EXISTS "Users can delete own devices" ON internal.push_devices;
DROP POLICY IF EXISTS "Users can insert own devices" ON internal.push_devices;
DROP POLICY IF EXISTS "Users can update own devices" ON internal.push_devices;
DROP POLICY IF EXISTS "Users can view own devices" ON internal.push_devices;

-- notification_queue
DROP POLICY IF EXISTS "Service role can manage notification queue" ON internal.notification_queue;

-- ==============================================================================
-- PHASE 5: Grant table-level permissions to service_role
-- ==============================================================================

GRANT ALL ON internal.stripe_events TO service_role;
GRANT ALL ON internal.apple_notifications TO service_role;
GRANT ALL ON internal.apple_orphan_notifications TO service_role;
GRANT ALL ON internal.app_account_tokens TO service_role;
GRANT ALL ON internal.admin_broadcasts TO service_role;
GRANT ALL ON internal.admin_audit_log TO service_role;
GRANT ALL ON internal.impersonation_sessions TO service_role;
GRANT ALL ON internal.impersonation_rate_limits TO service_role;
GRANT ALL ON internal.push_devices TO service_role;
GRANT ALL ON internal.notification_queue TO service_role;

-- Grant sequence permissions if any
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA internal TO service_role;

-- ==============================================================================
-- PHASE 6: Update SQL functions to reference internal schema
-- ==============================================================================

-- admin_count_target_users_active: references push_devices
CREATE OR REPLACE FUNCTION public.admin_count_target_users_active()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  INNER JOIN user_settings us ON us.user_id = pd.user_id
  WHERE us.last_active >= NOW() - INTERVAL '7 days';
$function$;

-- admin_count_target_users_all: references push_devices
CREATE OR REPLACE FUNCTION public.admin_count_target_users_all(exclude_user_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  WHERE (exclude_user_id IS NULL OR pd.user_id != exclude_user_id);
$function$;

-- admin_count_target_users_pro: references push_devices, subscriptions (subscriptions stays in public)
CREATE OR REPLACE FUNCTION public.admin_count_target_users_pro()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT COUNT(DISTINCT pd.user_id)
  FROM internal.push_devices pd
  INNER JOIN subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$function$;

-- admin_get_audit_log: references admin_audit_log
CREATE OR REPLACE FUNCTION public.admin_get_audit_log(p_limit integer DEFAULT 50, p_action_filter text DEFAULT NULL::text, p_target_filter uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, admin_id uuid, admin_email text, action text, target_user_id uuid, target_email text, metadata jsonb, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    a.id,
    a.admin_id,
    a.admin_email,
    a.action,
    a.target_user_id,
    a.target_email,
    a.metadata,
    a.created_at
  FROM internal.admin_audit_log a
  WHERE
    (p_action_filter IS NULL OR a.action = p_action_filter)
    AND (p_target_filter IS NULL OR a.target_user_id = p_target_filter)
  ORDER BY a.created_at DESC
  LIMIT p_limit;
END;
$function$;

-- admin_get_broadcast_history: references admin_broadcasts, notification_queue
CREATE OR REPLACE FUNCTION public.admin_get_broadcast_history(limit_count integer DEFAULT 10)
 RETURNS TABLE(id uuid, title text, body text, target text, target_count integer, status text, created_at timestamp with time zone, sent_count bigint, failed_count bigint, skipped_count bigint, pending_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT
    ab.id,
    ab.title,
    ab.body,
    ab.target,
    ab.target_count,
    ab.status,
    ab.created_at,
    COUNT(*) FILTER (WHERE nq.status = 'sent') AS sent_count,
    COUNT(*) FILTER (WHERE nq.status = 'failed') AS failed_count,
    COUNT(*) FILTER (WHERE nq.status = 'skipped') AS skipped_count,
    COUNT(*) FILTER (WHERE nq.status IN ('pending', 'processing')) AS pending_count
  FROM internal.admin_broadcasts ab
  LEFT JOIN internal.notification_queue nq ON nq.broadcast_id = ab.id
  GROUP BY ab.id, ab.title, ab.body, ab.target, ab.target_count, ab.status, ab.created_at
  ORDER BY ab.created_at DESC
  LIMIT limit_count;
$function$;

-- admin_get_subscribers: references subscriptions (stays in public)
-- No changes needed

-- admin_get_target_users_active: references push_devices
CREATE OR REPLACE FUNCTION public.admin_get_target_users_active()
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  INNER JOIN user_settings us ON us.user_id = pd.user_id
  WHERE us.last_active >= NOW() - INTERVAL '7 days';
$function$;

-- admin_get_target_users_all: references push_devices
CREATE OR REPLACE FUNCTION public.admin_get_target_users_all(exclude_user_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  WHERE (exclude_user_id IS NULL OR pd.user_id != exclude_user_id);
$function$;

-- admin_get_target_users_pro: references push_devices, subscriptions (subscriptions stays in public)
CREATE OR REPLACE FUNCTION public.admin_get_target_users_pro()
 RETURNS TABLE(user_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT DISTINCT pd.user_id
  FROM internal.push_devices pd
  INNER JOIN subscriptions s ON s.user_id = pd.user_id
  WHERE s.status IN ('active', 'trialing');
$function$;

-- admin_log_action: references admin_audit_log
CREATE OR REPLACE FUNCTION public.admin_log_action(p_admin_id uuid, p_admin_email text, p_action text, p_target_id uuid DEFAULT NULL::uuid, p_target_email text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_log_id UUID;
BEGIN
  -- Validate action is in allowed list
  IF p_action NOT IN (
    'user_lookup', 'user_ban', 'user_unban',
    'grant_grandfathered', 'revoke_grandfathered',
    'create_trial_subscription', 'revoke_trial_subscription',
    'broadcast_sent', 'user_list_viewed', 'admin_action_failed',
    'sql_executed',
    'shift_share_created', 'shift_share_updated', 'shift_share_deleted'
  ) THEN
    RAISE EXCEPTION 'Invalid action type: %', p_action;
  END IF;

  INSERT INTO internal.admin_audit_log (
    admin_id,
    admin_email,
    action,
    target_user_id,
    target_email,
    metadata
  ) VALUES (
    p_admin_id,
    p_admin_email,
    p_action,
    p_target_id,
    p_target_email,
    p_metadata
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$function$;

-- check_impersonation_rate_limit: references impersonation_rate_limits
CREATE OR REPLACE FUNCTION public.check_impersonation_rate_limit(p_admin_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  attempt_count int;
BEGIN
  -- Count attempts in the last hour
  SELECT COUNT(*) INTO attempt_count
  FROM internal.impersonation_rate_limits
  WHERE admin_user_id = p_admin_user_id
    AND attempted_at > (now() - interval '1 hour');

  -- Return true if under limit (10 per hour)
  RETURN attempt_count < 10;
END;
$function$;

-- claim_pending_notifications: references notification_queue
CREATE OR REPLACE FUNCTION public.claim_pending_notifications(batch_size integer DEFAULT 50)
 RETURNS SETOF internal.notification_queue
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
BEGIN
  -- First, reset any stale "processing" rows (worker died)
  -- Rows claimed more than 5 minutes ago are considered stale
  UPDATE internal.notification_queue
  SET status = 'pending', claimed_at = NULL
  WHERE status = 'processing'
    AND claimed_at < NOW() - INTERVAL '5 minutes';

  -- Atomically claim and return rows
  -- FOR UPDATE SKIP LOCKED ensures no two workers claim the same row
  RETURN QUERY
  WITH claimed AS (
    UPDATE internal.notification_queue
    SET
      status = 'processing',
      claimed_at = NOW()
    WHERE id IN (
      SELECT id
      FROM internal.notification_queue
      WHERE status = 'pending'
      ORDER BY created_at
      FOR UPDATE SKIP LOCKED
      LIMIT batch_size
    )
    RETURNING *
  )
  SELECT * FROM claimed;
END;
$function$;

-- get_or_create_app_account_token: references app_account_tokens
CREATE OR REPLACE FUNCTION public.get_or_create_app_account_token(p_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  v_token uuid;
BEGIN
  -- First try to get existing token
  SELECT token INTO v_token
  FROM internal.app_account_tokens
  WHERE user_id = p_user_id;

  -- If not found, create one
  IF v_token IS NULL THEN
    INSERT INTO internal.app_account_tokens (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
    RETURNING token INTO v_token;
  END IF;

  RETURN v_token;
END;
$function$;

-- get_shifts_due_for_reminder: references push_devices
CREATE OR REPLACE FUNCTION public.get_shifts_due_for_reminder()
 RETURNS TABLE(user_id uuid, shift_instance_key text, shift_date date, start_time time without time zone, end_time time without time zone, reminder_minutes integer, minutes_until_shift integer)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  cron_interval_minutes CONSTANT INTEGER := 1;  -- Cron runs every 1 minute
BEGIN
  RETURN QUERY
  WITH user_prefs AS (
    -- Get all users with push devices and their reminder arrays
    SELECT DISTINCT
      pd.user_id,
      COALESCE(np.shift_reminders_enabled, true) AS enabled,
      -- Use the array column with default fallback
      COALESCE(np.shift_reminder_minutes_array, ARRAY[300]) AS reminder_mins_array
    FROM internal.push_devices pd
    LEFT JOIN notification_preferences np ON np.user_id = pd.user_id
    WHERE COALESCE(np.shift_reminders_enabled, true) = true
  ),
  -- Unnest reminder arrays to get one row per (user, reminder_minutes)
  user_reminders AS (
    SELECT
      up.user_id,
      unnest(up.reminder_mins_array) AS reminder_mins
    FROM user_prefs up
  ),
  -- Get single shifts with explicit Europe/Oslo timezone
  single_shifts AS (
    SELECT
      us.user_id,
      'single:' || us.id || ':' || us.shift_date || ':' || us.start_time AS instance_key,
      us.shift_date,
      us.start_time::TIME AS start_time,
      us.end_time::TIME AS end_time,
      ((us.shift_date::TEXT || ' ' || us.start_time)::TIMESTAMP AT TIME ZONE 'Europe/Oslo') AS shift_start_ts
    FROM user_shifts us
    WHERE us.shift_date >= CURRENT_DATE
      AND us.shift_date <= CURRENT_DATE + INTERVAL '3 days'
  ),
  -- Cross join shifts with each user's reminder settings
  shift_reminders AS (
    SELECT
      ss.user_id,
      ss.instance_key,
      ss.shift_date,
      ss.start_time,
      ss.end_time,
      ss.shift_start_ts,
      ur.reminder_mins
    FROM single_shifts ss
    JOIN user_reminders ur ON ur.user_id = ss.user_id
  ),
  -- Calculate minutes until shift
  due_shifts AS (
    SELECT
      sr.*,
      EXTRACT(EPOCH FROM (sr.shift_start_ts - NOW())) / 60 AS mins_until
    FROM shift_reminders sr
    WHERE sr.shift_start_ts > NOW()  -- Shift hasn't started
  )
  SELECT
    ds.user_id,
    ds.instance_key AS shift_instance_key,
    ds.shift_date,
    ds.start_time,
    ds.end_time,
    ds.reminder_mins AS reminder_minutes,
    CEIL(ds.mins_until)::INTEGER AS minutes_until_shift
  FROM due_shifts ds
  WHERE
    -- Narrow window: only send when within [reminder_minutes - cron_interval, reminder_minutes]
    ds.mins_until <= ds.reminder_mins
    AND ds.mins_until >= (ds.reminder_mins - cron_interval_minutes);
END;
$function$;

-- get_user_id_by_app_account_token: references app_account_tokens
CREATE OR REPLACE FUNCTION public.get_user_id_by_app_account_token(p_token uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT user_id FROM internal.app_account_tokens WHERE token = p_token;
$function$;

-- process_pending_shift_deletes: references notification_queue
CREATE OR REPLACE FUNCTION public.process_pending_shift_deletes()
 RETURNS TABLE(owners_processed integer, total_updated integer, total_deleted integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
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

-- process_shift_update_events: references notification_queue
CREATE OR REPLACE FUNCTION public.process_shift_update_events()
 RETURNS TABLE(owners_processed integer, total_updated integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
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
    INSERT INTO internal.notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
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
    INSERT INTO internal.notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
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
    INSERT INTO pending_summary_notifications (recipient_id, sender_id, shift_id, shift_date, start_time, end_time, owner_name, notification_type)
    SELECT
      ss.viewer_id,
      v_owner_id,
      (s->>'shift_id')::uuid,
      (s->>'shift_date')::date,
      (s->>'start_time')::time,
      (s->>'end_time')::time,
      v_owner_name,
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

-- process_summary_notifications: references notification_queue
CREATE OR REPLACE FUNCTION public.process_summary_notifications()
 RETURNS TABLE(users_processed integer, notifications_queued integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_now_oslo TIMESTAMP;  -- LOCAL timestamp, not timestamptz!
  v_current_minute TIME;
  v_user RECORD;
  v_sender RECORD;
  v_users_processed INT := 0;
  v_notifications_queued INT := 0;
BEGIN
  -- Get local time in Europe/Oslo (TIMESTAMP, not TIMESTAMPTZ)
  v_now_oslo := now() AT TIME ZONE 'Europe/Oslo';
  v_current_minute := date_trunc('minute', v_now_oslo)::TIME;

  -- Delete pending rows for users who have disabled shared_shifts_enabled
  DELETE FROM pending_summary_notifications psn
  USING notification_preferences np
  WHERE psn.recipient_id = np.user_id
    AND np.shared_shifts_enabled = false;

  -- Find users whose summary_time is current minute OR previous minute
  -- AND who have shared_shifts_enabled = true (or default true if no row)
  FOR v_user IN
    SELECT DISTINCT psn.recipient_id, COALESCE(np.summary_time, '18:00:00'::TIME) AS summary_time
    FROM pending_summary_notifications psn
    LEFT JOIN notification_preferences np ON np.user_id = psn.recipient_id
    WHERE COALESCE(np.shared_shifts_enabled, true) = true
      AND (COALESCE(np.summary_time, '18:00:00'::TIME) = v_current_minute
           OR COALESCE(np.summary_time, '18:00:00'::TIME) = (v_current_minute - INTERVAL '1 minute')::TIME)
  LOOP
    v_users_processed := v_users_processed + 1;

    -- Group by sender for this recipient
    FOR v_sender IN
      SELECT
        sender_id, owner_name,
        COUNT(*) FILTER (WHERE notification_type = 'created') AS created_count,
        COUNT(*) FILTER (WHERE notification_type = 'updated') AS updated_count,
        COUNT(*) FILTER (WHERE notification_type = 'deleted') AS deleted_count,
        jsonb_agg(jsonb_build_object(
          'type', notification_type,
          'shift_date', shift_date,
          'shift_id', shift_id,
          'start_time', start_time,
          'end_time', end_time
        ) ORDER BY shift_date, start_time) AS shifts
      FROM pending_summary_notifications
      WHERE recipient_id = v_user.recipient_id
      GROUP BY sender_id, owner_name
    LOOP
      -- Queue summary notification
      INSERT INTO internal.notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
      VALUES (
        'shared_shift_summary',
        v_user.recipient_id,
        v_sender.sender_id,
        jsonb_build_object(
          'owner_id', v_sender.sender_id,
          'owner_name', v_sender.owner_name,
          'created_count', v_sender.created_count,
          'updated_count', v_sender.updated_count,
          'deleted_count', v_sender.deleted_count,
          'shifts', v_sender.shifts,
          'is_summary', true,
          'summary_date', to_char(v_now_oslo, 'YYYY-MM-DD')
        ),
        -- Idempotency key uses LOCAL date
        'summary:' || v_user.recipient_id || ':' || v_sender.sender_id || ':' ||
          to_char(v_now_oslo, 'YYYY-MM-DD')
      )
      ON CONFLICT (idempotency_key) DO NOTHING;

      v_notifications_queued := v_notifications_queued + 1;

      -- Delete processed records for this sender
      DELETE FROM pending_summary_notifications
      WHERE recipient_id = v_user.recipient_id AND sender_id = v_sender.sender_id;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT v_users_processed, v_notifications_queued;
END;
$function$;

-- queue_feedback_responded_notification: references notification_queue
CREATE OR REPLACE FUNCTION public.queue_feedback_responded_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'auth'
AS $function$
BEGIN
  -- Only trigger when response is FIRST added (not on edits)
  IF OLD.response IS NULL AND NEW.response IS NOT NULL THEN
    INSERT INTO internal.notification_queue (
      type,
      recipient_id,
      sender_id,
      payload,
      idempotency_key
    ) VALUES (
      'feedback_responded',
      NEW.user_id,
      NEW.responded_by,
      jsonb_build_object(
        'feedback_id', NEW.id,
        'response_preview', LEFT(NEW.response, 150)
      ),
      'feedback_responded:' || NEW.id  -- Stable key, one notification per feedback
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

-- queue_feedback_submitted_notification: references notification_queue
CREATE OR REPLACE FUNCTION public.queue_feedback_submitted_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_user_name text;
BEGIN
  -- Get the submitter's name
  SELECT COALESCE(raw_user_meta_data->>'full_name', NEW.user_email)
  INTO v_user_name
  FROM auth.users
  WHERE id = NEW.user_id;

  -- Set-based insert for all admins (no loop)
  INSERT INTO internal.notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    'feedback_submitted',
    u.id,
    NEW.user_id,
    jsonb_build_object(
      'feedback_id', NEW.id,
      'user_name', v_user_name,
      'user_email', NEW.user_email,
      'message_preview', LEFT(NEW.message, 100)
    ),
    'feedback_submitted:' || NEW.id || ':' || u.id
  FROM auth.users u
  WHERE (u.raw_app_meta_data->>'role') = 'admin'
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;

-- queue_recurring_shift_created_notification: references notification_queue
CREATE OR REPLACE FUNCTION public.queue_recurring_shift_created_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  owner_name TEXT;
BEGIN
  -- Get the shift owner's display name from user_metadata (full_name only)
  SELECT
    COALESCE(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name',
      email,
      'Noen'
    )
  INTO owner_name
  FROM auth.users
  WHERE id = NEW.user_id;

  IF owner_name IS NULL THEN
    owner_name := 'Noen';
  END IF;

  -- Recurring shifts always go to instant queue (not summary)
  -- Skip muted users
  -- Note: ss.blocked controls visibility, NOT notifications
  -- notification_frequency controls whether user gets notified (instant/summary/muted)
  INSERT INTO internal.notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  SELECT
    'recurring_shift_created',
    ss.viewer_id,
    NEW.user_id,
    jsonb_build_object(
      'recurring_id', NEW.id,
      'owner_id', NEW.user_id,
      'owner_name', owner_name
    ),
    'recurring_created:' || NEW.id || ':' || ss.viewer_id
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND COALESCE(np.shared_shifts_enabled, true) = true
    AND COALESCE(ss.notification_frequency, 'instant') != 'muted'
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;

-- queue_share_started_notification: references notification_queue
CREATE OR REPLACE FUNCTION public.queue_share_started_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  sharer_name TEXT;
  viewer_prefs RECORD;
  is_mutual BOOLEAN;
BEGIN
  -- Get the sharer's display name
  SELECT COALESCE(raw_user_meta_data->>'full_name', email, 'Noen')
  INTO sharer_name
  FROM auth.users
  WHERE id = NEW.owner_id;

  -- Check viewer's notification preferences
  SELECT shared_shifts_enabled
  INTO viewer_prefs
  FROM notification_preferences
  WHERE user_id = NEW.viewer_id;

  -- Only queue notification if viewer has shared_shifts_enabled (default true if no prefs)
  IF COALESCE(viewer_prefs.shared_shifts_enabled, true) = false THEN
    RETURN NEW;
  END IF;

  -- Check if this is now mutual sharing (viewer already shares with owner)
  SELECT EXISTS (
    SELECT 1 FROM shift_shares
    WHERE owner_id = NEW.viewer_id AND viewer_id = NEW.owner_id
  ) INTO is_mutual;

  -- Insert notification for the viewer with appropriate type
  INSERT INTO internal.notification_queue (
    type,
    recipient_id,
    sender_id,
    payload,
    idempotency_key
  )
  VALUES (
    'share_started',
    NEW.viewer_id,
    NEW.owner_id,
    jsonb_build_object(
      'owner_id', NEW.owner_id,
      'owner_name', sharer_name,
      'is_mutual', is_mutual
    ),
    'share_started:' || NEW.owner_id || ':' || NEW.viewer_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$function$;

-- queue_shift_created_notification: references notification_queue
CREATE OR REPLACE FUNCTION public.queue_shift_created_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  owner_name TEXT;
  likely_replacement BOOLEAN := false;
  is_recurring_conversion BOOLEAN := false;
BEGIN
  -- Check if this shift likely replaces a recently deleted one
  -- Match on same date only - if user deletes and creates on same day, it's an update
  SELECT EXISTS (
    SELECT 1
    FROM pending_shift_deletes
    WHERE owner_id = NEW.user_id
      AND shift_date = NEW.shift_date
      AND status = 'pending'
      AND check_at > now()
  ) INTO likely_replacement;

  -- If this is a likely replacement, skip the created notification
  -- The cron job will send "updated" instead after the window expires
  IF likely_replacement THEN
    RETURN NEW;
  END IF;

  -- Check if this shift is a recurring conversion (date is in exclusions of a recurring shift)
  -- This happens when user "edits" a recurring virtual shift - it creates a standalone shift
  SELECT EXISTS (
    SELECT 1
    FROM recurring_shifts
    WHERE user_id = NEW.user_id
      AND exclusions IS NOT NULL
      AND exclusions @> to_jsonb(NEW.shift_date::text)
  ) INTO is_recurring_conversion;

  -- Get the shift owner's display name from user_metadata
  SELECT
    COALESCE(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name',
      email,
      'Noen'
    )
  INTO owner_name
  FROM auth.users
  WHERE id = NEW.user_id;

  IF owner_name IS NULL THEN
    owner_name := 'Noen';
  END IF;

  -- Route to instant notification queue (for 'instant' frequency)
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
    CASE WHEN is_recurring_conversion THEN 'shared_shift_updated' ELSE 'shared_shift_created' END,
    ss.viewer_id,
    NEW.user_id,
    jsonb_build_object(
      'shift_id', NEW.id,
      'shift_date', NEW.shift_date,
      'start_time', NEW.start_time,
      'end_time', NEW.end_time,
      'owner_id', NEW.user_id,
      'owner_name', owner_name
    ),
    CASE WHEN is_recurring_conversion
      THEN 'shift_recurring_converted:' || NEW.id || ':' || ss.viewer_id
      ELSE 'shift_created:' || NEW.id || ':' || ss.viewer_id
    END
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND COALESCE(np.shared_shifts_enabled, true) = true
    AND COALESCE(ss.notification_frequency, 'instant') = 'instant'
  ON CONFLICT (idempotency_key) DO NOTHING;

  -- Route to summary queue (for 'summary' frequency)
  INSERT INTO pending_summary_notifications (
    recipient_id,
    sender_id,
    shift_id,
    shift_date,
    start_time,
    end_time,
    owner_name,
    notification_type
  )
  SELECT
    ss.viewer_id,
    NEW.user_id,
    NEW.id,
    NEW.shift_date,
    NEW.start_time::time,
    NEW.end_time::time,
    owner_name,
    CASE WHEN is_recurring_conversion THEN 'updated' ELSE 'created' END
  FROM shift_shares ss
  LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
  WHERE ss.owner_id = NEW.user_id
    AND COALESCE(np.shared_shifts_enabled, true) = true
    AND ss.notification_frequency = 'summary'
  ON CONFLICT (recipient_id, sender_id, shift_id) DO NOTHING;

  -- Note: 'muted' frequency is handled by the WHERE clause exclusion

  RETURN NEW;
END;
$function$;

-- record_impersonation_attempt: references impersonation_rate_limits
CREATE OR REPLACE FUNCTION public.record_impersonation_attempt(p_admin_user_id uuid, p_success boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  INSERT INTO internal.impersonation_rate_limits (admin_user_id, success)
  VALUES (p_admin_user_id, p_success);

  -- Clean up old records (older than 24 hours) to prevent table bloat
  DELETE FROM internal.impersonation_rate_limits
  WHERE attempted_at < (now() - interval '24 hours');
END;
$function$;

-- run_shift_notification_workers: references notification_queue
CREATE OR REPLACE FUNCTION public.run_shift_notification_workers()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  v_delete_result RECORD;
  v_update_result RECORD;
  v_summary_result RECORD;
  v_has_pending BOOLEAN;
BEGIN
  -- Run all three processors
  SELECT * INTO v_delete_result FROM process_pending_shift_deletes();
  SELECT * INTO v_update_result FROM process_shift_update_events();
  SELECT * INTO v_summary_result FROM process_summary_notifications();

  -- Check if there are any pending notifications to send
  SELECT EXISTS (
    SELECT 1 FROM internal.notification_queue WHERE status = 'pending'
  ) INTO v_has_pending;

  -- If there are pending notifications, trigger the edge function
  IF v_has_pending THEN
    PERFORM net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
  END IF;

  -- Return combined result
  RETURN jsonb_build_object(
    'pending_deletes', jsonb_build_object(
      'owners_processed', COALESCE(v_delete_result.owners_processed, 0),
      'updated', COALESCE(v_delete_result.total_updated, 0),
      'deleted', COALESCE(v_delete_result.total_deleted, 0)
    ),
    'direct_updates', jsonb_build_object(
      'owners_processed', COALESCE(v_update_result.owners_processed, 0),
      'updated', COALESCE(v_update_result.total_updated, 0)
    ),
    'summaries', jsonb_build_object(
      'users_processed', COALESCE(v_summary_result.users_processed, 0),
      'notifications_queued', COALESCE(v_summary_result.notifications_queued, 0)
    ),
    'triggered_send', v_has_pending
  );
END;
$function$;

-- trigger_push_notifications_after_insert: references notification_queue
CREATE OR REPLACE FUNCTION public.trigger_push_notifications_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
  pending_count INTEGER;
BEGIN
  -- Check if there are any pending notifications to process
  SELECT COUNT(*) INTO pending_count
  FROM internal.notification_queue
  WHERE status = 'pending';

  -- Only trigger if there are pending notifications
  IF pending_count > 0 THEN
    -- Get secrets from vault
    SELECT decrypted_secret INTO supabase_url
    FROM vault.decrypted_secrets WHERE name = 'supabase_url';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    -- Only call if we have the required secrets
    IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
      -- Use net.http_post (correct schema for pg_net extension)
      PERFORM net.http_post(
        url := supabase_url || '/functions/v1/send-push-notifications',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
      );
    END IF;
  END IF;

  RETURN NULL;
END;
$function$;

-- trigger_push_notifications_after_share_insert: references notification_queue
CREATE OR REPLACE FUNCTION public.trigger_push_notifications_after_share_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
DECLARE
  has_pending BOOLEAN;
  supabase_url TEXT;
  service_role_key TEXT;
BEGIN
  -- Check if there are any pending share_started notifications
  SELECT EXISTS (
    SELECT 1 FROM internal.notification_queue
    WHERE type = 'share_started' AND status = 'pending'
  ) INTO has_pending;

  IF NOT has_pending THEN
    RETURN NULL;
  END IF;

  -- Get secrets from vault
  SELECT decrypted_secret INTO supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url';

  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  -- Call edge function to process notifications
  IF supabase_url IS NOT NULL AND service_role_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN NULL;
END;
$function$;

-- trigger_send_push_notifications: references notification_queue
CREATE OR REPLACE FUNCTION public.trigger_send_push_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'net', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
  pending_count INT;
BEGIN
  SELECT COUNT(*) INTO pending_count FROM internal.notification_queue WHERE status = 'pending';

  IF pending_count > 0 THEN
    SELECT decrypted_secret INTO supabase_url FROM vault.decrypted_secrets WHERE name = 'supabase_url';
    SELECT decrypted_secret INTO service_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
      -- Use pg_net (net schema)
      PERFORM net.http_post(
        url := supabase_url || '/functions/v1/send-push-notifications',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
      );
    END IF;
  END IF;
END;
$function$;

-- update_push_devices_updated_at: trigger function for push_devices
CREATE OR REPLACE FUNCTION public.update_push_devices_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

-- ==============================================================================
-- PHASE 7: Create RPC functions for push_devices access (for server actions)
-- ==============================================================================

-- Register or update a push device (service_role only via server action)
CREATE OR REPLACE FUNCTION public.register_push_device(
  p_user_id uuid,
  p_fcm_token text,
  p_platform text,
  p_device_id text DEFAULT NULL,
  p_device_model text DEFAULT NULL,
  p_app_version text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  INSERT INTO internal.push_devices (
    user_id,
    fcm_token,
    platform,
    device_id,
    device_model,
    app_version,
    last_seen_at
  ) VALUES (
    p_user_id,
    p_fcm_token,
    p_platform,
    p_device_id,
    p_device_model,
    p_app_version,
    now()
  )
  ON CONFLICT (fcm_token) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    platform = EXCLUDED.platform,
    device_id = EXCLUDED.device_id,
    device_model = EXCLUDED.device_model,
    app_version = EXCLUDED.app_version,
    last_seen_at = now(),
    updated_at = now();
END;
$function$;

-- Unregister a push device (service_role only via server action)
CREATE OR REPLACE FUNCTION public.unregister_push_device(
  p_fcm_token text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  DELETE FROM internal.push_devices
  WHERE fcm_token = p_fcm_token;
END;
$function$;

-- Update push device last seen (service_role only via server action)
CREATE OR REPLACE FUNCTION public.update_push_device_last_seen(
  p_fcm_token text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $function$
BEGIN
  UPDATE internal.push_devices
  SET last_seen_at = now()
  WHERE fcm_token = p_fcm_token;
END;
$function$;

-- ==============================================================================
-- DONE
-- ==============================================================================
