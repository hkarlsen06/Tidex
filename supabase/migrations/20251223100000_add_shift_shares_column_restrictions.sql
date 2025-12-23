-- Add column-level update restrictions for shift_shares
-- This trigger ensures proper separation of concerns:
-- - Owners can update: show_earnings (controls what viewers see)
-- - Viewers can update: blocked (controls their own view)
-- - Neither can change: id, owner_id, viewer_id, created_at

CREATE OR REPLACE FUNCTION enforce_shift_shares_update_columns()
RETURNS TRIGGER AS $$
BEGIN
  -- Immutable columns - nobody can change these
  IF NEW.id != OLD.id THEN
    RAISE EXCEPTION 'Cannot modify id column';
  END IF;
  IF NEW.owner_id != OLD.owner_id THEN
    RAISE EXCEPTION 'Cannot modify owner_id column';
  END IF;
  IF NEW.viewer_id != OLD.viewer_id THEN
    RAISE EXCEPTION 'Cannot modify viewer_id column';
  END IF;
  IF NEW.created_at != OLD.created_at THEN
    RAISE EXCEPTION 'Cannot modify created_at column';
  END IF;

  -- Check if viewer is trying to update (RLS already verified they are the viewer)
  IF auth.uid() = OLD.viewer_id THEN
    -- Viewers can only update 'blocked', not 'show_earnings'
    IF NEW.show_earnings IS DISTINCT FROM OLD.show_earnings THEN
      RAISE EXCEPTION 'Viewers cannot modify show_earnings column';
    END IF;
  END IF;

  -- Check if owner is trying to update (RLS already verified they are the owner)
  IF auth.uid() = OLD.owner_id THEN
    -- Owners can only update 'show_earnings', not 'blocked'
    IF NEW.blocked IS DISTINCT FROM OLD.blocked THEN
      RAISE EXCEPTION 'Owners cannot modify blocked column';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply the trigger
CREATE TRIGGER shift_shares_update_columns_check
  BEFORE UPDATE ON shift_shares
  FOR EACH ROW
  EXECUTE FUNCTION enforce_shift_shares_update_columns();
