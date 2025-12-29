-- Add RLS policies for Apple notification tables
-- These tables are server-only, so we deny all client access

-- Deny all access to apple_notifications (server-only table)
CREATE POLICY "Deny all access - server only table" ON apple_notifications
  AS RESTRICTIVE
  FOR ALL
  USING (false)
  WITH CHECK (false);

-- Deny all access to apple_orphan_notifications (server-only table)
CREATE POLICY "Deny all access - server only table" ON apple_orphan_notifications
  AS RESTRICTIVE
  FOR ALL
  USING (false)
  WITH CHECK (false);
