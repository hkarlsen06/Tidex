-- Add custom_supplements column to user_shifts table
ALTER TABLE user_shifts
ADD COLUMN custom_supplements JSONB;

-- Add date_specific_supplements column to series_shifts table
ALTER TABLE series_shifts
ADD COLUMN date_specific_supplements JSONB;

-- Add GIN indexes for efficient JSONB querying
CREATE INDEX idx_user_shifts_custom_supplements
ON user_shifts USING GIN (custom_supplements);

CREATE INDEX idx_series_shifts_date_supplements
ON series_shifts USING GIN (date_specific_supplements);

-- Add comments explaining the structure
COMMENT ON COLUMN user_shifts.custom_supplements IS 'Shift-specific supplement overrides. Structure: { mode: "replace" | "merge", rules: SupplementRule[] }';
COMMENT ON COLUMN series_shifts.date_specific_supplements IS 'Date-specific supplement overrides for series. Structure: { [isoDate]: { mode: "replace" | "merge", rules: SupplementRule[] } }';
