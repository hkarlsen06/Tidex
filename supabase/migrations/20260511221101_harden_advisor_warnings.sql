-- Harden the warnings surfaced by Supabase advisors:
-- - public profile-picture URLs do not require broad object listing policies
-- - the app does not use pg_graphql, so keep app data out of GraphQL
-- - SECURITY DEFINER functions should not inherit EXECUTE from PUBLIC/anon
-- - trigger/internal helpers should not be directly callable by app clients

DROP POLICY IF EXISTS "Anyone can view profile pictures" ON storage.objects;
DROP POLICY IF EXISTS "Public can view profile pictures" ON storage.objects;

DROP EXTENSION IF EXISTS pg_graphql;

DO $$
DECLARE
  target_function regprocedure;
BEGIN
  FOR target_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'internal')
      AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', target_function);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', target_function);
  END LOOP;
END;
$$;

-- Keep intentional authenticated RPCs callable after removing inherited PUBLIC grants.
GRANT EXECUTE ON FUNCTION public.admin_count_target_users_active() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_count_target_users_all(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_count_target_users_pro() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_share_api(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_share_api(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_audit_log_api(integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_broadcast_history(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_broadcast_history_api() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_feedback_api(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_reports_api(integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_shares_api(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_subscribers_api(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_target_users_active() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_target_users_all(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_target_users_pro() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_user_locales(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_users_api(integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_log_action_rpc(text, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_manage_trial_api(uuid, text, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_preview_notification_target_api(text, uuid[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_respond_feedback_api(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_broadcast_api(text, text, text, text, text, text, text, uuid[], boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_toggle_grandfathered_api(uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_report_status_api(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_share_api(uuid, boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user_pair(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_thread(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_create_direct_thread(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_post_to_thread(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_message_attachment_object(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_upload_message_attachment_object(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_abuse_report(uuid, uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_inbox_sync_snapshot_v2(integer, timestamp with time zone, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_message_payload(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_message_sync_payload_v2(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_entitlement() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_profile_username() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_sharer_preview_payloads(uuid[], date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_sharers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_app_account_token(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_shared_month_payload(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sharing_friends_api() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_types() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_version_for_date(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tariff_versions(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_thread_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_thread_sync_snapshot_v2(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_direct_message_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_entitlement_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_shift_storage_entitlement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_wagey_bonus(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_wagey_invocation(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_user_pair_abuse_blocked(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_inbox_events_v2(bigint, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_threads(integer, timestamp with time zone, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_thread_events_v2(uuid, bigint, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_thread_messages(uuid, integer, timestamp with time zone, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_thread_messages_v2(uuid, integer, timestamp with time zone, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_sharing_action(text, text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_thread_read(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_user_for_deletion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.queue_thread_typing_notification(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device(text, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_sharing_screenshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_thread_screenshot(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_message(uuid, uuid, text, uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_profile_username(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_thread_muted(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user_pair(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_device(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_push_device_last_seen(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_has_any_shifts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_has_shift_in_month(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_has_verified_mfa_factors() TO authenticated;

-- Backend-only RPCs used by Edge Functions with service-role clients.
GRANT EXECUTE ON FUNCTION internal.claim_outbox_notifications(integer) TO service_role;
GRANT EXECUTE ON FUNCTION internal.get_unread_direct_message_counts(uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_log_action(uuid, text, text, uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_admin_user_ids() TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_wagey_bonus(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_user_entitlement_status(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_users_by_ids(uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.find_user_by_email(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO service_role;

-- These are trigger functions, policy helpers, or internal builders. They run
-- through triggers/definer functions and should not be exposed as direct RPCs.
DO $$
DECLARE
  target_function regprocedure;
BEGIN
  FOR target_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosecdef
      AND (
        n.nspname = 'internal'
        OR (n.nspname = 'public' AND p.proname IN (
          'admin_log_action',
          'assert_is_admin',
          'assert_is_superadmin',
          'assign_job_id_and_validate_owner',
          'check_mfa_aal',
          'enforce_shift_shares_update_columns',
          'ensure_default_job',
          'ensure_job_currency_on_insert',
          'get_admin_user_ids',
          'handle_new_user',
          'is_admin',
          'is_superadmin',
          'queue_abuse_report_notification',
          'queue_feedback_responded_notification',
          'queue_feedback_submitted_notification',
          'queue_message_reaction_notification',
          'queue_share_started_notification',
          'queue_thread_message_notification',
          'reject_job_currency_change',
          'rls_auto_enable',
          'set_wage_snapshots_deleted_at_from_job',
          'sync_default_job_to_legacy_settings',
          'sync_legacy_settings_to_default_job',
          'sync_shift_shares_hidden_legacy_blocked',
          'update_thread_unread_counts_on_message_insert',
          'update_thread_unread_counts_on_message_soft_delete'
        ))
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', target_function);
  END LOOP;
END;
$$;
