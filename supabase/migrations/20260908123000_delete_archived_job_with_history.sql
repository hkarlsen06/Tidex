-- Function: assign_job_id_and_validate_owner
-- Description:
--   Trigger helper for user_shifts/recurring_shifts/wage_snapshots.
--   Fills missing job_id with default job and validates ownership.

CREATE OR REPLACE FUNCTION public.assign_job_id_and_validate_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.job_id IS NULL THEN
    NEW.job_id := public.ensure_default_job(NEW.user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.id = NEW.job_id
      AND j.user_id = NEW.user_id
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
    FOR SHARE
  ) THEN
    RAISE EXCEPTION 'job_id must belong to same user';
  END IF;

  RETURN NEW;
END;
$$;

-- Function: validate_payroll_adjustment_job_owner
-- Description:
--   Allows payroll adjustments without a job_id, and validates that explicit
--   job_id references belong to the same active job owner.

CREATE OR REPLACE FUNCTION public.validate_payroll_adjustment_job_owner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.job_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.jobs j
    WHERE j.id = NEW.job_id
      AND j.user_id = NEW.user_id
      AND j.deleted_at IS NULL
      AND j.archived_at IS NULL
    FOR SHARE
  ) THEN
    RAISE EXCEPTION 'job_id must belong to same user';
  END IF;

  RETURN NEW;
END;
$function$;

-- Preview an archived workplace deletion, then atomically delete exactly the
-- reviewed history. NULL confirmation tokens only preview; stale tokens fail.
-- SECURITY INVOKER preserves ownership and MFA RLS on every affected table.
CREATE OR REPLACE FUNCTION public.delete_archived_job(
  p_job_id uuid,
  p_confirmation_token text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_job public.jobs%ROWTYPE;
  v_history jsonb;
  v_token text;
  v_result jsonb;
  v_deleted_at timestamptz;
BEGIN
  SELECT * INTO v_job
  FROM public.jobs
  WHERE id = p_job_id AND user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'workplace not found' USING ERRCODE = 'PT404';
  END IF;

  -- A retry after a lost success response is safe and does not delete again.
  IF v_job.deleted_at IS NOT NULL THEN
    IF p_confirmation_token IS NULL THEN
      RAISE EXCEPTION 'workplace not found' USING ERRCODE = 'PT404';
    END IF;
    RETURN jsonb_build_object(
      'job_id', v_job.id, 'user_id', v_job.user_id, 'job_name', v_job.name,
      'job_revision', v_job.revision, 'confirmation_token', p_confirmation_token,
      'user_shifts', 0, 'recurring_shifts', 0, 'payroll_adjustments', 0,
      'wage_snapshots', 0, 'deleted_at_epoch', extract(epoch FROM v_job.deleted_at)
    );
  END IF;

  IF v_job.archived_at IS NULL OR v_job.is_default THEN
    RAISE EXCEPTION 'archive the workplace before deleting it' USING ERRCODE = 'PT400';
  END IF;

  -- Lock history in a fixed order before counting it. New references are denied
  -- by the existing active-job ownership triggers, which also lock the parent.
  PERFORM id FROM public.user_shifts
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL
    ORDER BY id FOR UPDATE;
  PERFORM id FROM public.recurring_shifts
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL
    ORDER BY id FOR UPDATE;
  PERFORM id FROM public.payroll_adjustments
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL
    ORDER BY id FOR UPDATE;
  PERFORM id FROM public.wage_snapshots
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL
    ORDER BY id FOR UPDATE;

  SELECT jsonb_build_object(
    'user_shifts', (SELECT coalesce(jsonb_agg(jsonb_build_array(id, revision) ORDER BY id), '[]')
      FROM public.user_shifts WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL),
    'recurring_shifts', (SELECT coalesce(jsonb_agg(jsonb_build_array(id, revision) ORDER BY id), '[]')
      FROM public.recurring_shifts WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL),
    'payroll_adjustments', (SELECT coalesce(jsonb_agg(jsonb_build_array(id, revision) ORDER BY id), '[]')
      FROM public.payroll_adjustments WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL),
    'wage_snapshots', (SELECT coalesce(jsonb_agg(jsonb_build_array(id, revision) ORDER BY id), '[]')
      FROM public.wage_snapshots WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL)
  ) INTO v_history;

  v_token := md5(v_job.id::text || ':' || v_job.revision::text || ':' || v_history::text);
  v_result := jsonb_build_object(
    'job_id', v_job.id, 'user_id', v_job.user_id, 'job_name', v_job.name,
    'job_revision', v_job.revision, 'confirmation_token', v_token,
    'user_shifts', jsonb_array_length(v_history->'user_shifts'),
    'recurring_shifts', jsonb_array_length(v_history->'recurring_shifts'),
    'payroll_adjustments', jsonb_array_length(v_history->'payroll_adjustments'),
    'wage_snapshots', jsonb_array_length(v_history->'wage_snapshots'),
    'deleted_at_epoch', NULL
  );

  IF p_confirmation_token IS NULL THEN
    RETURN v_result;
  END IF;
  IF p_confirmation_token IS DISTINCT FROM v_token THEN
    RAISE EXCEPTION 'workplace history changed; review deletion again' USING ERRCODE = 'PT409';
  END IF;

  v_deleted_at := clock_timestamp();
  UPDATE public.user_shifts SET deleted_at = v_deleted_at
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL;
  UPDATE public.recurring_shifts SET deleted_at = v_deleted_at
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL;
  UPDATE public.payroll_adjustments SET deleted_at = v_deleted_at
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL;
  UPDATE public.wage_snapshots SET deleted_at = v_deleted_at
    WHERE job_id = p_job_id AND user_id = v_user_id AND deleted_at IS NULL;
  -- Keep the existing dependent-history guard as a final consistency check.
  UPDATE public.jobs SET deleted_at = v_deleted_at, is_default = false
    WHERE id = p_job_id AND user_id = v_user_id
    RETURNING revision INTO v_job.revision;

  RETURN v_result || jsonb_build_object(
    'job_revision', v_job.revision,
    'deleted_at_epoch', extract(epoch FROM v_deleted_at)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_archived_job(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_archived_job(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
