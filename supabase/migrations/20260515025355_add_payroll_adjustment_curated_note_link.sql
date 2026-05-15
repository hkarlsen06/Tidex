ALTER TABLE public.payroll_adjustments
  ADD COLUMN IF NOT EXISTS curated_note text,
  ADD COLUMN IF NOT EXISTS curated_link text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'payroll_adjustments_curated_note_check'
  ) THEN
    ALTER TABLE public.payroll_adjustments
      ADD CONSTRAINT payroll_adjustments_curated_note_check CHECK (
        curated_note IS NULL OR length(curated_note) <= 1000
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'payroll_adjustments_curated_link_check'
  ) THEN
    ALTER TABLE public.payroll_adjustments
      ADD CONSTRAINT payroll_adjustments_curated_link_check CHECK (
        curated_link IS NULL OR length(btrim(curated_link)) BETWEEN 1 AND 2048
      );
  END IF;
END $$;
