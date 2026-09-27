-- Shared-shift access fixes.
--
-- 1. Direct RLS reads of a friend's shifts, recurring shifts, settings and wage
--    snapshots ignored blocks, and wage snapshots ignored show_earnings.
--    The app and Wagey read friend data through SECURITY DEFINER RPCs or the
--    service role, so these policies only matter for direct REST reads.
-- 2. user_settings_all_merged was FOR ALL with shared viewers in USING, so a
--    viewer could update or delete the owner's row. Writes are now own-row only.
-- 3. The blocked party could delete the blocked shift_shares rows and share
--    again, and direct INSERT skipped the share limit in manage_sharing_action.
--    Only the blocker can delete blocked rows, direct INSERT has no policy, and
--    manage_sharing_action refuses to share across a block.

-- 1. Shared reads respect blocks (and show_earnings for wage snapshots)

DROP POLICY IF EXISTS "Users can view shifts (own or shared)" ON public.user_shifts;
CREATE POLICY "Users can view shifts (own or shared)"
  ON public.user_shifts
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.shift_shares ss
      WHERE ss.owner_id = user_shifts.user_id
        AND ss.viewer_id = (SELECT auth.uid())
        AND ss.blocked_by_user_id IS NULL
    )
  );

DROP POLICY IF EXISTS "Recurring shifts read" ON public.recurring_shifts;
CREATE POLICY "Recurring shifts read"
  ON public.recurring_shifts
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.shift_shares ss
      WHERE ss.owner_id = recurring_shifts.user_id
        AND ss.viewer_id = (SELECT auth.uid())
        AND ss.blocked_by_user_id IS NULL
    )
  );

DROP POLICY IF EXISTS "Users can read wage snapshots (own or shared)" ON public.wage_snapshots;
CREATE POLICY "Users can read wage snapshots (own or shared)"
  ON public.wage_snapshots
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.shift_shares ss
      WHERE ss.owner_id = wage_snapshots.user_id
        AND ss.viewer_id = (SELECT auth.uid())
        AND ss.blocked_by_user_id IS NULL
        AND ss.show_earnings
    )
  );

-- 2. user_settings: shared viewers can read, only the owner can write

DROP POLICY IF EXISTS user_settings_all_merged ON public.user_settings;

CREATE POLICY user_settings_select_own_or_shared
  ON public.user_settings
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.shift_shares ss
      WHERE ss.owner_id = user_settings.user_id
        AND ss.viewer_id = (SELECT auth.uid())
        AND ss.blocked_by_user_id IS NULL
    )
  );

CREATE POLICY user_settings_insert_own
  ON public.user_settings
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY user_settings_update_own
  ON public.user_settings
  FOR UPDATE
  TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY user_settings_delete_own
  ON public.user_settings
  FOR DELETE
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- 3. shift_shares: blocks survive the blocked party, inserts go through the RPC

DROP POLICY IF EXISTS "Owner or viewer can delete shares" ON public.shift_shares;
CREATE POLICY "Owner or viewer can delete shares"
  ON public.shift_shares
  FOR DELETE
  TO authenticated
  USING (
    (owner_id = (SELECT auth.uid()) OR viewer_id = (SELECT auth.uid()))
    AND (
      blocked_by_user_id IS NULL
      OR blocked_by_user_id = (SELECT auth.uid())
    )
  );

-- manage_sharing_action and the admin share RPCs are SECURITY DEFINER and
-- owned by postgres (BYPASSRLS), so they still insert.
DROP POLICY IF EXISTS "Owner can create shares" ON public.shift_shares;

CREATE OR REPLACE FUNCTION public.manage_sharing_action(p_action text, p_identifier text DEFAULT NULL::text, p_recipient_id uuid DEFAULT NULL::uuid, p_show_earnings boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_limit integer := 5;
  v_target_id uuid;
  v_normalized text;
  v_identifier text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT CASE COALESCE(tier, 'free')
    WHEN 'max' THEN 200
    WHEN 'pro' THEN 200
    ELSE 5
  END
  INTO v_limit
  FROM public.user_entitlements
  WHERE user_id = v_user_id;

  IF (SELECT COUNT(*) FROM public.shift_shares WHERE owner_id = v_user_id) >= v_limit THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Du har nådd maksimalt antall delinger for ditt abonnement'
    );
  END IF;

  IF p_action = 'createShare' THEN
    IF p_identifier IS NULL OR btrim(p_identifier) = '' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Vennligst oppgi en gyldig e-post, telefonnummer eller brukernavn'
      );
    END IF;

    v_identifier := btrim(p_identifier);

    IF position('@' IN v_identifier) > 0 AND left(v_identifier, 1) <> '@' THEN
      SELECT id INTO v_target_id
      FROM auth.users
      WHERE lower(email) = lower(v_identifier)
      LIMIT 1;
    ELSE
      v_identifier := lower(v_identifier);
      IF left(v_identifier, 1) = '@' THEN
        v_identifier := substr(v_identifier, 2);
      END IF;

      SELECT id INTO v_target_id
      FROM public.profiles
      WHERE username = v_identifier
      LIMIT 1;

      IF v_target_id IS NULL THEN
        v_normalized := regexp_replace(p_identifier, '\D', '', 'g');
        IF length(v_normalized) = 8 THEN
          v_normalized := '47' || v_normalized;
        ELSIF left(v_normalized, 2) = '00' THEN
          v_normalized := substr(v_normalized, 3);
        END IF;

        SELECT id INTO v_target_id
        FROM auth.users
        WHERE phone = v_normalized
        LIMIT 1;
      END IF;
    END IF;
  ELSIF p_action = 'shareBack' THEN
    v_target_id := p_recipient_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Ugyldig handling');
  END IF;

  IF v_target_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Fant ingen bruker med denne e-posten, telefonnummeret eller brukernavnet'
    );
  END IF;

  IF v_target_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele med deg selv');
  END IF;

  -- A block lives on the pair's shift_shares rows. Refuse a new share in
  -- either direction while one exists.
  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE (
      (owner_id = v_user_id AND viewer_id = v_target_id)
      OR (owner_id = v_target_id AND viewer_id = v_user_id)
    )
      AND blocked_by_user_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du kan ikke dele vaktene dine med denne brukeren');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.shift_shares
    WHERE owner_id = v_user_id
      AND viewer_id = v_target_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Du deler allerede vaktene dine med denne brukeren');
  END IF;

  INSERT INTO public.shift_shares (
    owner_id,
    viewer_id,
    show_earnings,
    muted,
    owner_muted
  ) VALUES (
    v_user_id,
    v_target_id,
    COALESCE(p_show_earnings, false),
    false,
    false
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;
