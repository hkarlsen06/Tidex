-- Migration: Add clarifying comment for ended_by_admin_user_id column
-- The column name is historical - it can store either the admin's ID or the
-- impersonated user's ID (since both are allowed to end sessions)

COMMENT ON COLUMN internal.impersonation_sessions.ended_by_admin_user_id IS
  'User ID who ended the session. Despite the column name, this can be either the admin who started the session OR the impersonated user (target) who ended it. The audit log metadata includes ended_by_type to clarify.';
