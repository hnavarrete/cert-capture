-- Prueba de la auditoría interna de finca (QMS 05.02). Corre DESPUÉS de la migración 20261025000000, dentro de la
-- transacción de ida_y_vuelta_qms_auditoria_interna.sql. Usuarios, grupo y cédulas ficticios. Cada resultado va a _res;
-- el error final de la ida y vuelta deshace todo y trae los resultados en su mensaje.
do $prueba$
declare
  g uuid := gen_random_uuid(); q uuid := gen_random_uuid(); c uuid := gen_random_uuid(); l uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  slug text := 'prueba-qms-auditoria'; otro text := 'prueba-qms-otro2';
  m1 uuid; m2 uuid; m3 uuid; mx uuid; i1 uuid; i2 uuid; i3 uuid;
  todo_cumple jsonb; tres_minor jsonb; major_nc jsonb; sin_coment jsonb; sin_plazo jsonb; incompleto jsonb; nivel_falso jsonb;
  firma text := 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  ini text := (now() - interval '2 hours')::text; fin text := (now() - interval '50 minutes')::text;
  n int; t text; r jsonb; ok boolean; d date;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', e
      from (values (g, 'g-ai@vg.invalid'), (q, 'q-ai@vg.invalid'), (c, 'c-ai@vg.invalid'), (l, 'l-ai@vg.invalid'),
                   (a, 'auditora-ai@vg.invalid'), (x, 'x-ai@vg.invalid')) v(u, e);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin',         array[slug], 'active', null),
    (q, 'eudr', 'gerente_sostenibilidad', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',           array[slug], 'active', null),
    (l, 'eudr', 'lector',                 array[slug], 'active', null),
    (a, 'eudr', 'auditor',                '{}',        'active', now() + interval '60 days'),
    (x, 'eudr', 'producer_admin',         array[otro], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;

  -- Los informes de prueba se arman con la lista oficial (como superusuario: la app no lee la tabla).
  select jsonb_agg(jsonb_build_object('code', code, 'resultado', 'cumple',
           'comentario', case when nivel = 'Major' then 'Verificado en finca (prueba)' end) order by orden)
    into todo_cumple from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart';
  -- 3 Minor de 71 no cumplen → 95,8 %: cumple
  select jsonb_agg(case when nivel = 'Minor' and k <= 3
           then jsonb_build_object('code', code, 'resultado', 'no_cumple', 'comentario', 'Falta registro (prueba)', 'plazo', (current_date + 30)::text)
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) end order by orden)
    into tres_minor
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;
  -- 1 Major no cumple → no cumple aunque el equipo diga que es Minor
  select jsonb_agg(case when nivel = 'Major' and k = 1
           then jsonb_build_object('code', code, 'nivel', 'Minor', 'resultado', 'no_cumple', 'comentario', 'Sin análisis de agua (prueba)', 'plazo', (current_date + 15)::text)
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) end order by orden)
    into major_nc
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;
  nivel_falso := major_nc;
  select jsonb_agg(jsonb_build_object('code', code, 'resultado', 'cumple') order by orden)
    into sin_coment from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart';
  select jsonb_agg(case when nivel = 'Minor' and k = 1
           then jsonb_build_object('code', code, 'resultado', 'no_cumple', 'comentario', 'Falta (prueba)')
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) end order by orden)
    into sin_plazo
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;
  select jsonb_agg(e) into incompleto from (select e from jsonb_array_elements(todo_cumple) e limit 90) s;

  -- socios y auditor externo (directiva)
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-ai@vg.invalid')::text, true);
  set local role authenticated;
  m1 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999991', 'nombre', 'Socia auditada uno',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":2.1}]'::jsonb, 'sitios', '[{"nombre":"Finca Uno","area_ha":2.1,"certificado":true}]'::jsonb));
  m2 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999992', 'nombre', 'Socio auditado dos',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1.5}]'::jsonb));
  m3 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999993', 'nombre', 'Aspirante tres',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1.0}]'::jsonb));
  mx := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999994', 'nombre', 'Excluido cuatro',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1.0}]'::jsonb));
  perform public.cert_qms_cambiar_estado(m1, 'activo'); perform public.cert_qms_cambiar_estado(m2, 'activo');
  perform public.cert_qms_cambiar_estado(mx, 'excluido', 'Producto no autorizado (prueba)');
  perform public.cert_qms_autorizar_auditor(slug, 'auditora-ai@vg.invalid', 'Certificador de prueba', current_date + 60);

  -- 01 la directiva planifica y asigna al técnico
  i1 := public.cert_qms_planificar(slug, m1, current_date, 'C-AI@vg.invalid');
  insert into _res values ('01 la directiva planifica la auditoría: ' || case when i1 is not null then 'OK' else 'FALLA' end);
  -- 02 una sola abierta por socio
  begin perform public.cert_qms_planificar(slug, m1, current_date + 3, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when unique_violation then t := 'OK'; when others then t := 'FALLA ' || sqlstate; end;
  insert into _res values ('02 una sola auditoría abierta por socio: ' || t);
  -- 03 un excluido no se audita
  begin perform public.cert_qms_planificar(slug, mx, current_date, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('03 un socio excluido no se planifica: ' || t);
  i2 := public.cert_qms_planificar(slug, m2, current_date, 'g-ai@vg.invalid');     -- la directiva se asigna a sí misma
  i3 := public.cert_qms_planificar(slug, m3, current_date + 10, 'c-ai@vg.invalid');

  -- 04 el técnico no planifica, pero ve SOLO lo suyo, con lo necesario para la finca
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-ai@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_planificar(slug, m2, current_date, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('04 el técnico no planifica: ' || t);
  select count(*), bool_and(socio_nombre is not null and productos is not null) into n, ok from public.cert_qms_mis_inspecciones();
  insert into _res values ('05 el técnico ve sus 2 auditorías asignadas (' || n || '): ' || case when n = 2 and ok then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_cronograma(slug); t := 'FALLA (vio el cronograma)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('05b el técnico no ve el cronograma del grupo: ' || t);

  -- 06 informes incompletos: el servidor dice qué falta
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', incompleto)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%faltan 7 puntos%' then 'OK' else 'FALLA ' || sqlstate || ' ' || sqlerrm end; end;
  insert into _res values ('06 informe con 7 puntos sin resultado se rechaza: ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', sin_coment)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%26 puntos necesitan comentario%' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('07 Major sin comentario se rechaza (26): ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', sin_plazo)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%sin plazo%' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('08 incumplimiento sin plazo se rechaza: ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', null, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', todo_cumple)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%firmas%' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('09 sin la firma del socio se rechaza: ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', fin, 'fin', ini, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', todo_cumple)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('10 fin antes del inicio se rechaza: ' || t);

  -- 11 envío válido: 3 Minor de 71 no cumplen → 95,8 % y cumple
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia auditada uno',
          'firma_socio', firma, 'inspector_nombre', 'Técnico de prueba', 'firma_inspector', firma, 'resultados', tres_minor));
  insert into _res values ('11 envío válido (95,8 por ciento, cumple): ' || case when (r->>'pct_minor')::numeric = 95.8 and (r->>'cumple')::boolean
    and (r->>'major_aplicables')::int = 26 and (r->>'minor_no_cumple')::int = 3 then 'OK' else 'FALLA ' || r::text end);
  -- 12 reintento tras perder la respuesta: mismo resultado, sin error
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'X',
          'firma_socio', firma, 'inspector_nombre', 'X', 'firma_inspector', firma, 'resultados', todo_cumple));
  insert into _res values ('12 reenviar es idempotente (no pisa el original): ' || case when (r->>'minor_no_cumple')::int = 3 then 'OK' else 'FALLA' end);
  select count(*) into n from public.cert_qms_mis_inspecciones();
  insert into _res values ('13 lo enviado sale de la lista del técnico (' || n || '): ' || case when n = 1 then 'OK' else 'FALLA' end);
  select count(*) into n from public.cert_qms_informe(i1) where firma_socio is not null;
  insert into _res values ('14 el técnico lee su propio informe: ' || case when n = 1 then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_decidir(i1, 'conforme', 'Técnico'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('15 el técnico no decide: ' || t);

  -- 16 el informe enviado no se edita ni se borra, ni siquiera el dueño de la base
  reset role;
  begin update compliance.qms_inspecciones set resultados = todo_cumple where id = i1; t := 'FALLA (editó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin delete from compliance.qms_inspecciones where id = i1; t := t || ' / FALLA (borró)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('16 informe enviado: ni editar ni borrar: ' || t);

  -- 17 quien audita no aprueba (la directiva se auditó m2 y no puede decidir sobre ella)
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-ai@vg.invalid')::text, true);
  set local role authenticated;
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i2, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socio dos',
          'firma_socio', firma, 'inspector_nombre', 'Directiva', 'firma_inspector', firma, 'resultados', nivel_falso));
  insert into _res values ('17 el nivel lo pone el servidor: Major no cumple aunque el equipo diga Minor: '
    || case when (r->>'major_no_cumple')::int = 1 and not (r->>'cumple')::boolean then 'OK' else 'FALLA ' || r::text end);
  begin perform public.cert_qms_decidir(i2, 'no_conforme', 'Directiva', 'Major sin cumplir'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('18 quien hizo la auditoría no la aprueba (12.5 a): ' || t);

  -- 19 calidad decide: conforme bloqueado si no cumple; no conforme exige motivo
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', q, 'role', 'authenticated', 'email', 'q-ai@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_decidir(i2, 'conforme', 'Calidad'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_decidir(i2, 'no_conforme', 'Calidad', ''); t := t || ' / FALLA (sin motivo)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  perform public.cert_qms_decidir(i2, 'no_conforme', 'Responsable de calidad', 'Major sin cumplir: análisis de agua');
  insert into _res values ('19 conforme bloqueado si no cumple; no conforme con motivo: ' || t);
  begin perform public.cert_qms_decidir(i1, 'conforme', ''); t := 'FALLA (sin nombre)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_decidir(i1, 'conforme', 'Responsable de calidad');
  select ultima_auditoria_interna into d from public.cert_qms_miembros(slug) where id = m1;
  insert into _res values ('20 conforme con nombre y fecha en el registro del socio: ' || case when t = 'OK'
    and d = ((ini::timestamptz) at time zone 'America/Guayaquil')::date then 'OK' else 'FALLA ' || t || ' ' || coalesce(d::text, 'sin fecha') end);
  begin perform public.cert_qms_decidir(i1, 'no_conforme', 'Otro', 'cambio'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('21 una decisión no se cambia: ' || t);

  -- 22 cancelar: con motivo y solo lo que no se hizo
  begin perform public.cert_qms_cancelar_inspeccion(i3, ' '); t := 'FALLA (sin motivo)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_cancelar_inspeccion(i3, 'El socio viaja; se reprograma (prueba)');
  begin perform public.cert_qms_cancelar_inspeccion(i1, 'tarde'); t := t || ' / FALLA (canceló un enviado)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  select count(*) into n from public.cert_qms_cronograma(slug);
  insert into _res values ('22 cancelar exige motivo y solo lo no hecho (cronograma ' || n || '): ' || case when n = 3 then t else 'FALLA' end);

  -- 23 auditor externo: lee el cronograma y el informe con firmas
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'auditora-ai@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_cronograma(slug);
  select (firma_inspector is not null and decision = 'conforme') into ok from public.cert_qms_informe(i1);
  insert into _res values ('23 el auditor externo lee cronograma e informe: ' || case when n = 3 and ok then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_planificar(slug, m3, current_date, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('24 el auditor externo no planifica: ' || t);

  -- 25 otro grupo y solo lectura: nada
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated', 'email', 'x-ai@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_informe(i1); t := 'FALLA (leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_cronograma(slug); t := t || ' / FALLA (leyó)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('25 otro grupo no lee informe ni cronograma: ' || t);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated', 'email', 'l-ai@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_mis_inspecciones();
  begin perform public.cert_qms_informe(i1); t := 'FALLA (leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('26 solo lectura: sin auditorías ni informes (' || n || '): ' || case when n = 0 then t else 'FALLA' end);
  reset role;

  -- 27 anon no ejecuta nada; authenticated no toca las tablas
  select bool_or(has_function_privilege('anon', f, 'execute')) into ok from unnest(array[
    'public.cert_qms_cronograma(text)', 'public.cert_qms_planificar(text, uuid, date, text)', 'public.cert_qms_cancelar_inspeccion(uuid, text)',
    'public.cert_qms_mis_inspecciones()', 'public.cert_qms_enviar_inspeccion(jsonb)', 'public.cert_qms_informe(uuid)',
    'public.cert_qms_decidir(uuid, text, text, text)']) f;
  insert into _res values ('27 anon sin permiso; tablas cerradas: ' || case when not ok
    and not has_table_privilege('authenticated', 'compliance.qms_inspecciones', 'select')
    and not has_table_privilege('authenticated', 'compliance.qms_inspecciones', 'update') then 'OK' else 'FALLA' end);
end $prueba$;
