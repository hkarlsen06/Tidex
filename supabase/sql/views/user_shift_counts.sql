-- Administrative shift-count view retained from the linked project.
CREATE OR REPLACE VIEW public.user_shift_counts
WITH (security_invoker = on)
AS
SELECT
  u.id AS user_id,
  COALESCE(
    u.raw_user_meta_data ->> 'name',
    u.raw_user_meta_data ->> 'full_name'
  ) AS name,
  u.email,
  u.created_at,
  COALESCE(us.cnt, 0::bigint) AS user_shifts_count,
  COALESCE(rs.cnt, 0::bigint) AS recurring_shifts_count,
  COALESCE(us.cnt, 0::bigint) + COALESCE(rs.cnt, 0::bigint) AS total_count
FROM auth.users u
LEFT JOIN (
  SELECT user_id, count(*) AS cnt
  FROM public.user_shifts
  GROUP BY user_id
) us ON us.user_id = u.id
LEFT JOIN (
  SELECT user_id, count(*) AS cnt
  FROM public.recurring_shifts
  GROUP BY user_id
) rs ON rs.user_id = u.id;

GRANT ALL ON TABLE public.user_shift_counts
  TO anon, authenticated, service_role;
