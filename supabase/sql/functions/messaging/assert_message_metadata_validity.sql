-- Function: assert_message_metadata_validity
-- Description: Validates supported rich-content metadata and rejects oversized or unsupported payloads

CREATE OR REPLACE FUNCTION public.assert_message_metadata_validity(p_metadata jsonb)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_metadata jsonb := COALESCE(p_metadata, '{}'::jsonb);
  v_content jsonb;
  v_kind text;
BEGIN
  IF jsonb_typeof(v_metadata) <> 'object' THEN
    RAISE EXCEPTION 'Metadata must be a JSON object';
  END IF;

  IF pg_column_size(v_metadata) > 8192 THEN
    RAISE EXCEPTION 'Metadata exceeds the 8 KB limit';
  END IF;

  IF NOT (v_metadata ? 'content') THEN
    RETURN;
  END IF;

  v_content := v_metadata->'content';

  IF jsonb_typeof(v_content) <> 'object' THEN
    RAISE EXCEPTION 'Metadata content must be a JSON object';
  END IF;

  v_kind := NULLIF(btrim(v_content->>'kind'), '');

  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Metadata content kind is required';
  END IF;

  IF public.message_supported_rich_content_kind(v_metadata) IS NOT NULL THEN
    RETURN;
  END IF;

  IF v_kind = 'shift_snapshot' THEN
    RAISE EXCEPTION 'Invalid shift snapshot metadata';
  END IF;

  RAISE EXCEPTION 'Unsupported rich content kind: %', v_kind;
END;
$function$;
