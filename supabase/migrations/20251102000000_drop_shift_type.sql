-- Drop shift_type column from user_shifts table
-- This column was redundant as shift type can be derived from shift_date

ALTER TABLE user_shifts DROP COLUMN IF EXISTS shift_type;
