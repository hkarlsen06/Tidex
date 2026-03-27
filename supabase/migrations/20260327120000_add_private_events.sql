BEGIN;

CREATE TABLE IF NOT EXISTS public.events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  start_date date NOT NULL,
  end_date date NOT NULL,
  is_all_day boolean NOT NULL DEFAULT false,
  start_time text,
  end_time text,
  note text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revision bigint NOT NULL DEFAULT 1,
  deleted_at timestamptz DEFAULT NULL
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'events_time_format_valid'
      AND conrelid = 'public.events'::regclass
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_time_format_valid
      CHECK (
        (start_time IS NULL OR start_time ~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$')
        AND (
          end_time IS NULL
          OR end_time ~ '^(?:(?:[01][0-9]|2[0-3]):[0-5][0-9]|24:00)$'
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'events_note_not_blank'
      AND conrelid = 'public.events'::regclass
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_note_not_blank
      CHECK (btrim(note) <> '');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'events_shape_valid'
      AND conrelid = 'public.events'::regclass
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_shape_valid
      CHECK (
        (
          is_all_day = false
          AND start_date = end_date
          AND start_time IS NOT NULL
          AND end_time IS NOT NULL
          AND end_time > start_time
        )
        OR (
          is_all_day = true
          AND start_time IS NULL
          AND end_time IS NULL
          AND end_date >= start_date
        )
      );
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_events_user_updated_at_id
  ON public.events (user_id, updated_at, id);

CREATE INDEX IF NOT EXISTS idx_events_user_active_start_date_desc
  ON public.events (user_id, start_date DESC, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_events_user_active_span
  ON public.events (user_id, start_date, end_date, id)
  WHERE deleted_at IS NULL;

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'events'
      AND policyname = 'Users can view own events'
  ) THEN
    CREATE POLICY "Users can view own events" ON public.events
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'events'
      AND policyname = 'Users can insert own events'
  ) THEN
    CREATE POLICY "Users can insert own events" ON public.events
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'events'
      AND policyname = 'Users can update own events'
  ) THEN
    CREATE POLICY "Users can update own events" ON public.events
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'events'
      AND policyname = 'Users can delete own events'
  ) THEN
    CREATE POLICY "Users can delete own events" ON public.events
      FOR DELETE TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'events'
      AND policyname = 'Require MFA for users who enrolled'
  ) THEN
    CREATE POLICY "Require MFA for users who enrolled" ON public.events
      AS RESTRICTIVE
      FOR ALL
      TO authenticated
      USING (public.check_mfa_aal());
  END IF;
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.events TO authenticated;

CREATE OR REPLACE FUNCTION public.set_events_updated_at_and_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  NEW.revision := COALESCE(OLD.revision, 0) + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_events_updated_at_revision ON public.events;
CREATE TRIGGER set_events_updated_at_revision
  BEFORE UPDATE ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.set_events_updated_at_and_revision();

COMMIT;
