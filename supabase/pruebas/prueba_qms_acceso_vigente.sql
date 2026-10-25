-- Prueba de 20261025010000: el auditor interno lee su informe y queda vinculado solo con acceso vigente al grupo.
-- Corre dentro de ida_y_vuelta_qms_acceso_vigente.sql (el RAISE final deshace todo). Usuarios y cédulas ficticios.
do $prueba$
declare
  g uuid := gen_random_uuid(); c uuid := gen_random_uuid(); u uuid := gen_random_uuid();
  slug text := 'prueba-qms-vigente'; m1 uuid; m2 uuid; i1 uuid; i2 uuid; res jsonb; n int; t text; v uuid;
  firma text := 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select x, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', e
      from (values (g, 'g-vig@vg.invalid'), (c, 'c-vig@vg.invalid'), (u, 'u-vig@vg.invalid')) s(x, e);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',   array[slug], 'active', null),
    (u, 'eudr', 'field_worker',   array['otro-grupo-vig'], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;
  select jsonb_agg(jsonb_build_object('code', code, 'resultado', 'cumple',
           'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) order by orden)
    into res from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart';

  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-vig@vg.invalid')::text, true);
  set local role authenticated;
  m1 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999981', 'nombre', 'Socia vigente uno',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1}]'::jsonb));
  m2 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999982', 'nombre', 'Socio vigente dos',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1}]'::jsonb));
  perform public.cert_qms_cambiar_estado(m1, 'activo'); perform public.cert_qms_cambiar_estado(m2, 'activo');
  i1 := public.cert_qms_planificar(slug, m1, current_date, 'c-vig@vg.invalid');
  i2 := public.cert_qms_planificar(slug, m2, current_date, 'u-vig@vg.invalid');   -- correo de una cuenta SIN acceso al grupo

  -- 01 una cuenta sin acceso al grupo no queda vinculada ni ve la auditoría, aunque su correo coincida
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'email', 'u-vig@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_mis_inspecciones();
  reset role;
  select inspector_id into v from compliance.qms_inspecciones where id = i2;
  insert into _res values ('01 sin acceso al grupo: ni la ve ni queda vinculada (' || n || '): ' || case when n = 0 and v is null then 'OK' else 'FALLA' end);

  -- 02 el técnico con acceso la hace, la envía y lee su informe
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-vig@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_mis_inspecciones();
  perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', (now() - interval '2 hours')::text, 'fin', (now() - interval '1 hour')::text,
          'firmante_nombre', 'Socia', 'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', res));
  select count(*) into n from public.cert_qms_informe(i1);
  insert into _res values ('02 con acceso: envía y lee su informe: ' || case when n = 1 then 'OK' else 'FALLA' end);

  -- 03 se le quita el acceso al grupo: ya no lee su informe (función ni tabla)
  reset role;
  update public.user_products set client_slugs = array['otro-grupo-vig'] where user_id = c and product = 'eudr';
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-vig@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_informe(i1); t := 'FALLA (leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('03 sin acceso vigente ya no lee su informe: ' || t);
  reset role;

  -- 04 la directiva sigue leyéndolo
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-vig@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_informe(i1);
  insert into _res values ('04 la directiva lo sigue leyendo: ' || case when n = 1 then 'OK' else 'FALLA' end);
  reset role;
end $prueba$;
