-- Migration: Add impersonation audit log table
-- This table provides granular audit logging for impersonation events,
-- complementing the existing impersonation_sessions table.

-- ==============================================================================
-- PHASE 1: Create the audit log table in internal schema
-- ==============================================================================

CREATE TABLE IF NOT EXISTS internal.impersonation_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES internal.impersonation_sessions(id) ON DELETE SET NULL,
  admin_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  target_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  reason text,
  admin_ip text,
  admin_user_agent text,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT impersonation_audit_log_action_check CHECK (action IN ('start', 'stop', 'action_blocked', 'session_expired'))
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_impersonation_audit_log_session_id
  ON internal.impersonation_audit_log(session_id);
CREATE INDEX IF NOT EXISTS idx_impersonation_audit_log_admin_user_id_created
  ON internal.impersonation_audit_log(admin_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_impersonation_audit_log_target_user_id_created
  ON internal.impersonation_audit_log(target_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_impersonation_audit_log_created_at
  ON internal.impersonation_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_impersonation_audit_log_action
  ON internal.impersonation_audit_log(action);

-- ==============================================================================
-- PHASE 2: Disable RLS (service_role only access)
-- ==============================================================================

ALTER TABLE internal.impersonation_audit_log DISABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- PHASE 3: Grant permissions to service_role
-- ==============================================================================

GRANT ALL ON internal.impersonation_audit_log TO service_role;

-- ==============================================================================
-- PHASE 4: Add missing column to impersonation_sessions if needed
-- ==============================================================================

-- Make admin_refresh_token_enc optional for iOS flow
-- iOS stores admin session in Keychain, doesn't need server-side storage
ALTER TABLE internal.impersonation_sessions
  ALTER COLUMN admin_refresh_token_enc DROP NOT NULL;

-- Set default to empty string for backwards compatibility
ALTER TABLE internal.impersonation_sessions
  ALTER COLUMN admin_refresh_token_enc SET DEFAULT '';

-- ==============================================================================
-- PHASE 5: Add comment for documentation
-- ==============================================================================

COMMENT ON TABLE internal.impersonation_audit_log IS
  'Audit log for impersonation events. Records start/stop events and blocked actions during impersonation.';

COMMENT ON COLUMN internal.impersonation_audit_log.action IS
  'Type of event: start, stop, action_blocked, session_expired';

COMMENT ON COLUMN internal.impersonation_audit_log.metadata IS
  'Additional context: caller_email, target_email, blocked_action_name, etc.';
