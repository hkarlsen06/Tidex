DO $$
BEGIN
  IF to_regprocedure('public.admin_execute_sql_api(text)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql_api(text) FROM PUBLIC;
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql_api(text) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql_api(text) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql_api(text) FROM service_role;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.admin_execute_sql_api(text);

DO $$
BEGIN
  IF to_regprocedure('public.admin_execute_sql(text)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql(text) FROM PUBLIC;
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql(text) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql(text) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.admin_execute_sql(text) FROM service_role;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.admin_execute_sql(text);
