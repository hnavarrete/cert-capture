select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance', 'attest') and p.prokind = 'f'
     and (n.nspname in ('compliance', 'attest') or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema in ('compliance', 'attest')
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname in ('compliance', 'attest')
  union all select 'n:form_defs:'||count(*) from compliance.cert_form_defs
  union all select 'c:'||md5(c::text) from attest.certifications c where code = 'fairtrade'
) s
