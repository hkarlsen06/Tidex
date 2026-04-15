BEGIN;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS notification_minutes_array integer[] NULL,
  ADD COLUMN IF NOT EXISTS notification_anchor_time text NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'events_notification_anchor_time_valid'
      AND conrelid = 'public.events'::regclass
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_notification_anchor_time_valid
      CHECK (
        notification_anchor_time IS NULL
        OR notification_anchor_time ~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
      );
  END IF;
END;
$$;

COMMIT;
