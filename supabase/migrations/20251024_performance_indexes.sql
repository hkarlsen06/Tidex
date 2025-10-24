-- Performance Optimization Indexes
-- Phase 2: Database Optimization
-- Created: 2025-10-24

-- ============================================================================
-- User Shifts Table Indexes
-- ============================================================================

-- 1. Single column index on user_id (should already exist as FK, but ensuring it exists)
CREATE INDEX IF NOT EXISTS idx_user_shifts_user_id
  ON user_shifts(user_id);

-- 2. Single column index on shift_date for date range queries
CREATE INDEX IF NOT EXISTS idx_user_shifts_shift_date
  ON user_shifts(shift_date);

-- 3. Composite index for the most common query pattern: filter by user, order by date
--    This index supports queries like:
--    SELECT * FROM user_shifts WHERE user_id = ? ORDER BY shift_date DESC
CREATE INDEX IF NOT EXISTS idx_user_shifts_user_date
  ON user_shifts(user_id, shift_date DESC);

-- 4. Composite index for date range queries per user
--    This supports queries with date range filters:
--    SELECT * FROM user_shifts WHERE user_id = ? AND shift_date >= ? AND shift_date <= ?
CREATE INDEX IF NOT EXISTS idx_user_shifts_user_date_range
  ON user_shifts(user_id, shift_date);

-- ============================================================================
-- User Settings Table Indexes
-- ============================================================================

-- Index for settings lookups (should already exist as FK, but ensuring it exists)
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id
  ON user_settings(user_id);

-- ============================================================================
-- Analysis and Verification
-- ============================================================================

-- To verify index usage, run EXPLAIN ANALYZE on your queries:
--
-- EXPLAIN ANALYZE
-- SELECT * FROM user_shifts
-- WHERE user_id = 'some-uuid'
-- AND shift_date >= '2024-04-01'
-- AND shift_date <= '2024-10-24'
-- ORDER BY shift_date DESC
-- LIMIT 500;
--
-- Look for "Index Scan" or "Index Only Scan" in the output
-- "Seq Scan" indicates the index is not being used

-- ============================================================================
-- Notes
-- ============================================================================
--
-- 1. The composite index idx_user_shifts_user_date should be used for most queries
--    as it covers both filtering by user_id and ordering by shift_date
--
-- 2. The idx_user_shifts_user_date_range index is specifically for range queries
--    and may be used by the query planner when date filters are present
--
-- 3. PostgreSQL query planner will automatically choose the most efficient index
--    based on query statistics and table size
--
-- 4. Run ANALYZE user_shifts; after applying this migration to update statistics
