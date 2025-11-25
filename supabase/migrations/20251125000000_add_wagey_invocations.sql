-- Migration: Add Wagey invocations tracking to profiles
-- Purpose: Track monthly usage limits for Wagey AI assistant per subscription tier

-- Add wagey_invocations JSONB column to profiles table
-- Structure: { "count": number, "month": "YYYY-MM" | null }
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS wagey_invocations JSONB DEFAULT '{"count": 0, "month": null}'::jsonb;

-- Create atomic increment function for race-condition-safe usage tracking
-- This function:
-- 1. Resets count to 1 if the month has changed
-- 2. Increments count if under the limit
-- 3. Returns whether the invocation was allowed and remaining count
CREATE OR REPLACE FUNCTION increment_wagey_invocation(
  p_user_id UUID,
  p_current_month TEXT,  -- Format: "2025-01"
  p_max_invocations INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current JSONB;
  v_count INTEGER;
  v_month TEXT;
  v_new_count INTEGER;
  v_allowed BOOLEAN;
BEGIN
  -- Get current invocations with row lock to prevent race conditions
  SELECT wagey_invocations INTO v_current
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  -- Handle null or missing data
  IF v_current IS NULL THEN
    v_current := '{"count": 0, "month": null}'::jsonb;
  END IF;

  v_count := COALESCE((v_current->>'count')::integer, 0);
  v_month := v_current->>'month';

  -- Reset if new month or first use
  IF v_month IS NULL OR v_month != p_current_month THEN
    v_new_count := 1;
    v_allowed := TRUE;
  ELSE
    -- Check if under limit
    IF v_count < p_max_invocations THEN
      v_new_count := v_count + 1;
      v_allowed := TRUE;
    ELSE
      -- At or over limit - don't increment
      v_new_count := v_count;
      v_allowed := FALSE;
    END IF;
  END IF;

  -- Only update if allowed
  IF v_allowed THEN
    UPDATE profiles
    SET
      wagey_invocations = jsonb_build_object('count', v_new_count, 'month', p_current_month),
      updated_at = now()
    WHERE id = p_user_id;
  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'count', v_new_count,
    'remaining', GREATEST(0, p_max_invocations - v_new_count)
  );
END;
$$;

-- Add comment for documentation
COMMENT ON COLUMN profiles.wagey_invocations IS 'Tracks monthly Wagey AI invocations. Structure: { "count": number, "month": "YYYY-MM" | null }';
COMMENT ON FUNCTION increment_wagey_invocation IS 'Atomically increments Wagey invocation count with monthly reset and limit enforcement';
