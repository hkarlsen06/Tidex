-- MFA Enforcement RLS Policies
-- These restrictive policies ensure users with MFA enrolled must have aal2 to access data.
-- Users without MFA can still access with aal1.
--
-- How it works:
-- - If user has verified MFA factors: only aal2 is allowed
-- - If user has no MFA factors: both aal1 and aal2 are allowed
--
-- IMPORTANT: These are RESTRICTIVE policies, meaning they stack with existing permissive
-- policies. A user must satisfy BOTH the restrictive policy AND at least one permissive policy.

-- user_settings
CREATE POLICY "Require MFA for users who enrolled"
  ON public.user_settings
  AS RESTRICTIVE
  TO authenticated
  USING (
    array[(select auth.jwt()->>'aal')] <@ (
      SELECT
        CASE
          WHEN count(id) > 0 THEN array['aal2']
          ELSE array['aal1', 'aal2']
        END AS aal
      FROM auth.mfa_factors
      WHERE ((select auth.uid()) = user_id) AND status = 'verified'
    )
  );

-- user_shifts
CREATE POLICY "Require MFA for users who enrolled"
  ON public.user_shifts
  AS RESTRICTIVE
  TO authenticated
  USING (
    array[(select auth.jwt()->>'aal')] <@ (
      SELECT
        CASE
          WHEN count(id) > 0 THEN array['aal2']
          ELSE array['aal1', 'aal2']
        END AS aal
      FROM auth.mfa_factors
      WHERE ((select auth.uid()) = user_id) AND status = 'verified'
    )
  );

-- recurring_shifts
CREATE POLICY "Require MFA for users who enrolled"
  ON public.recurring_shifts
  AS RESTRICTIVE
  TO authenticated
  USING (
    array[(select auth.jwt()->>'aal')] <@ (
      SELECT
        CASE
          WHEN count(id) > 0 THEN array['aal2']
          ELSE array['aal1', 'aal2']
        END AS aal
      FROM auth.mfa_factors
      WHERE ((select auth.uid()) = user_id) AND status = 'verified'
    )
  );

-- wage_snapshots
CREATE POLICY "Require MFA for users who enrolled"
  ON public.wage_snapshots
  AS RESTRICTIVE
  TO authenticated
  USING (
    array[(select auth.jwt()->>'aal')] <@ (
      SELECT
        CASE
          WHEN count(id) > 0 THEN array['aal2']
          ELSE array['aal1', 'aal2']
        END AS aal
      FROM auth.mfa_factors
      WHERE ((select auth.uid()) = user_id) AND status = 'verified'
    )
  );

-- profiles
CREATE POLICY "Require MFA for users who enrolled"
  ON public.profiles
  AS RESTRICTIVE
  TO authenticated
  USING (
    array[(select auth.jwt()->>'aal')] <@ (
      SELECT
        CASE
          WHEN count(id) > 0 THEN array['aal2']
          ELSE array['aal1', 'aal2']
        END AS aal
      FROM auth.mfa_factors
      WHERE ((select auth.uid()) = user_id) AND status = 'verified'
    )
  );

-- subscriptions
CREATE POLICY "Require MFA for users who enrolled"
  ON public.subscriptions
  AS RESTRICTIVE
  TO authenticated
  USING (
    array[(select auth.jwt()->>'aal')] <@ (
      SELECT
        CASE
          WHEN count(id) > 0 THEN array['aal2']
          ELSE array['aal1', 'aal2']
        END AS aal
      FROM auth.mfa_factors
      WHERE ((select auth.uid()) = user_id) AND status = 'verified'
    )
  );
