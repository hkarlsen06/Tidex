-- Admin console: remove a reported message. Same soft delete as delete_message, without the sender check.

ALTER TABLE internal.admin_audit_log DROP CONSTRAINT admin_audit_log_action_check;
ALTER TABLE internal.admin_audit_log ADD CONSTRAINT admin_audit_log_action_check CHECK (action = ANY (ARRAY[
  'user_lookup', 'user_ban', 'user_unban', 'grant_admin', 'revoke_admin', 'grant_grandfathered',
  'revoke_grandfathered', 'create_trial_subscription', 'revoke_trial_subscription', 'broadcast_sent',
  'user_list_viewed', 'admin_action_failed', 'sql_executed', 'shift_share_created',
  'shift_share_updated', 'shift_share_deleted', 'user_deleted_self', 'message_deleted'
]));

CREATE OR REPLACE FUNCTION public.admin_delete_message_api(p_message_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
DECLARE
  v_thread_id uuid;
  v_sender_user_id uuid;
  v_latest public.messages%ROWTYPE;
BEGIN
  PERFORM public.assert_is_admin();

  SELECT thread_id, sender_user_id INTO v_thread_id, v_sender_user_id
  FROM public.messages
  WHERE id = p_message_id AND deleted_at IS NULL;

  IF v_thread_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Message not found or already deleted');
  END IF;

  -- Lets the soft delete trigger emit the sync event that removes the message on devices.
  PERFORM set_config('tidex.messaging_v2_emit_message_soft_delete', 'true', true);

  UPDATE public.messages SET deleted_at = now() WHERE id = p_message_id;

  SELECT * INTO v_latest
  FROM public.messages m
  WHERE m.thread_id = v_thread_id AND m.deleted_at IS NULL
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1;

  UPDATE public.threads t
  SET
    last_message_id = v_latest.id,
    last_message_sender_id = v_latest.sender_user_id,
    last_message_at = COALESCE(v_latest.created_at, t.created_at)
  WHERE t.id = v_thread_id;

  PERFORM public.admin_log_action_rpc(
    'message_deleted',
    v_sender_user_id,
    NULL,
    jsonb_build_object('message_id', p_message_id, 'thread_id', v_thread_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_delete_message_api(uuid) TO authenticated;
