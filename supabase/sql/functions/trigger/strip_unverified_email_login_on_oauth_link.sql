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
