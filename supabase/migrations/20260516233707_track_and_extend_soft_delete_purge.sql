CREATE OR REPLACE FUNCTION internal.purge_soft_deletes(
  p_retention interval DEFAULT interval '30 days'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'public', 'storage', 'net', 'vault', 'pg_temp'
AS $function$
DECLARE
  v_cutoff timestamptz := now() - COALESCE(p_retention, interval '30 days');
  v_supabase_url text;
  v_service_role_key text;
  v_storage_delete record;
BEGIN
  SELECT decrypted_secret
  INTO v_supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url';

  SELECT decrypted_secret
  INTO v_service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  IF v_supabase_url IS NOT NULL AND v_service_role_key IS NOT NULL THEN
    FOR v_storage_delete IN
      SELECT
        ma.storage_bucket,
        jsonb_agg(ma.storage_path ORDER BY ma.storage_path) AS prefixes
      FROM public.message_attachments ma
      JOIN public.messages m ON m.id = ma.message_id
      JOIN storage.objects so
        ON so.bucket_id = ma.storage_bucket
       AND so.name = ma.storage_path
      WHERE m.deleted_at IS NOT NULL
        AND m.deleted_at < v_cutoff
      GROUP BY ma.storage_bucket
    LOOP
      PERFORM net.http_delete(
        url := v_supabase_url || '/storage/v1/object/' || v_storage_delete.storage_bucket,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', v_service_role_key
        ),
        body := jsonb_build_object('prefixes', v_storage_delete.prefixes),
        timeout_milliseconds := 5000
      );
    END LOOP;
  END IF;

  DELETE FROM public.messages m
  WHERE m.deleted_at IS NOT NULL
    AND m.deleted_at < v_cutoff
    AND NOT EXISTS (
      SELECT 1
      FROM public.message_attachments ma
      JOIN storage.objects so
        ON so.bucket_id = ma.storage_bucket
       AND so.name = ma.storage_path
      WHERE ma.message_id = m.id
    );

  DELETE FROM public.events e
  WHERE e.deleted_at IS NOT NULL
    AND e.deleted_at < v_cutoff;

  DELETE FROM public.payroll_adjustments pa
  WHERE pa.deleted_at IS NOT NULL
    AND pa.deleted_at < v_cutoff;

  DELETE FROM public.user_shifts us
  WHERE us.deleted_at IS NOT NULL
    AND us.deleted_at < v_cutoff;

  DELETE FROM public.recurring_shifts rs
  WHERE rs.deleted_at IS NOT NULL
    AND rs.deleted_at < v_cutoff;

  DELETE FROM public.wage_snapshots ws
  WHERE ws.deleted_at IS NOT NULL
    AND ws.deleted_at < v_cutoff;

  DELETE FROM public.jobs j
  WHERE j.deleted_at IS NOT NULL
    AND j.deleted_at < v_cutoff;
END;
$function$;

REVOKE EXECUTE ON FUNCTION internal.purge_soft_deletes(interval) FROM public;
REVOKE EXECUTE ON FUNCTION internal.purge_soft_deletes(interval) FROM anon;
REVOKE EXECUTE ON FUNCTION internal.purge_soft_deletes(interval) FROM authenticated;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'daily_purge_soft_deletes';

SELECT cron.schedule(
  'daily_purge_soft_deletes',
  '30 3 * * *',
  $$SELECT internal.purge_soft_deletes(interval '30 days');$$
);
