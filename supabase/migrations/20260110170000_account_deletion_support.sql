-- Migration: Account Deletion Support
-- Description: Fixes FK constraints that block user deletion and creates a cleanup function
--
-- Problem: Deleting users via Supabase Auth fails because internal.admin_audit_log
-- has FK constraints to auth.users with NO ACTION delete rule.
--
-- Solution:
-- 1. Change blocking FK constraints to ON DELETE SET NULL (preserve audit history)
-- 2. Create a function to clean up internal tables before auth user deletion

-- ============================================================================
-- Step 1: Fix FK constraints on internal.admin_audit_log
-- These currently block user deletion - change to SET NULL to preserve audit trail
-- ============================================================================

-- Drop and recreate admin_audit_log FK constraints with ON DELETE SET NULL
ALTER TABLE internal.admin_audit_log
DROP CONSTRAINT IF EXISTS admin_audit_log_admin_id_fkey;

ALTER TABLE internal.admin_audit_log
ADD CONSTRAINT admin_audit_log_admin_id_fkey
  FOREIGN KEY (admin_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE internal.admin_audit_log
DROP CONSTRAINT IF EXISTS admin_audit_log_target_user_id_fkey;

ALTER TABLE internal.admin_audit_log
ADD CONSTRAINT admin_audit_log_target_user_id_fkey
  FOREIGN KEY (target_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ============================================================================
-- Step 2: Fix FK constraints on internal.admin_broadcasts
-- Preserve broadcast history when admin is deleted
-- ============================================================================

ALTER TABLE internal.admin_broadcasts
DROP CONSTRAINT IF EXISTS admin_broadcasts_admin_id_fkey;

ALTER TABLE internal.admin_broadcasts
ADD CONSTRAINT admin_broadcasts_admin_id_fkey
  FOREIGN KEY (admin_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ============================================================================
-- Step 3: Fix FK constraints on internal.impersonation_sessions
-- Preserve session history when users are deleted
-- ============================================================================

ALTER TABLE internal.impersonation_sessions
DROP CONSTRAINT IF EXISTS impersonation_sessions_admin_user_id_fkey;

ALTER TABLE internal.impersonation_sessions
ADD CONSTRAINT impersonation_sessions_admin_user_id_fkey
  FOREIGN KEY (admin_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE internal.impersonation_sessions
DROP CONSTRAINT IF EXISTS impersonation_sessions_target_user_id_fkey;

ALTER TABLE internal.impersonation_sessions
ADD CONSTRAINT impersonation_sessions_target_user_id_fkey
  FOREIGN KEY (target_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE internal.impersonation_sessions
DROP CONSTRAINT IF EXISTS impersonation_sessions_ended_by_admin_user_id_fkey;

ALTER TABLE internal.impersonation_sessions
ADD CONSTRAINT impersonation_sessions_ended_by_admin_user_id_fkey
  FOREIGN KEY (ended_by_admin_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ============================================================================
-- Step 4: Fix FK constraint on internal.apple_orphan_notifications
-- ============================================================================

ALTER TABLE internal.apple_orphan_notifications
DROP CONSTRAINT IF EXISTS apple_orphan_notifications_reconciled_user_id_fkey;

ALTER TABLE internal.apple_orphan_notifications
ADD CONSTRAINT apple_orphan_notifications_reconciled_user_id_fkey
  FOREIGN KEY (reconciled_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ============================================================================
-- Step 5: Fix FK constraint on public.feedback (responded_by column)
-- The user_id column should cascade, but responded_by should set null
-- ============================================================================

ALTER TABLE public.feedback
DROP CONSTRAINT IF EXISTS feedback_responded_by_fkey;

ALTER TABLE public.feedback
ADD CONSTRAINT feedback_responded_by_fkey
  FOREIGN KEY (responded_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- ============================================================================
-- Step 6: Create cleanup function for internal tables
-- This function cleans up data that should be deleted (not just nullified)
-- Call this BEFORE deleting the auth user
-- ============================================================================

CREATE OR REPLACE FUNCTION public.prepare_user_for_deletion(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, internal
AS $$
BEGIN
  -- Validate input
  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_id cannot be null';
  END IF;

  -- Delete from internal tables that should be cleaned up (not preserved)
  DELETE FROM internal.impersonation_rate_limits WHERE admin_user_id = target_user_id;
  DELETE FROM internal.app_account_tokens WHERE user_id = target_user_id;
  DELETE FROM internal.push_devices WHERE user_id = target_user_id;
  DELETE FROM internal.notification_time_windows WHERE owner_id = target_user_id;
  DELETE FROM internal.notifications_outbox WHERE owner_id = target_user_id OR recipient_id = target_user_id;

  -- Note: The following are handled by ON DELETE SET NULL or ON DELETE CASCADE:
  -- - internal.admin_audit_log (SET NULL - preserves audit trail)
  -- - internal.admin_broadcasts (SET NULL - preserves broadcast history)
  -- - internal.impersonation_sessions (SET NULL - preserves session history)
  -- - internal.apple_orphan_notifications (SET NULL)
  -- - All public schema tables (CASCADE via existing FKs)

  -- Log the account deletion preparation (before the user is deleted)
  -- This will have target_user_id set to NULL after auth user deletion
  INSERT INTO internal.admin_audit_log (
    admin_id,
    action,
    target_user_id,
    admin_email,
    target_email,
    metadata
  )
  SELECT
    target_user_id,
    'user_deleted_self',
    target_user_id,
    COALESCE(u.email, u.phone, 'unknown'),
    COALESCE(u.email, u.phone, 'unknown'),
    jsonb_build_object('deletion_type', 'self_service', 'deleted_at', now())
  FROM auth.users u
  WHERE u.id = target_user_id;

END;
$$;

-- Grant execute permission to authenticated users (they can only delete themselves)
GRANT EXECUTE ON FUNCTION public.prepare_user_for_deletion(uuid) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION public.prepare_user_for_deletion(uuid) IS
'Prepares a user account for deletion by cleaning up internal tables.
Call this function before calling auth.admin.deleteUser().
The function is SECURITY DEFINER to access internal schema tables.
Users can only call this with their own user ID (enforced at API level).';

-- ============================================================================
-- Step 7: Add 'user_deleted_self' to the action check constraint
-- ============================================================================

ALTER TABLE internal.admin_audit_log
DROP CONSTRAINT IF EXISTS admin_audit_log_action_check;

ALTER TABLE internal.admin_audit_log
ADD CONSTRAINT admin_audit_log_action_check
CHECK (action = ANY (ARRAY[
  'user_lookup'::text,
  'user_ban'::text,
  'user_unban'::text,
  'grant_admin'::text,
  'revoke_admin'::text,
  'grant_grandfathered'::text,
  'revoke_grandfathered'::text,
  'create_trial_subscription'::text,
  'revoke_trial_subscription'::text,
  'broadcast_sent'::text,
  'user_list_viewed'::text,
  'admin_action_failed'::text,
  'sql_executed'::text,
  'shift_share_created'::text,
  'shift_share_updated'::text,
  'shift_share_deleted'::text,
  'user_deleted_self'::text
]));
