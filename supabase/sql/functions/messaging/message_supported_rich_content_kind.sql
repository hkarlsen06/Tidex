-- Function: message_supported_rich_content_kind
-- Description: Returns the supported rich-content kind when metadata is fully renderable

CREATE OR REPLACE FUNCTION public.message_supported_rich_content_kind(p_metadata jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_content jsonb;
  v_kind text;
  v_snapshot jsonb;
  v_includes_earnings boolean;
BEGIN
  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RETURN NULL;
  END IF;

  v_content := v_metadata->'content';

  IF jsonb_typeof(v_content) <> 'object' THEN
    RETURN NULL;
  END IF;

  v_kind := NULLIF(btrim(v_content->>'kind'), '');

  IF v_kind <> 'shift_snapshot' THEN
    RETURN NULL;
  END IF;

  v_snapshot := v_content->'shift_snapshot';

  IF jsonb_typeof(v_snapshot) <> 'object' THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'schema_version') OR v_snapshot->>'schema_version' <> '1' THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'owner_user_id')
     OR COALESCE(jsonb_typeof(v_snapshot->'owner_user_id'), '') <> 'string'
     OR (v_snapshot->>'owner_user_id') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'owner_display_name')
     OR COALESCE(jsonb_typeof(v_snapshot->'owner_display_name'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'owner_display_name'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'owner_avatar_url'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'shift_id')
     OR COALESCE(jsonb_typeof(v_snapshot->'shift_id'), '') <> 'string'
     OR (v_snapshot->>'shift_id') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'job_name'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'job_color_hex'), 'null') NOT IN ('string', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'shift_date')
     OR COALESCE(jsonb_typeof(v_snapshot->'shift_date'), '') <> 'string'
     OR (v_snapshot->>'shift_date') !~ '^\d{4}-\d{2}-\d{2}$'
  THEN
    RETURN NULL;
  END IF;

  BEGIN
    PERFORM (v_snapshot->>'shift_date')::date;
  EXCEPTION
    WHEN others THEN
      RETURN NULL;
  END;

  IF NOT (v_snapshot ? 'start_time')
     OR COALESCE(jsonb_typeof(v_snapshot->'start_time'), '') <> 'string'
     OR (v_snapshot->>'start_time') !~ '^([01]\d|2[0-3]):[0-5]\d$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'end_time')
     OR COALESCE(jsonb_typeof(v_snapshot->'end_time'), '') <> 'string'
     OR (v_snapshot->>'end_time') !~ '^([01]\d|2[0-3]):[0-5]\d$'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'paid_hours')
     OR COALESCE(jsonb_typeof(v_snapshot->'paid_hours'), '') <> 'number'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'currency')
     OR COALESCE(jsonb_typeof(v_snapshot->'currency'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'currency'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'includes_earnings')
     OR COALESCE(jsonb_typeof(v_snapshot->'includes_earnings'), '') <> 'boolean'
  THEN
    RETURN NULL;
  END IF;

  v_includes_earnings := (v_snapshot->>'includes_earnings')::boolean;

  IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') NOT IN ('number', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') NOT IN ('number', 'null')
  THEN
    RETURN NULL;
  END IF;

  IF v_includes_earnings THEN
    IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') <> 'number'
       OR COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') <> 'number'
    THEN
      RETURN NULL;
    END IF;
  ELSE
    IF COALESCE(jsonb_typeof(v_snapshot->'gross_pay'), 'null') <> 'null'
       OR COALESCE(jsonb_typeof(v_snapshot->'net_pay'), 'null') <> 'null'
    THEN
      RETURN NULL;
    END IF;
  END IF;

  IF NOT (v_snapshot ? 'tax_enabled')
     OR COALESCE(jsonb_typeof(v_snapshot->'tax_enabled'), '') <> 'boolean'
  THEN
    RETURN NULL;
  END IF;

  IF NOT (v_snapshot ? 'source')
     OR COALESCE(jsonb_typeof(v_snapshot->'source'), '') <> 'string'
     OR NULLIF(btrim(v_snapshot->>'source'), '') IS NULL
  THEN
    RETURN NULL;
  END IF;

  RETURN 'shift_snapshot';
END;
$function$;
