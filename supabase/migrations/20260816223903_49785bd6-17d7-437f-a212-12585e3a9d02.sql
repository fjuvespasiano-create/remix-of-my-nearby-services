CREATE OR REPLACE FUNCTION public.admin_export_full_backup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t record;
  rows_json jsonb;
  tables_json jsonb := '{}'::jsonb;
  counts_json jsonb := '{}'::jsonb;
BEGIN
  -- Somente administradores (ou o service_role interno) podem exportar tudo.
  IF auth.uid() IS NOT NULL AND NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Acesso restrito a administradores.';
  END IF;

  FOR t IN
    SELECT c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
    ORDER BY c.relname
  LOOP
    EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) FROM public.%I x', t.table_name)
      INTO rows_json;
    tables_json := tables_json || jsonb_build_object(t.table_name, rows_json);
    counts_json := counts_json || jsonb_build_object(t.table_name, jsonb_array_length(rows_json));
  END LOOP;

  RETURN jsonb_build_object(
    'schema_version', 1,
    'created_at', now(),
    'source', 'admin_export_full_backup',
    'counts', counts_json,
    'tables', tables_json
  );
END $$;

REVOKE ALL ON FUNCTION public.admin_export_full_backup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_export_full_backup() TO authenticated, service_role;