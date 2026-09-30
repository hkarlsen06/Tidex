-- Follow-ups from the review of 20260930170000_security_audit_hardening.
-- 1. The OAuth-link trigger also moves the account email to the proven address
--    and removes MFA factors, passkeys, calendar tokens, push devices and
--    outgoing shares, so a pre-created account can't keep access after
--    the real owner links it.
-- 2. prepare_user_for_deletion requires aal2 for users with MFA, like
--    delete-account.
-- 3. PostgREST rejects access tokens whose session was deleted or has passed
--    not_after.

-- Function: internal.strip_unverified_email_login_on_oauth_link
-- Description: Pre-account-takeover mitigation. Runs after GoTrue inserts a
--              google or apple identity. If the same user still has an email
--              identity whose address was never verified, the account may have
--              been created by someone who signed up with an address they do
--              not own (MAILER_AUTOCONFIRM=true skips verification). The
--              function then removes everything that would let that person keep
--              access after the OAuth owner takes the account over:
--              - the unverified email identity and the password (GoTrue stores
--                "no password" as NULL), plus pending email change and one-time
--                tokens;
--              - all existing sessions (refresh tokens and AMR claims cascade);
--              - MFA factors and passkeys, which could lock the new owner out
--                or let the old holder back in;
--              - calendar feed tokens, push devices and outgoing shift shares,
--                which keep sending the account's data to whoever set them up.
--              The account email moves to the address the provider just
--              proved, or to NULL if another user has it. Otherwise GoTrue
--              would later link the real owner of the old unverified address
--              to this account by its users.email fallback
--              (internal/models/linking.go), which matters when the new
--              identity has a different address, e.g. a manual link.
--              This mirrors GoTrue's RemoveUnconfirmedIdentities and
--              UpdateUserEmailFromIdentities (internal/models/user.go), which
--              do not run when autoconfirm marks the user as confirmed.
--              GoTrue creates the session for the sign-in in progress after it
--              inserts the identity, so that session survives. GoTrue does not
--              write users.email while linking, so the new email sticks.
-- Trade-off: an unverified-email user who links Google or Apple by hand from
--            settings loses the password, MFA, passkeys, calendar feeds and
--            outgoing shares, and is signed out. Push devices register again
--            on the next app launch.
-- Used by: AFTER INSERT trigger on auth.identities.
-- Security: SECURITY DEFINER (owner postgres can modify the auth and internal
--           tables). EXECUTE is revoked from public, anon and authenticated.
--           The trigger fires as supabase_auth_admin without needing EXECUTE.

CREATE OR REPLACE FUNCTION internal.strip_unverified_email_login_on_oauth_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_removed integer;
  v_new_email text := NULLIF(lower(NEW.email), '');
BEGIN
  DELETE FROM auth.identities
  WHERE user_id = NEW.user_id
    AND provider = 'email'
    AND id <> NEW.id
    AND COALESCE(identity_data ->> 'email_verified', '') <> 'true';

  GET DIAGNOSTICS v_removed = ROW_COUNT;

  IF v_removed = 0 THEN
    RETURN NULL;
  END IF;

  IF v_new_email IS NOT NULL AND EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = v_new_email
      AND u.id <> NEW.user_id
      AND u.is_sso_user = false
  ) THEN
    v_new_email := NULL;
  END IF;

  UPDATE auth.users
  SET
    encrypted_password = NULL,
    email = v_new_email,
    email_confirmed_at = CASE WHEN v_new_email IS NULL THEN NULL ELSE COALESCE(email_confirmed_at, now()) END,
    email_change = '',
    email_change_token_new = '',
    email_change_token_current = '',
    email_change_confirm_status = 0,
    recovery_token = '',
    confirmation_token = ''
  WHERE id = NEW.user_id;

  DELETE FROM auth.one_time_tokens WHERE user_id = NEW.user_id;

  -- Deleting a session cascades to auth.refresh_tokens and auth.mfa_amr_claims.
  DELETE FROM auth.sessions WHERE user_id = NEW.user_id;

  -- Cascades to auth.mfa_challenges.
  DELETE FROM auth.mfa_factors WHERE user_id = NEW.user_id;
  DELETE FROM auth.webauthn_credentials WHERE user_id = NEW.user_id;

  UPDATE internal.calendar_subscription_tokens
  SET revoked_at = now()
  WHERE user_id = NEW.user_id
    AND revoked_at IS NULL;

  DELETE FROM internal.push_devices WHERE user_id = NEW.user_id;

  DELETE FROM public.shift_shares WHERE owner_id = NEW.user_id;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION internal.strip_unverified_email_login_on_oauth_link() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_identity_oauth_linked ON auth.identities;
CREATE TRIGGER on_auth_identity_oauth_linked
AFTER INSERT ON auth.identities
FOR EACH ROW
WHEN (NEW.provider IN ('google', 'apple'))
EXECUTE FUNCTION internal.strip_unverified_email_login_on_oauth_link();

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

  -- An admin impersonating a user must not be able to delete that user's account.
  IF public.is_impersonation_session() THEN
    RAISE EXCEPTION 'Accounts cannot be deleted during an impersonation session'
      USING ERRCODE = '42501';
  END IF;

  -- Users with a verified MFA factor need an aal2 session. delete-account checks
  -- this too, but authenticated users can call this RPC directly.
  IF public.check_mfa_aal() IS NOT TRUE THEN
    RAISE EXCEPTION 'Multi-factor authentication required'
      USING ERRCODE = '42501';
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

-- Function: public.enforce_live_session
-- Description: PostgREST pre-request check (authenticator role setting
--              pgrst.db_pre_request). GoTrue access tokens stay valid until
--              they expire (JWT_EXP=3600), even after sign-out or after
--              internal.strip_unverified_email_login_on_oauth_link deletes the
--              session. This rejects a REST request with 401 when the token's
--              session_id no longer exists in auth.sessions or is past its
--              not_after (impersonation sessions set not_after).
--              Tokens without a session_id (anon, service_role, publishable
--              key) pass through unchanged.
-- Limits: Storage, Realtime and edge functions do not run this check.
-- Security: SECURITY DEFINER so the request role can read auth.sessions.
--           It is in public because anon and authenticated have no USAGE on
--           internal. Calling it as an RPC only checks the caller's own
--           session.

CREATE OR REPLACE FUNCTION public.enforce_live_session()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_session_id text := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id';
BEGIN
  IF v_session_id IS NULL THEN
    RETURN;
  END IF;

  IF v_session_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR NOT EXISTS (
      SELECT 1
      FROM auth.sessions s
      WHERE s.id = v_session_id::uuid
        AND (s.not_after IS NULL OR s.not_after > now())
    )
  THEN
    RAISE SQLSTATE 'PGRST'
      USING MESSAGE = '{"code":"session_not_found","message":"Session has ended. Sign in again."}',
            DETAIL = '{"status":401,"headers":{"WWW-Authenticate":"Bearer error=\"invalid_token\""}}';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.enforce_live_session() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enforce_live_session() TO anon, authenticated, service_role;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.enforce_live_session';
NOTIFY pgrst, 'reload config';
