-- admin_log_action
-- SECURITY DEFINER function for logging admin actions to audit log
-- Only callable via service role (bypasses RLS)
-- Server actions pass verified admin info (never from client)
-- Emails are denormalized at write time for future-proof rendering

CREATE OR REPLACE FUNCTION admin_log_action(
  p_admin_id UUID,
  p_admin_email TEXT,
  p_action TEXT,
  p_target_id UUID DEFAULT NULL,
  p_target_email TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $$
DECLARE
  v_log_id UUID;
BEGIN
  -- Validate action is in allowed list
  IF p_action NOT IN (
    'user_lookup', 'user_ban', 'user_unban',
    'grant_admin', 'revoke_admin',
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
$$;

-- Revoke execute from public, only service role should call this
REVOKE EXECUTE ON FUNCTION admin_log_action FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_log_action FROM authenticated;

COMMENT ON FUNCTION admin_log_action IS 'Logs admin actions to audit log. SECURITY DEFINER - only callable via service role.';
