-- IDA Y VUELTA de las evidencias de la IFA para el auditor (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- VG Certificaciones · 26-oct-2026 · GlobalG.A.P. opción 2 (QMS), parte 3c: el AUDITOR EXTERNO ve las evidencias de la IFA.
-- Punto 4 de la demo del encargo v2 de #15. Hasta hoy, `cert_mis_respuestas` y la lectura del depósito `cert-evidencias`
-- exigían acceso de producto al grupo, que el rol `auditor` de la Capa 0 nunca tiene (no lleva client_slugs). El auditor
-- veía el registro, las auditorías internas y los incumplimientos, pero no lo que cada finca respondió de la IFA.
--   · public.cert_qms_evidencias_ifa(slug): las respuestas de GlobalG.A.P. del grupo, en solo lectura, para quien lee el
--     registro (directiva o calidad, VG y el auditor autorizado). SOLO certificacion = 'GLOBAL_GAP': un auditor de
--     GlobalG.A.P. no ve lo que el grupo captura para EUDR u otras normas. Sin el correo de quien capturó.
--   · Lectura de las fotos y documentos de esas mismas respuestas en `cert-evidencias` (la ruta es
--     <grupo>/<local_id de la respuesta>/...): una política nueva, solo de lectura, que comprueba que el archivo
--     pertenece a una respuesta de GlobalG.A.P. viva del grupo que el auditor tiene autorizado.
-- No toca `cert_mis_respuestas` ni las políticas existentes: el resto de los roles sigue igual.

-- 🔴 En `public`, no en `compliance`: la política del depósito la evalúa el rol de la app, que no tiene acceso al esquema
-- compliance. Con la función allí, TODA lectura de fotos del depósito habría fallado con «permission denied for schema
-- compliance», para todos los usuarios (lo atrapó la prueba de ida y vuelta, 26-oct). Mismo patrón que is_admin y
-- fn_user_has_product_access, que ya usan las otras políticas del depósito.
create or replace function public.fn_qms_auditor_ve_evidencia(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(compliance.fn_qms_nivel(split_part(p_name, '/', 1)), '') = 'auditor'
     and exists (select 1 from compliance.cert_responses c
                  where c.client_slug = split_part(p_name, '/', 1)
                    and c.local_id::text = split_part(p_name, '/', 2)
                    and c.certificacion = 'GLOBAL_GAP' and c.deleted_at is null);
$$;
revoke all on function public.fn_qms_auditor_ve_evidencia(text) from public, anon;
grant execute on function public.fn_qms_auditor_ve_evidencia(text) to authenticated;   -- la evalúa la política del depósito

drop policy if exists cert_evidencias_select_auditor_qms on storage.objects;
create policy cert_evidencias_select_auditor_qms on storage.objects for select to authenticated
  using (bucket_id = 'cert-evidencias' and public.fn_qms_auditor_ve_evidencia(name));

create or replace function public.cert_qms_evidencias_ifa(p_slug text)
returns table (id uuid, local_id uuid, form_key text, producer_id text, finca_id text, lote_id text, data jsonb, fotos jsonb,
               estado text, created_at timestamptz, audit_chain_seq bigint, audit_hash text, audit_timestamp_seal text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'las evidencias de la IFA las ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query
    select c.id, c.local_id, c.form_key, c.producer_id, c.finca_id, c.lote_id, c.data, c.fotos, c.estado, c.created_at,
           c.audit_chain_seq, c.audit_hash, c.audit_timestamp_seal
      from compliance.cert_responses c
     where c.client_slug = p_slug and c.certificacion = 'GLOBAL_GAP' and c.deleted_at is null
     order by c.finca_id nulls last, c.form_key, c.audit_chain_seq;
end;
$$;
revoke all on function public.cert_qms_evidencias_ifa(text) from public, anon;
grant execute on function public.cert_qms_evidencias_ifa(text) to authenticated, service_role;
insert into _h select 'con_migracion', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- Prueba de 20261026020000 (el auditor externo ve las evidencias de la IFA). Corre dentro de
-- ida_y_vuelta_qms_auditor_evidencias.sql (el RAISE final deshace todo). Datos ficticios.
do $prueba$
declare
  g uuid := gen_random_uuid(); c uuid := gen_random_uuid(); a uuid := gen_random_uuid(); x uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
  slug text := 'prueba-qms-evid'; lg uuid := gen_random_uuid(); le uuid := gen_random_uuid(); n int; t text; ok boolean; ok2 boolean;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', em
      from (values (g, 'g-ev@vg.invalid'), (c, 'c-ev@vg.invalid'), (a, 'aud-ev@vg.invalid'), (x, 'x-ev@vg.invalid'), (a2, 'aud2-ev@vg.invalid')) s(u, em);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',   array[slug], 'active', null),
    (a, 'eudr', 'auditor',        '{}',        'active', now() + interval '60 days'),
    (a2, 'eudr', 'auditor',       '{}',        'active', now() + interval '60 days'),   -- auditor sin autorización de este grupo
    (x, 'eudr', 'producer_admin', array['prueba-qms-evid-otro'], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;
  -- una respuesta de GlobalG.A.P. y una de EUDR del mismo grupo, con su foto
  insert into compliance.cert_responses (local_id, client_slug, form_key, certificacion, finca_id, data, fotos)
  values (lg, slug, 'globalgap_fv_smart', 'GLOBAL_GAP', 'finca-ev-1', '{"sec_3.fv_smart_03_01.estado":"cumple"}'::jsonb,
          jsonb_build_array(jsonb_build_object('field', 'sec_3.fv_smart_03_01__evidencia', 'path', slug || '/' || lg || '/foto.jpg', 'bucket', 'cert-evidencias'))),
         (le, slug, 'eudr_dds', 'EUDR', 'finca-ev-1', '{"x":"y"}'::jsonb, '[]'::jsonb);

  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-ev@vg.invalid')::text, true);
  set local role authenticated;
  perform public.cert_qms_autorizar_auditor(slug, 'aud-ev@vg.invalid', 'Certificador de prueba', current_date + 60);
  select count(*) into n from public.cert_qms_evidencias_ifa(slug);
  insert into _res values ('01 la directiva ve solo lo de GlobalG.A.P. (' || n || '): ' || case when n = 1 then 'OK' else 'FALLA' end);
  reset role;

  -- 02 el auditor autorizado: ve la respuesta de GlobalG.A.P. y su foto; no la de EUDR ni su ruta
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'aud-ev@vg.invalid')::text, true);
  set local role authenticated;
  select count(*), bool_and(form_key = 'globalgap_fv_smart' and data->>'sec_3.fv_smart_03_01.estado' = 'cumple') into n, ok from public.cert_qms_evidencias_ifa(slug);
  ok2 := public.fn_qms_auditor_ve_evidencia(slug || '/' || lg || '/foto.jpg') and not public.fn_qms_auditor_ve_evidencia(slug || '/' || le || '/doc.pdf')
         and not public.fn_qms_auditor_ve_evidencia(slug || '/' || gen_random_uuid() || '/x.jpg');
  begin perform public.cert_mis_respuestas(slug, null); t := 'FALLA (entró a cert_mis_respuestas)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('02 auditor: 1 respuesta GlobalG.A.P. y su foto; EUDR no; cert_mis_respuestas sigue cerrada: ' || case when n = 1 and ok and ok2 then t else 'FALLA n=' || n end);
  reset role;

  -- 03 auditor sin autorización de este grupo, técnico (que tiene su propia vía) y otro grupo: nada por aquí
  perform set_config('request.jwt.claims', json_build_object('sub', a2, 'role', 'authenticated', 'email', 'aud2-ev@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_evidencias_ifa(slug); t := 'FALLA (auditor no autorizado leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  ok := not public.fn_qms_auditor_ve_evidencia(slug || '/' || lg || '/foto.jpg');
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-ev@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_evidencias_ifa(slug); t := t || ' / FALLA (técnico)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated', 'email', 'x-ev@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_evidencias_ifa(slug); t := t || ' / FALLA (otro grupo)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  reset role;
  insert into _res values ('03 auditor no autorizado, técnico y otro grupo no leen por aquí: ' || case when ok then t else 'FALLA (foto)' end);

  -- 04 la política del depósito existe, es solo de lectura, y anon no ejecuta nada
  select count(*) into n from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'cert_evidencias_select_auditor_qms' and cmd = 'SELECT';
  insert into _res values ('04 política de solo lectura en el depósito; anon sin acceso: ' || case when n = 1
    and not has_function_privilege('anon', 'public.cert_qms_evidencias_ifa(text)', 'execute')
    and not has_function_privilege('anon', 'public.fn_qms_auditor_ve_evidencia(text)', 'execute') then 'OK' else 'FALLA' end);
  -- 05 leer el depósito con el rol de la app no falla (la política nueva se evalúa para TODOS los usuarios)
  t := '';
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-ev@vg.invalid')::text, true);
  set local role authenticated;
  begin perform count(*) from storage.objects where bucket_id = 'cert-evidencias'; t := 'OK';
  exception when others then t := 'FALLA directiva ' || sqlstate || ' ' || left(sqlerrm, 60); end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'aud-ev@vg.invalid')::text, true);
  set local role authenticated;
  begin perform count(*) from storage.objects where bucket_id = 'cert-evidencias'; t := t || ' / OK';
  exception when others then t := t || ' / FALLA auditor ' || sqlstate || ' ' || left(sqlerrm, 60); end;
  reset role;
  insert into _res values ('05 leer el depósito con el rol de la app no falla (directiva y auditor): ' || t);
end $prueba$;
-- Reversa de 20261026020000_cert_qms_auditor_evidencias_ifa.sql (lo comprueba la ida y vuelta).
drop function if exists public.cert_qms_evidencias_ifa(text);
drop policy if exists cert_evidencias_select_auditor_qms on storage.objects;
drop function if exists public.fn_qms_auditor_ve_evidencia(text);
insert into _h select 'despues', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  -- La API de gestión corta el mensaje hacia los 500 caracteres: se cuentan los OK y se muestran enteras solo las fallas.
  select count(*) filter (where t !~ 'FALLA') || ' de ' || count(*) || ' OK'
         || coalesce(' · FALLAS: ' || string_agg(t, ' || ' order by t) filter (where t ~ 'FALLA'), '')
    into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, left(a, 8), left(c, 8), left(d, 8),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
