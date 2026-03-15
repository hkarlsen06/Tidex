-- Fix broadcast history functions to read delivery state from notifications_outbox.

CREATE OR REPLACE FUNCTION public.admin_get_broadcast_history(limit_count integer DEFAULT 10)
 RETURNS TABLE(id uuid, title text, body text, target text, target_count integer, status text, created_at timestamp with time zone, sent_count bigint, failed_count bigint, skipped_count bigint, pending_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'internal'
AS $function$
  SELECT
    ab.id,
    ab.title,
    ab.body,
    ab.target,
    ab.target_count,
    ab.status,
    ab.created_at,
    COUNT(*) FILTER (WHERE no.status = 'sent') AS sent_count,
    COUNT(*) FILTER (WHERE no.status = 'failed') AS failed_count,
    COUNT(*) FILTER (WHERE no.status = 'skipped') AS skipped_count,
    COUNT(*) FILTER (WHERE no.status IN ('pending', 'sending')) AS pending_count
  FROM internal.admin_broadcasts ab
  LEFT JOIN internal.notifications_outbox no ON no.broadcast_id = ab.id
  GROUP BY ab.id, ab.title, ab.body, ab.target, ab.target_count, ab.status, ab.created_at
  ORDER BY ab.created_at DESC
  LIMIT limit_count;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_broadcast_history_api()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_is_admin();

  RETURN (
    WITH rows AS (
      SELECT
        ab.id,
        ab.title,
        ab.body,
        ab.target,
        ab.target_count,
        ab.status,
        ab.created_at,
        COUNT(*) FILTER (WHERE no.status = 'sent')::integer AS sent_count,
        COUNT(*) FILTER (WHERE no.status = 'failed')::integer AS failed_count,
        COUNT(*) FILTER (WHERE no.status = 'skipped')::integer AS skipped_count,
        COUNT(*) FILTER (WHERE no.status IN ('pending', 'sending'))::integer AS pending_count
      FROM internal.admin_broadcasts ab
      LEFT JOIN internal.notifications_outbox no ON no.broadcast_id = ab.id
      GROUP BY ab.id
      ORDER BY ab.created_at DESC
      LIMIT 10
    )
    SELECT jsonb_build_object(
      'broadcasts', COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'title', title,
            'body', body,
            'target', target,
            'targetCount', target_count,
            'status', status,
            'createdAt', created_at,
            'sentCount', sent_count,
            'failedCount', failed_count,
            'skippedCount', skipped_count,
            'pendingCount', pending_count
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      )
    )
    FROM rows
  );
END;
$function$;
