-- Expand account deletion cleanup so auth user deletion is not blocked by
-- messaging or abuse-report foreign keys.

CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal
AS $$
BEGIN
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF auth.uid() != target_user_id THEN
    RAISE EXCEPTION 'You can only delete your own account';
  END IF;

  UPDATE public.abuse_reports
  SET reviewed_by = NULL
  WHERE reviewed_by = target_user_id;

  DELETE FROM public.abuse_reports
  WHERE reporter_user_id = target_user_id
     OR reported_user_id = target_user_id;

  DELETE FROM public.threads t
  USING public.direct_threads dt
  WHERE t.id = dt.thread_id
    AND (
      dt.user_low_id = target_user_id
      OR dt.user_high_id = target_user_id
    );

  DELETE FROM public.thread_user_state WHERE user_id = target_user_id;
  DELETE FROM public.thread_memberships WHERE user_id = target_user_id;
  DELETE FROM public.messages WHERE sender_user_id = target_user_id;

  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

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
'Prepares a user account for deletion by cleaning up internal and public tables that would otherwise block auth user deletion. Call this function before calling auth.admin.deleteUser().';
