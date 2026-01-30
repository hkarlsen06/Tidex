-- Make admin_refresh_token_enc nullable
-- 
-- This change supports the new security architecture where:
-- 1. The Edge Function creates the impersonation session WITHOUT the admin refresh token
-- 2. The Next.js API route stores the encrypted token server-side AFTER the session is created
-- 3. iOS clients don't store admin tokens server-side (they use Keychain)
--
-- This ensures the admin refresh token never leaves the Next.js server boundary
-- and is not accepted by the Edge Function API.

-- Remove the NOT NULL constraint from admin_refresh_token_enc
ALTER TABLE internal.impersonation_sessions
  ALTER COLUMN admin_refresh_token_enc DROP NOT NULL;

-- Add a comment explaining the column's nullable behavior
COMMENT ON COLUMN internal.impersonation_sessions.admin_refresh_token_enc IS 
  'Encrypted admin refresh token for session restoration. NULL for iOS clients (they store in Keychain). For web, stored by Next.js API after Edge Function creates session.';

