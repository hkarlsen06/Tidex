-- Function: get_admin_user_ids
-- Description: Returns UUIDs of all admin users for feedback notifications
-- Used by: submitFeedback server action (lib/notifications/enqueue.ts)
-- Schema: public
--
-- This function is called when a user submits feedback to notify all admins.
-- It queries auth.users for users with role='admin' in app_metadata.
--
-- Returns:
--   SETOF UUID - All admin user IDs
--
-- Security:
--   - SECURITY DEFINER to access auth.users
--   - Only returns users where deleted_at IS NULL

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

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.get_admin_user_ids TO service_role;
