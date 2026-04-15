-- admin_execute_sql
-- Executes raw SQL for admin users only. Used by the admin SQL runner in the dashboard.
-- SECURITY: This function uses SECURITY DEFINER and bypasses RLS.
-- Admin verification is done at the application layer via verifyAdmin() in the server action.
-- The service role client is used to call this function, which doesn't have JWT context.

CREATE OR REPLACE FUNCTION admin_execute_sql(sql_query text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Execute the query and return results as JSON
  EXECUTE 'SELECT COALESCE(jsonb_agg(row_to_json(t)), ''[]''::jsonb) FROM (' || sql_query || ') t'
  INTO result;

  RETURN result;
END;
$$;

-- Restrict execution to service_role only. Admin checks happen in trusted server code.
REVOKE EXECUTE ON FUNCTION public.admin_execute_sql(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_execute_sql(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_execute_sql(text) TO service_role;
