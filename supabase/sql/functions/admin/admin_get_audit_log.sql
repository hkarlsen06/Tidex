-- admin_get_audit_log
-- Returns recent audit log entries with optional action and target filters
-- Uses SECURITY DEFINER to access internal schema

CREATE OR REPLACE FUNCTION admin_get_audit_log(
  p_limit INTEGER DEFAULT 50,
  p_action_filter TEXT DEFAULT NULL,
  p_target_filter UUID DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  admin_id UUID,
  admin_email TEXT,
  action TEXT,
  target_user_id UUID,
  target_email TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal'
AS $$
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
$$;

COMMENT ON FUNCTION admin_get_audit_log IS 'Returns recent audit log entries with optional action and target filters. Uses SECURITY DEFINER to access internal schema.';
