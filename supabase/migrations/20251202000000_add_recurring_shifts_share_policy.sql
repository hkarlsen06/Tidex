-- Add shared access policy for recurring_shifts table
-- This allows viewers to see recurring shifts from users who have shared with them

-- Allow viewing recurring shifts shared with you
CREATE POLICY "Users can view shared recurring shifts"
  ON public.recurring_shifts
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shift_shares
      WHERE shift_shares.owner_id = recurring_shifts.user_id
        AND shift_shares.viewer_id = auth.uid()
    )
  );
