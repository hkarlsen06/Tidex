-- Function: build_thread_core_sync_payload_v2
-- Description: Builds the viewer-independent thread-core payload used by messaging sync V2

CREATE OR REPLACE FUNCTION internal.build_thread_core_sync_payload_v2(p_thread_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'id', t.id,
    'kind', t.kind,
    'title', t.title,
    'avatar_url', t.avatar_url,
    'metadata', t.metadata,
    'created_at', t.created_at
  )
  FROM public.threads t
  WHERE t.id = p_thread_id;
$function$;

