-- Shift Shares Table
-- Allows users to share their shifts with other users for read-only viewing.
-- Recipients can view the sharer's shifts, wage snapshots, and relevant settings.

-- Create shift_shares table
CREATE TABLE public.shift_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Prevent duplicate shares
  UNIQUE(owner_id, viewer_id),

  -- Can't share with yourself
  CHECK (owner_id != viewer_id)
);

-- Indexes for efficient queries
CREATE INDEX idx_shift_shares_owner ON public.shift_shares(owner_id);
CREATE INDEX idx_shift_shares_viewer ON public.shift_shares(viewer_id);

-- Enable RLS
ALTER TABLE public.shift_shares ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS Policies for shift_shares table
-- ============================================================================

-- Owner can see who they've shared with
CREATE POLICY "Owner can view own shares"
  ON public.shift_shares
  FOR SELECT
  TO authenticated
  USING (owner_id = auth.uid());

-- Viewer can see shares they have access to
CREATE POLICY "Viewer can view shares they received"
  ON public.shift_shares
  FOR SELECT
  TO authenticated
  USING (viewer_id = auth.uid());

-- Only owner can create shares
CREATE POLICY "Owner can create shares"
  ON public.shift_shares
  FOR INSERT
  TO authenticated
  WITH CHECK (owner_id = auth.uid());

-- Only owner can delete shares
CREATE POLICY "Owner can delete shares"
  ON public.shift_shares
  FOR DELETE
  TO authenticated
  USING (owner_id = auth.uid());

-- ============================================================================
-- RLS Policies for shared access to user_shifts
-- ============================================================================

-- Allow viewing shifts shared with you
CREATE POLICY "Users can view shared shifts"
  ON public.user_shifts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shift_shares
      WHERE shift_shares.owner_id = user_shifts.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );

-- ============================================================================
-- RLS Policies for shared access to wage_snapshots
-- ============================================================================

-- Allow viewing wage snapshots for shared shifts (needed for payroll calculations)
CREATE POLICY "Users can view shared wage snapshots"
  ON public.wage_snapshots
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shift_shares
      WHERE shift_shares.owner_id = wage_snapshots.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );

-- ============================================================================
-- RLS Policies for shared access to user_settings
-- ============================================================================

-- Allow viewing settings for shared users (needed for display preferences)
CREATE POLICY "Users can view shared user settings"
  ON public.user_settings
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shift_shares
      WHERE shift_shares.owner_id = user_settings.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );

-- ============================================================================
-- MFA Enforcement for shift_shares
-- ============================================================================

-- Require MFA for users who enrolled (consistent with other tables)
CREATE POLICY "Require MFA for users who enrolled"
  ON public.shift_shares
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
