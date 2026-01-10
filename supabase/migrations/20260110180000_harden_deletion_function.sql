-- Migration: Harden prepare_user_for_deletion function
-- Description: Add auth.uid() check to ensure users can only delete their own account
--
-- Security improvement: The function now validates that the calling user
-- is attempting to delete their own account, not someone else's.

CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal
AS $$
BEGIN
  -- Validate input
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  -- SECURITY: Ensure the calling user can only delete their own account
  -- auth.uid() returns the ID of the currently authenticated user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  -- Delete from internal tables that should be cleaned up (not preserved)
  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notification_time_windows WHERE owner_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  -- Note: The following are handled by ON DELETE SET NULL or ON DELETE CASCADE:
  -- - internal.admin_audit_log (SET NULL - preserves audit trail)
  -- - internal.admin_broadcasts (SET NULL - preserves broadcast history)
  -- - internal.impersonation_sessions (SET NULL - preserves session history)
  -- - internal.apple_orphan_notifications (SET NULL)
  -- - All public schema tables (CASCADE via existing FKs)

  -- Log the account deletion preparation (before the user is deleted)
  -- This will have target_user_id set to NULL after auth user deletion
  INSERT INTO internal.admin_audit_log (
    admin_id,
    action,
    target_user_id,
    admin_email,
    target_email,
    metadata
  )
  SELECT
    target_user_id,
    'user_deleted_self',
    target_user_id,
    COALESCE(u.email, u.phone, 'unknown'),
    COALESCE(u.email, u.phone, 'unknown'),
    jsonb_build_object('deletion_type', 'self_service', 'deleted_at', now())
  FROM auth.users u
  WHERE u.id = target_user_id;

END;
$$;

-- Update comment to reflect the security check
COMMENT ON FUNCTION public.prepare_user_for_deletion(uuid) IS
'Prepares a user account for deletion by cleaning up internal tables.
Call this function before calling auth.admin.deleteUser().
The function is SECURITY DEFINER to access internal schema tables.
Security: Validates auth.uid() = target_user_id to prevent users from deleting others.';
