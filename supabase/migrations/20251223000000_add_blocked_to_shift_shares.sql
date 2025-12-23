-- Add blocked column to shift_shares
-- Allows viewers to hide sharers they don't want to see without removing the share relationship

ALTER TABLE shift_shares
ADD COLUMN blocked BOOLEAN NOT NULL DEFAULT false;

-- Partial index for efficient lookup of blocked shares per viewer
CREATE INDEX idx_shift_shares_blocked ON shift_shares(viewer_id) WHERE blocked = true;

-- Add update policy for viewers to update blocked status
-- (Viewers can only update the blocked column, not other columns like show_earnings)
CREATE POLICY "Viewers can update blocked status"
ON shift_shares
FOR UPDATE
TO authenticated
USING (auth.uid() = viewer_id)
WITH CHECK (auth.uid() = viewer_id);
