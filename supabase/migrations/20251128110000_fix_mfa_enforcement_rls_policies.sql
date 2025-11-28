-- Fix MFA Enforcement RLS Policies
-- The previous migration directly queried auth.mfa_factors which isn't accessible via RLS.
-- This migration drops the broken policies and recreates them using SECURITY DEFINER functions.

-- Drop the broken policies
DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.user_settings;
DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.user_shifts;
DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.recurring_shifts;
DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.wage_snapshots;
DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.profiles;
DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.subscriptions;

-- Create a security definer function to check MFA factors
-- This is needed because auth.mfa_factors is not directly accessible via RLS
CREATE OR REPLACE FUNCTION public.user_has_verified_mfa_factors()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.mfa_factors
    WHERE user_id = auth.uid()
      AND status = 'verified'
  )
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.user_has_verified_mfa_factors() TO authenticated;

-- Helper function to check if current AAL is sufficient
-- Returns true if:
-- 1. User has no MFA factors (any AAL is fine), OR
-- 2. User has MFA factors AND current AAL is 'aal2'
CREATE OR REPLACE FUNCTION public.check_mfa_aal()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    CASE
      WHEN public.user_has_verified_mfa_factors() THEN
        (auth.jwt()->>'aal') = 'aal2'
      ELSE
        true
    END
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.check_mfa_aal() TO authenticated;

-- Recreate policies using the security definer function
CREATE POLICY "Require MFA for users who enrolled"
  ON public.user_settings
  AS RESTRICTIVE
  TO authenticated
  USING (public.check_mfa_aal());

CREATE POLICY "Require MFA for users who enrolled"
  ON public.user_shifts
  AS RESTRICTIVE
  TO authenticated
  USING (public.check_mfa_aal());

CREATE POLICY "Require MFA for users who enrolled"
  ON public.recurring_shifts
  AS RESTRICTIVE
  TO authenticated
  USING (public.check_mfa_aal());

CREATE POLICY "Require MFA for users who enrolled"
  ON public.wage_snapshots
  AS RESTRICTIVE
  TO authenticated
  USING (public.check_mfa_aal());

CREATE POLICY "Require MFA for users who enrolled"
  ON public.profiles
  AS RESTRICTIVE
  TO authenticated
  USING (public.check_mfa_aal());

CREATE POLICY "Require MFA for users who enrolled"
  ON public.subscriptions
  AS RESTRICTIVE
  TO authenticated
  USING (public.check_mfa_aal());
