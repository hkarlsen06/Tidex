-- Add UPDATE policy for shift_shares table
-- Allows owners to update share settings (e.g., show_earnings toggle)
-- This was missing from the original migration, causing toggle updates to fail silently

CREATE POLICY "Owner can update share settings"
  ON public.shift_shares
  FOR UPDATE
  TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
