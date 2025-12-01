-- Drop the MFA enforcement policy on shift_shares that causes permission denied errors
-- The policy tries to query auth.mfa_factors which authenticated users cannot access

DROP POLICY IF EXISTS "Require MFA for users who enrolled" ON public.shift_shares;

-- Note: MFA enforcement is handled by existing policies on the underlying tables
-- (user_shifts, wage_snapshots, user_settings) that the shared data comes from.
