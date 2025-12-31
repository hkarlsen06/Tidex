-- Function: admin_get_broadcast_history
-- Description: Returns broadcast history with aggregated notification counts
-- Used by: Admin broadcast management

CREATE OR REPLACE FUNCTION public.admin_get_broadcast_history(limit_count integer DEFAULT 10)
 RETURNS TABLE(id uuid, title text, body text, target text, target_count integer, status text, created_at timestamp with time zone, sent_count bigint, failed_count bigint, skipped_count bigint, pending_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    ab.id,
    ab.title,
    ab.body,
    ab.target,
    ab.target_count,
    ab.status,
    ab.created_at,
    COUNT(*) FILTER (WHERE nq.status = 'sent') AS sent_count,
    COUNT(*) FILTER (WHERE nq.status = 'failed') AS failed_count,
    COUNT(*) FILTER (WHERE nq.status = 'skipped') AS skipped_count,
    COUNT(*) FILTER (WHERE nq.status IN ('pending', 'processing')) AS pending_count
  FROM admin_broadcasts ab
  LEFT JOIN notification_queue nq ON nq.broadcast_id = ab.id
  GROUP BY ab.id, ab.title, ab.body, ab.target, ab.target_count, ab.status, ab.created_at
  ORDER BY ab.created_at DESC
  LIMIT limit_count;
$function$;
