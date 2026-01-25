-- Migration: Remove database-level shift month limit enforcement
-- The month limit is now enforced in the application layer (both Next.js and iOS)
-- with proper user experience including the option to delete shifts in other months

-- Drop the old restrictive policies
DROP POLICY IF EXISTS "insert_user_shifts_paid_or_existing_month" ON "public"."user_shifts";
DROP POLICY IF EXISTS "update_user_shifts_paid_or_existing_month" ON "public"."user_shifts";

-- Create new simpler policies that just check ownership
-- Insert: user can insert their own shifts
CREATE POLICY "insert_own_shifts" ON "public"."user_shifts"
  FOR INSERT
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Update: user can update their own shifts
CREATE POLICY "update_own_shifts" ON "public"."user_shifts"
  FOR UPDATE
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Note: The following functions are kept for potential future use:
-- - user_has_any_shifts(uuid)
-- - user_has_shift_in_month(uuid, date)
-- - has_shift_storage_entitlement(uuid)
-- They can be dropped later if truly no longer needed.

COMMENT ON POLICY "insert_own_shifts" ON "public"."user_shifts" IS 'Users can insert their own shifts. Month limits are enforced at the application layer.';
COMMENT ON POLICY "update_own_shifts" ON "public"."user_shifts" IS 'Users can update their own shifts. Month limits are enforced at the application layer.';
