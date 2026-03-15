-- Function: prepare_user_for_deletion
-- Description: Prepares a user account for deletion by cleaning up internal tables.
--              Call this function before calling auth.admin.deleteUser().
--
-- Usage: SELECT public.prepare_user_for_deletion('user-uuid-here');
--
-- Security: SECURITY DEFINER to access internal schema tables.
--           Validates auth.uid() = target_user_id to prevent users from deleting others.

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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  -- Clear report reviewer references, then remove reports that cannot outlive either side.
  UPDATE public.abuse_reports
  SET reviewed_by = NULL
  WHERE reviewed_by = target_user_id;

  DELETE FROM public.abuse_reports
  WHERE reporter_user_id = target_user_id
     OR reported_user_id = target_user_id;

  -- Delete direct-message threads involving the user. This cascades memberships,
  -- thread state, messages, and message_attachments for those threads.
  DELETE FROM public.threads t
  USING public.direct_threads dt
  WHERE t.id = dt.thread_id
    AND (
      dt.user_low_id = target_user_id
      OR dt.user_high_id = target_user_id
    );

  -- Remove remaining messaging rows in non-direct threads.
  DELETE FROM public.thread_user_state WHERE user_id = target_user_id;
  DELETE FROM public.thread_memberships WHERE user_id = target_user_id;
  DELETE FROM public.messages WHERE sender_user_id = target_user_id;

  -- Delete from internal tables that should be cleaned up (not preserved)
  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  -- Note: The following are handled by ON DELETE SET NULL or ON DELETE CASCADE:
  -- - internal.admin_audit_log (SET NULL - preserves audit trail)
  -- - internal.admin_broadcasts (SET NULL - preserves broadcast history)
  -- - internal.impersonation_sessions (SET NULL - preserves session history)
  -- - internal.apple_orphan_notifications (SET NULL)
  -- - public.jobs and dependent tables (CASCADE from auth.users)

  -- Log the account deletion preparation (before the user is deleted)
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

GRANT EXECUTE ON FUNCTION public.prepare_user_for_deletion(uuid) TO authenticated;

COMMENT ON FUNCTION public.prepare_user_for_deletion(uuid) IS
'Prepares a user account for deletion by cleaning up internal tables.
Call this function before calling auth.admin.deleteUser().
The function is SECURITY DEFINER to access internal schema tables.
Security: Validates auth.uid() = target_user_id to prevent users from deleting others.';
