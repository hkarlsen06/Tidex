-- Resolve current Supabase advisor warnings that are safe to address without
-- changing public RPC contracts.

-- Security advisor 0008: internal table has RLS enabled but no explicit policy.
-- The table remains inaccessible to app clients; this policy only documents and
-- enforces that there is no direct client access path.
DROP POLICY IF EXISTS "No direct client access" ON internal.calendar_subscription_tokens;
CREATE POLICY "No direct client access"
  ON internal.calendar_subscription_tokens
  AS RESTRICTIVE
  FOR ALL
  TO anon, authenticated
  USING (false)
  WITH CHECK (false);

-- Security advisor 0029: this helper is used from RLS policies and should not
-- be directly callable as a PostgREST RPC by signed-in users.
REVOKE EXECUTE ON FUNCTION public.check_mfa_aal() FROM authenticated;

-- Performance advisor 0001: add covering indexes for foreign keys that were
-- missing standalone or leading-column coverage.
CREATE INDEX IF NOT EXISTS inbox_events_thread_id_idx
  ON internal.inbox_events (thread_id);

CREATE INDEX IF NOT EXISTS thread_events_actor_user_id_idx
  ON internal.thread_events (actor_user_id);

CREATE INDEX IF NOT EXISTS abuse_reports_message_id_idx
  ON public.abuse_reports (message_id);

CREATE INDEX IF NOT EXISTS abuse_reports_reporter_user_id_idx
  ON public.abuse_reports (reporter_user_id);

CREATE INDEX IF NOT EXISTS abuse_reports_reviewed_by_idx
  ON public.abuse_reports (reviewed_by);

CREATE INDEX IF NOT EXISTS direct_threads_user_high_id_idx
  ON public.direct_threads (user_high_id);

CREATE INDEX IF NOT EXISTS message_reactions_user_id_idx
  ON public.message_reactions (user_id);

CREATE INDEX IF NOT EXISTS messages_reply_to_message_id_idx
  ON public.messages (reply_to_message_id);

CREATE INDEX IF NOT EXISTS messages_sender_user_id_idx
  ON public.messages (sender_user_id);

CREATE INDEX IF NOT EXISTS shift_shares_blocked_by_user_id_idx
  ON public.shift_shares (blocked_by_user_id);

CREATE INDEX IF NOT EXISTS thread_user_state_last_read_message_id_idx
  ON public.thread_user_state (last_read_message_id);

CREATE INDEX IF NOT EXISTS thread_user_state_user_id_idx
  ON public.thread_user_state (user_id);

CREATE INDEX IF NOT EXISTS threads_created_by_user_id_idx
  ON public.threads (created_by_user_id);

CREATE INDEX IF NOT EXISTS threads_last_message_id_idx
  ON public.threads (last_message_id);

CREATE INDEX IF NOT EXISTS threads_last_message_sender_id_idx
  ON public.threads (last_message_sender_id);

-- Performance advisor 0003: wrap auth.uid() in a scalar SELECT so the value is
-- initialized once per statement instead of once per row.
DROP POLICY IF EXISTS "Users can view own events" ON public.events;
CREATE POLICY "Users can view own events"
  ON public.events
  FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert own events" ON public.events;
CREATE POLICY "Users can insert own events"
  ON public.events
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can update own events" ON public.events;
CREATE POLICY "Users can update own events"
  ON public.events
  FOR UPDATE
  TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can delete own events" ON public.events;
CREATE POLICY "Users can delete own events"
  ON public.events
  FOR DELETE
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can view own abuse reports" ON public.abuse_reports;
CREATE POLICY "Users can view own abuse reports"
  ON public.abuse_reports
  FOR SELECT
  TO authenticated
  USING (reporter_user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert own abuse reports" ON public.abuse_reports;
CREATE POLICY "Users can insert own abuse reports"
  ON public.abuse_reports
  FOR INSERT
  TO authenticated
  WITH CHECK (reporter_user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Users can insert own thread state" ON public.thread_user_state;
CREATE POLICY "Users can insert own thread state"
  ON public.thread_user_state
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND public.can_access_thread(thread_id)
  );

DROP POLICY IF EXISTS "Users can update own thread state" ON public.thread_user_state;
CREATE POLICY "Users can update own thread state"
  ON public.thread_user_state
  FOR UPDATE
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND public.can_access_thread(thread_id)
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND public.can_access_thread(thread_id)
  );
