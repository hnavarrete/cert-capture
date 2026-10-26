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
