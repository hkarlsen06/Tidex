-- ============================================================================
-- Move Tax & Break Deduction Settings to Wage Snapshots
-- ============================================================================
-- This migration moves tax_deduction and pause_deduction settings from
-- the global user_settings table to per-snapshot storage in wage_snapshots.
-- This allows historical tracking as these values change over time.
--
-- Changes:
-- 1. Add tax/break columns to wage_snapshots
-- 2. Backfill existing snapshots with current user settings
-- 3. Remove deprecated columns from user_settings
-- ============================================================================

-- ============================================================================
-- Step 1: Add new columns to wage_snapshots
-- ============================================================================

-- Add tax fields
ALTER TABLE wage_snapshots ADD COLUMN IF NOT EXISTS tax_enabled boolean DEFAULT false;
ALTER TABLE wage_snapshots ADD COLUMN IF NOT EXISTS tax_percentage numeric(5,2) DEFAULT 0;

-- Add break deduction fields
ALTER TABLE wage_snapshots ADD COLUMN IF NOT EXISTS break_enabled boolean DEFAULT true;
ALTER TABLE wage_snapshots ADD COLUMN IF NOT EXISTS break_method text DEFAULT 'proportional';
ALTER TABLE wage_snapshots ADD COLUMN IF NOT EXISTS break_threshold_hours numeric(4,2) DEFAULT 5.5;
ALTER TABLE wage_snapshots ADD COLUMN IF NOT EXISTS break_deduction_minutes integer DEFAULT 30;

-- Add check constraint for break_method
ALTER TABLE wage_snapshots DROP CONSTRAINT IF EXISTS wage_snapshots_break_method_check;
ALTER TABLE wage_snapshots ADD CONSTRAINT wage_snapshots_break_method_check
  CHECK (break_method IN ('proportional', 'base_only', 'end_of_shift', 'none'));

-- Add check constraint for tax_percentage
ALTER TABLE wage_snapshots DROP CONSTRAINT IF EXISTS wage_snapshots_tax_percentage_check;
ALTER TABLE wage_snapshots ADD CONSTRAINT wage_snapshots_tax_percentage_check
  CHECK (tax_percentage >= 0 AND tax_percentage <= 100);

-- ============================================================================
-- Step 2: Backfill existing snapshots with user's current settings
-- ============================================================================
-- Copy current tax/break settings from user_settings to all existing snapshots

UPDATE wage_snapshots ws
SET
  tax_enabled = COALESCE(us.tax_deduction_enabled, false),
  tax_percentage = COALESCE(us.tax_percentage, 0),
  break_enabled = COALESCE(us.pause_deduction_enabled, true),
  break_method = COALESCE(us.pause_deduction_method, 'proportional'),
  break_threshold_hours = COALESCE(us.pause_threshold_hours, 5.5),
  break_deduction_minutes = COALESCE(us.pause_deduction_minutes, 30)
FROM user_settings us
WHERE ws.user_id = us.user_id;

-- ============================================================================
-- Step 3: Remove deprecated columns from user_settings
-- ============================================================================
-- These settings are now stored per-snapshot in wage_snapshots
-- Note: half_tax_month remains in user_settings (global calendar preference)

ALTER TABLE user_settings DROP COLUMN IF EXISTS tax_deduction_enabled;
ALTER TABLE user_settings DROP COLUMN IF EXISTS tax_percentage;
ALTER TABLE user_settings DROP COLUMN IF EXISTS pause_deduction_enabled;
ALTER TABLE user_settings DROP COLUMN IF EXISTS pause_deduction_method;
ALTER TABLE user_settings DROP COLUMN IF EXISTS pause_threshold_hours;
ALTER TABLE user_settings DROP COLUMN IF EXISTS pause_deduction_minutes;

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- Remaining fields in user_settings:
-- - half_tax_month (global calendar preference for half-tax month)
-- - payroll_day (global payment day preference)
-- - monthly_goal (global earnings goal)
-- ============================================================================
