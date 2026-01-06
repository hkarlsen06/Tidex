-- Notification System Redesign Migration
-- This migration implements the new notification system with:
-- 1. App-only enqueueing (no database triggers)
-- 2. 15-minute window batching for non-today shifts
-- 3. Immediate delivery for same-day changes
-- 4. Unified notifications_outbox table

-- ============================================================================
-- PHASE 0: CLEANUP - Remove old notification system components
-- ============================================================================

-- A. Drop all notification-related triggers on user_shifts
DROP TRIGGER IF EXISTS a_on_shift_created_queue_notification ON user_shifts;
DROP TRIGGER IF EXISTS on_shift_deleted_queue_pending ON user_shifts;
DROP TRIGGER IF EXISTS trg_capture_shift_updates_stmt ON user_shifts;
DROP TRIGGER IF EXISTS z_on_shifts_inserted_send_notifications ON user_shifts;

-- B. Drop all notification-related triggers on shift_shares
DROP TRIGGER IF EXISTS on_share_started_notify ON shift_shares;
DROP TRIGGER IF EXISTS z_on_share_inserted_send_notifications ON shift_shares;

-- C. Drop all notification-related triggers on feedback
DROP TRIGGER IF EXISTS a_on_feedback_responded_notify ON feedback;
DROP TRIGGER IF EXISTS a_on_feedback_submitted_notify ON feedback;
DROP TRIGGER IF EXISTS z_on_feedback_inserted_send_notifications ON feedback;
DROP TRIGGER IF EXISTS z_on_feedback_updated_send_notifications ON feedback;

-- D. Drop all notification-related triggers on recurring_shifts
DROP TRIGGER IF EXISTS on_recurring_shift_created_notify ON recurring_shifts;
DROP TRIGGER IF EXISTS on_recurring_shifts_inserted_send_notifications ON recurring_shifts;

-- E. Drop old notification functions (trigger functions)
DROP FUNCTION IF EXISTS public.queue_shift_created_notification() CASCADE;
DROP FUNCTION IF EXISTS public.queue_pending_shift_delete() CASCADE;
DROP FUNCTION IF EXISTS public.capture_shift_updates_stmt() CASCADE;
DROP FUNCTION IF EXISTS public.queue_share_started_notification() CASCADE;
DROP FUNCTION IF EXISTS public.queue_feedback_submitted_notification() CASCADE;
DROP FUNCTION IF EXISTS public.queue_feedback_responded_notification() CASCADE;
DROP FUNCTION IF EXISTS public.queue_recurring_shift_created_notification() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_push_notifications_after_insert() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_push_notifications_after_share_insert() CASCADE;
DROP FUNCTION IF EXISTS public.trigger_send_push_notifications() CASCADE;

-- F. Drop old notification worker/processor functions
DROP FUNCTION IF EXISTS public.process_pending_shift_deletes() CASCADE;
DROP FUNCTION IF EXISTS public.process_shift_update_events() CASCADE;
DROP FUNCTION IF EXISTS public.process_summary_notifications() CASCADE;
DROP FUNCTION IF EXISTS public.claim_pending_notifications() CASCADE;
DROP FUNCTION IF EXISTS public.run_shift_notification_workers() CASCADE;

-- G. Drop old notification tables
DROP TABLE IF EXISTS public.pending_shift_deletes CASCADE;
DROP TABLE IF EXISTS public.shift_update_events CASCADE;
DROP TABLE IF EXISTS public.pending_summary_notifications CASCADE;
DROP TABLE IF EXISTS internal.notification_queue CASCADE;

-- ============================================================================
-- PHASE 1: Create new tables
-- ============================================================================

-- A. notification_time_windows - Aggregates non-today shift mutations per 15-min window
CREATE TABLE internal.notification_time_windows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  window_start TIMESTAMPTZ NOT NULL,

  -- Mutation counts
  added_count INT NOT NULL DEFAULT 0,
  updated_count INT NOT NULL DEFAULT 0,
  deleted_count INT NOT NULL DEFAULT 0,

  -- Affected dates (capped at 31 for bounded storage)
  affected_dates DATE[] NOT NULL DEFAULT '{}',
  truncated_dates BOOLEAN NOT NULL DEFAULT FALSE,

  -- Processing status
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'finalized')),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Unique per owner per window
  UNIQUE (owner_id, window_start)
);

CREATE INDEX idx_ntw_status_window ON internal.notification_time_windows (status, window_start)
  WHERE status = 'pending';
CREATE INDEX idx_ntw_owner ON internal.notification_time_windows (owner_id);

-- B. notifications_outbox - Unified delivery queue with pre-built messages
CREATE TABLE internal.notifications_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Targeting
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,  -- NULL for admin broadcasts
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  broadcast_id UUID,  -- For admin broadcasts

  -- Notification type for routing/analytics
  notification_type TEXT NOT NULL,

  -- Delivery timing
  due_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Status tracking
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'skipped')),
  claimed_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  attempts INT NOT NULL DEFAULT 0,  -- Track retry attempts

  -- Pre-computed message (Norwegian)
  title TEXT NOT NULL,
  body TEXT NOT NULL,

  -- Deep link and metadata (NOT for rendering)
  data_payload JSONB NOT NULL DEFAULT '{}',

  -- Idempotency
  idempotency_key TEXT NOT NULL UNIQUE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_outbox_due ON internal.notifications_outbox (status, due_at)
  WHERE status = 'pending';
CREATE INDEX idx_outbox_recipient ON internal.notifications_outbox (recipient_id);
CREATE INDEX idx_outbox_broadcast ON internal.notifications_outbox (broadcast_id)
  WHERE broadcast_id IS NOT NULL;

-- ============================================================================
-- PHASE 2: Modify existing tables
-- ============================================================================

-- C. Add muted column to shift_shares
ALTER TABLE shift_shares ADD COLUMN IF NOT EXISTS muted BOOLEAN NOT NULL DEFAULT FALSE;

-- Migrate data: notification_frequency = 'muted' -> muted = true
UPDATE shift_shares SET muted = TRUE WHERE notification_frequency = 'muted';

-- ============================================================================
-- PHASE 3: Create new SQL functions
-- ============================================================================

-- D. Atomic window upsert function
CREATE OR REPLACE FUNCTION internal.upsert_notification_window(
  p_owner_id UUID,
  p_window_start TIMESTAMPTZ,
  p_event_type TEXT,
  p_shift_date DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
BEGIN
  INSERT INTO notification_time_windows (
    owner_id, window_start,
    added_count, updated_count, deleted_count,
    affected_dates
  )
  VALUES (
    p_owner_id, p_window_start,
    CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
    ARRAY[p_shift_date]
  )
  ON CONFLICT (owner_id, window_start) DO UPDATE SET
    added_count = notification_time_windows.added_count +
      CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
    updated_count = notification_time_windows.updated_count +
      CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
    deleted_count = notification_time_windows.deleted_count +
      CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
    affected_dates = CASE
      WHEN array_length(notification_time_windows.affected_dates, 1) >= 31 THEN
        notification_time_windows.affected_dates
      WHEN p_shift_date = ANY(notification_time_windows.affected_dates) THEN
        notification_time_windows.affected_dates
      ELSE
        array_append(notification_time_windows.affected_dates, p_shift_date)
    END,
    truncated_dates = CASE
      WHEN array_length(notification_time_windows.affected_dates, 1) >= 31 THEN TRUE
      ELSE notification_time_windows.truncated_dates
    END,
    updated_at = now();
END;
$$;

-- E. Process notification windows - fans out to outbox when window ends
CREATE OR REPLACE FUNCTION internal.process_notification_windows()
RETURNS TABLE(windows_processed INT, outbox_rows_created INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window RECORD;
  v_owner_name TEXT;
  v_title TEXT;
  v_body TEXT;
  v_action_parts TEXT[];
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

    -- Build Norwegian message
    -- Format: "Alvilde slettet 2 vakter, la til 2 vakter, og endret 1 vakt"
    v_action_parts := '{}';

    IF v_window.deleted_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'slettet ' || v_window.deleted_count ||
        CASE WHEN v_window.deleted_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    IF v_window.added_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'la til ' || v_window.added_count ||
        CASE WHEN v_window.added_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    IF v_window.updated_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'endret ' || v_window.updated_count ||
        CASE WHEN v_window.updated_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    -- Build title with Norwegian conjunction rules
    IF array_length(v_action_parts, 1) = 1 THEN
      v_title := v_owner_name || ' ' || v_action_parts[1];
    ELSIF array_length(v_action_parts, 1) = 2 THEN
      v_title := v_owner_name || ' ' || v_action_parts[1] || ' og ' || v_action_parts[2];
    ELSE
      v_title := v_owner_name || ' ' || v_action_parts[1] || ', ' ||
                 v_action_parts[2] || ', og ' || v_action_parts[3];
    END IF;

    v_body := 'Trykk for å se endringene';

    -- Fan out to each non-muted recipient
    INSERT INTO internal.notifications_outbox (
      owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key
    )
    SELECT
      v_window.owner_id,
      ss.viewer_id,
      'shared_shift_changes',
      v_window_end,  -- due_at = window_end for clarity
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'shared_shift_changes',
        'owner_id', v_window.owner_id,
        'shift_dates', to_jsonb(v_window.affected_dates),  -- JSON array, not comma string
        'added_count', v_window.added_count,
        'updated_count', v_window.updated_count,
        'deleted_count', v_window.deleted_count
      ),
      -- Stable idempotency: owner_id:recipient_id:window_start
      v_window.owner_id || ':' || ss.viewer_id || ':' || v_window.window_start::text
    FROM shift_shares ss
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

-- F. Claim outbox notifications for edge function
CREATE OR REPLACE FUNCTION internal.claim_outbox_notifications(batch_size INT DEFAULT 50)
RETURNS SETOF internal.notifications_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
BEGIN
  -- Reset stale claims (stuck > 15 minutes) with bounded retries
  UPDATE notifications_outbox
  SET
    status = CASE
      WHEN attempts >= 10 THEN 'failed'  -- Max 10 attempts, then permanent failure
      ELSE 'pending'
    END,
    claimed_at = NULL,
    attempts = attempts + 1,
    error_message = CASE
      WHEN attempts >= 10 THEN 'Max retry attempts exceeded'
      ELSE error_message
    END
  WHERE status = 'sending'
    AND claimed_at < now() - INTERVAL '15 minutes';

  -- Claim and return batch (only pending with < 10 attempts)
  RETURN QUERY
  UPDATE notifications_outbox
  SET status = 'sending', claimed_at = now()
  WHERE id IN (
    SELECT id FROM notifications_outbox
    WHERE status = 'pending'
      AND due_at <= now()
      AND attempts < 10
    ORDER BY due_at
    LIMIT batch_size
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;

-- G. New notification workers orchestrator
CREATE OR REPLACE FUNCTION public.run_notification_workers()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window_result RECORD;
  v_has_pending BOOLEAN;
BEGIN
  -- Process due windows (fans out to outbox)
  SELECT * INTO v_window_result FROM internal.process_notification_windows();

  -- Check for pending outbox notifications that are due
  SELECT EXISTS (
    SELECT 1 FROM internal.notifications_outbox
    WHERE status = 'pending' AND due_at <= now()
  ) INTO v_has_pending;

  -- Trigger edge function if pending notifications exist
  IF v_has_pending THEN
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
    'windows_processed', COALESCE(v_window_result.windows_processed, 0),
    'outbox_rows_created', COALESCE(v_window_result.outbox_rows_created, 0),
    'triggered_send', v_has_pending
  );
END;
$$;

-- ============================================================================
-- PHASE 4: Grant permissions
-- ============================================================================

-- Grant execute on new functions to service_role
GRANT EXECUTE ON FUNCTION internal.upsert_notification_window TO service_role;
GRANT EXECUTE ON FUNCTION internal.process_notification_windows TO service_role;
GRANT EXECUTE ON FUNCTION internal.claim_outbox_notifications TO service_role;
GRANT EXECUTE ON FUNCTION public.run_notification_workers TO service_role;

-- Grant table access
GRANT SELECT, INSERT, UPDATE, DELETE ON internal.notification_time_windows TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON internal.notifications_outbox TO service_role;

-- ============================================================================
-- PHASE 5: Helper functions for app-side enqueueing
-- ============================================================================

-- H. Get admin user IDs for feedback notifications
CREATE OR REPLACE FUNCTION public.get_admin_user_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $$
  SELECT id FROM auth.users
  WHERE raw_app_meta_data->>'role' = 'admin'
    AND deleted_at IS NULL;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_user_ids TO service_role;

-- ============================================================================
-- PHASE 6: Drop deprecated columns from existing tables
-- ============================================================================

-- I. Drop old notification_frequency column from shift_shares (now using muted boolean)
ALTER TABLE shift_shares DROP COLUMN IF EXISTS notification_frequency;

-- J. Drop old summary_time column from notification_preferences (no longer used)
ALTER TABLE notification_preferences DROP COLUMN IF EXISTS summary_time;
