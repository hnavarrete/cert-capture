-- Prueba de 20261026010000 (reclamos QMS 04, retiro QMS 07, balance de masas QMS 06 b). Corre dentro de
-- ida_y_vuelta_qms_reclamos_retiro.sql (el RAISE final deshace todo). Usuarios, grupo y cédulas ficticios.
do $prueba$
declare
  g uuid := gen_random_uuid(); c uuid := gen_random_uuid(); a uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  slug text := 'prueba-qms-3b'; m1 uuid; r1 uuid; r2 uuid; nc uuid; t1 uuid; t2 uuid; b1 uuid; n int; t text; e text; ok boolean; v record;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', em
      from (values (g, 'g-3b@vg.invalid'), (c, 'c-3b@vg.invalid'), (a, 'aud-3b@vg.invalid'), (x, 'x-3b@vg.invalid')) s(u, em);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',   array[slug], 'active', null),
    (a, 'eudr', 'auditor',        '{}',        'active', now() + interval '60 days'),
    (x, 'eudr', 'producer_admin', array['prueba-qms-3b-otro'], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;

  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-3b@vg.invalid')::text, true);
  set local role authenticated;
  m1 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999961', 'nombre', 'Socia 3b',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1}]'::jsonb));
  perform public.cert_qms_autorizar_auditor(slug, 'aud-3b@vg.invalid', 'Certificador de prueba', current_date + 60);

  -- 01 reclamo de inocuidad contra un socio; fecha futura no
  begin perform public.cert_qms_reclamo_guardar(jsonb_build_object('client_slug', slug, 'recibido_en', current_date + 1, 'origen', 'cliente',
          'tema', 'inocuidad', 'descripcion', 'x x x')); t := 'FALLA (fecha futura)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  r1 := public.cert_qms_reclamo_guardar(jsonb_build_object('client_slug', slug, 'recibido_en', current_date - 2, 'origen', 'cliente', 'miembro_id', m1,
          'tema', 'inocuidad', 'descripcion', 'Residuo de plaguicida sobre el límite en un embarque'));
  select estado into e from public.cert_qms_reclamos(slug) where id = r1;
  insert into _res values ('01 reclamo registrado («' || e || '»), sin fechas futuras: ' || case when e = 'recibido' then t else 'FALLA' end);

  -- 02 investigación → en investigación
  perform public.cert_qms_reclamo_guardar(jsonb_build_object('id', r1, 'investigacion', 'Se revisó el registro de aplicaciones del lote', 'seguimiento', 'Análisis de residuos pedido'));
  select (estado = 'en_investigacion' and requiere_aviso) into ok from public.cert_qms_reclamos(slug) where id = r1;
  insert into _res values ('02 investigación anotada y aviso exigido por ser de inocuidad: ' || case when ok then 'OK' else 'FALLA' end);

  -- 03 cerrar exige el aviso al certificador (04 e); el aviso no es futuro ni se anota dos veces
  begin perform public.cert_qms_reclamo_cerrar(r1, 'Se corrigió', 'Calidad'); t := 'FALLA (cerró sin aviso)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_reclamo_aviso_cb(r1, current_date + 1); t := t || ' / FALLA (aviso futuro)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  perform public.cert_qms_reclamo_aviso_cb(r1, current_date);
  begin perform public.cert_qms_reclamo_aviso_cb(r1, current_date); t := t || ' / FALLA (dos avisos)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  perform public.cert_qms_reclamo_cerrar(r1, 'Origen identificado; socio sancionado y lote retirado', 'Responsable de calidad');
  begin perform public.cert_qms_reclamo_guardar(jsonb_build_object('id', r1, 'investigacion', 'otra')); t := t || ' / FALLA (editó cerrado)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('03 cierre con aviso al certificador; cerrado no cambia: ' || t);

  -- 04 reclamo de calidad: sin investigación no se cierra; no exige aviso
  r2 := public.cert_qms_reclamo_guardar(jsonb_build_object('client_slug', slug, 'recibido_en', current_date, 'origen', 'cliente', 'tema', 'calidad', 'descripcion', 'Fruta con calibre menor al pedido'));
  begin perform public.cert_qms_reclamo_cerrar(r2, 'ok', 'Calidad'); t := 'FALLA (sin investigación)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_reclamo_guardar(jsonb_build_object('id', r2, 'investigacion', 'Clasificación revisada en el acopio'));
  perform public.cert_qms_reclamo_cerrar(r2, 'Se ajustó la clasificación', 'Calidad');
  select estado into e from public.cert_qms_reclamos(slug) where id = r2;
  insert into _res values ('04 calidad: sin investigación no cierra; sin aviso sí: ' || case when e = 'cerrado' then t else 'FALLA ' || e end);

  -- 05 un incumplimiento que nace del reclamo; un reclamo ajeno no
  nc := public.cert_qms_nc_guardar(jsonb_build_object('client_slug', slug, 'miembro_id', m1, 'origen', 'qms', 'reclamo_id', r2, 'descripcion', 'Clasificación sin calibrar',
          'plazo', current_date + 10));
  select count(*) into n from public.cert_qms_nc_lista(slug) where id = nc and origen = 'reclamo';
  select nc_abiertas into e from public.cert_qms_reclamos(slug) where id = r2;
  begin perform public.cert_qms_nc_guardar(jsonb_build_object('client_slug', slug, 'origen', 'reclamo', 'reclamo_id', gen_random_uuid(), 'descripcion', 'x x', 'plazo', current_date)); t := 'FALLA (reclamo ajeno)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('05 incumplimiento desde el reclamo (origen reclamo, ' || e || ' abierto); ajeno no: ' || case when n = 1 and e = '1' then t else 'FALLA' end);

  -- 06 simulacro: cierre exige conciliación, clientes y resultado; cerrado no cambia
  begin perform public.cert_qms_retiro_guardar(jsonb_build_object('client_slug', slug, 'tipo', 'simulacro', 'iniciado_en', (now() + interval '1 day')::text,
          'producto', 'pitahaya amarilla', 'motivo', 'Simulacro anual', 'decide_nombre', 'Calidad')); t := 'FALLA (inicio futuro)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  t1 := public.cert_qms_retiro_guardar(jsonb_build_object('client_slug', slug, 'tipo', 'simulacro', 'iniciado_en', (now() - interval '3 hours')::text,
          'producto', 'pitahaya amarilla', 'lotes', 'L-2026-041, L-2026-042', 'motivo', 'Simulacro anual: residuo sobre el límite', 'decide_nombre', 'Responsable de calidad'));
  begin perform public.cert_qms_retiro_cerrar(t1, 'Calidad'); t := t || ' / FALLA (sin conciliación)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  perform public.cert_qms_retiro_guardar(jsonb_build_object('id', t1, 'lotes', 'L-2026-041, L-2026-042', 'clientes_avisados', 'Exportadora de prueba (correo)',
          'unidad', 'kg', 'cantidad_afectada', 1200, 'cantidad_localizada', 1176, 'resultado', '98 % localizado en 2 h 40 min'));
  perform public.cert_qms_retiro_cerrar(t1, 'Responsable de calidad');
  select * into v from public.cert_qms_retiros(slug) where id = t1;
  begin perform public.cert_qms_retiro_guardar(jsonb_build_object('id', t1, 'resultado', 'otro')); t := t || ' / FALLA (editó cerrado)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('06 simulacro: no futuro, cierre con conciliación, cerrado no cambia: ' || case when v.estado = 'cerrado' and v.terminado_en > v.iniciado_en then t else 'FALLA' end);

  -- 07 retiro real: se cierra con el aviso al certificador
  t2 := public.cert_qms_retiro_guardar(jsonb_build_object('client_slug', slug, 'tipo', 'real', 'iniciado_en', (now() - interval '1 day')::text, 'producto', 'pitahaya amarilla',
          'motivo', 'Reclamo de inocuidad', 'decide_nombre', 'Directiva', 'clientes_avisados', 'Exportadora', 'unidad', 'cajas', 'cantidad_afectada', 80,
          'cantidad_localizada', 80, 'resultado', 'Todo el lote recuperado'));
  begin perform public.cert_qms_retiro_cerrar(t2, 'Calidad'); t := 'FALLA (real sin aviso)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_retiro_guardar(jsonb_build_object('id', t2, 'clientes_avisados', 'Exportadora', 'unidad', 'cajas', 'cantidad_afectada', 80,
          'cantidad_localizada', 80, 'resultado', 'Todo el lote recuperado', 'aviso_cb_en', current_date));
  perform public.cert_qms_retiro_cerrar(t2, 'Calidad');
  select estado into e from public.cert_qms_retiros(slug) where id = t2;
  insert into _res values ('07 retiro real: se cierra con el aviso al certificador: ' || case when e = 'cerrado' then t else 'FALLA' end);

  -- 08 balance de masas: periodo terminado; registrado no cambia
  begin perform public.cert_qms_balance_registrar(jsonb_build_object('client_slug', slug, 'producto', 'pitahaya amarilla', 'desde', current_date - 30, 'hasta', current_date + 1,
          'unidad', 'kg', 'entradas_cert', 10, 'salidas_cert', 9, 'conclusion', 'x x x', 'hecho_por_nombre', 'Calidad')); t := 'FALLA (periodo sin terminar)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  b1 := public.cert_qms_balance_registrar(jsonb_build_object('client_slug', slug, 'producto', 'pitahaya amarilla', 'desde', current_date - 365, 'hasta', current_date - 1,
          'unidad', 'kg', 'entradas_cert', 152000, 'entradas_no_cert', 8000, 'salidas_cert', 149500, 'salidas_no_cert', 8000, 'existencias_cert', 2500,
          'conclusion', 'Cuadra: entradas certificadas = salidas + existencias', 'fuente', 'VG Custody · balance de masas', 'hecho_por_nombre', 'Responsable de calidad'));
  reset role;
  begin update compliance.qms_balances set conclusion = 'otra' where id = b1; t := t || ' / FALLA (editó)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  begin delete from compliance.qms_retiros where id = t1; t := t || ' / FALLA (borró retiro)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  begin update compliance.qms_reclamos set descripcion = 'otra' where id = r2; t := t || ' / FALLA (reescribió reclamo cerrado)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('08 balance con periodo terminado; nada se edita ni se borra: ' || t);

  -- 09 auditor externo lee; técnico y otro grupo no; anon nada
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'aud-3b@vg.invalid')::text, true);
  set local role authenticated;
  select (select count(*) from public.cert_qms_reclamos(slug)) + (select count(*) from public.cert_qms_retiros(slug)) + (select count(*) from public.cert_qms_balances(slug)) into n;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-3b@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_retiros(slug); t := 'FALLA (técnico leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated', 'email', 'x-3b@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_reclamo_guardar(jsonb_build_object('client_slug', slug, 'recibido_en', current_date, 'origen', 'otro', 'tema', 'otro', 'descripcion', 'x x x')); t := t || ' / FALLA (otro grupo escribió)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  reset role;
  select bool_or(has_function_privilege('anon', f, 'execute')) into ok from unnest(array['public.cert_qms_reclamos(text)', 'public.cert_qms_reclamo_guardar(jsonb)',
    'public.cert_qms_reclamo_aviso_cb(uuid, date)', 'public.cert_qms_reclamo_cerrar(uuid, text, text)', 'public.cert_qms_retiros(text)',
    'public.cert_qms_retiro_guardar(jsonb)', 'public.cert_qms_retiro_cerrar(uuid, text)', 'public.cert_qms_balances(text)',
    'public.cert_qms_balance_registrar(jsonb)', 'public.cert_qms_nc_guardar(jsonb)']) f;
  insert into _res values ('09 auditor lee (' || n || '); técnico, otro grupo y anon no: ' || case when n = 5 and not ok then t else 'FALLA' end);
end $prueba$;
