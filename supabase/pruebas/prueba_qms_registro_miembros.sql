-- Prueba del registro interno de miembros y del auditor externo (QMS 4.1.2.2). Corre DESPUÉS de la migración, dentro de
-- la transacción de ida_y_vuelta_qms_registro_miembros.sql. Usuarios, grupo y cédulas ficticios. Cada resultado va a _res;
-- el error final de la ida y vuelta deshace todo y trae los resultados en su mensaje.
do $prueba$
declare
  g uuid := gen_random_uuid(); c uuid := gen_random_uuid(); l uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  slug text := 'prueba-qms-pitahaya'; otro text := 'prueba-qms-otro';
  m1 uuid; m2 uuid; aud uuid; n int; t text; ok boolean;
  procedure_dummy int;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', e
      from (values (g, 'g-qms@vg.invalid'), (c, 'c-qms@vg.invalid'), (l, 'l-qms@vg.invalid'), (a, 'auditora-qms@vg.invalid'),
                   (x, 'x-qms@vg.invalid')) v(u, e);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',   array[slug], 'active', null),
    (l, 'eudr', 'lector',         array[slug], 'active', null),
    (a, 'eudr', 'auditor',        '{}',        'active', now() + interval '60 days'),
    (x, 'eudr', 'producer_admin', array[otro], 'active', null)
  -- el alta en auth.users ya crea una fila eudr por usuario (disparador de la Capa 0): se reemplaza
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;

  -- 01 alta por la directiva
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-qms@vg.invalid')::text, true);
  set local role authenticated;
  m1 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999998', 'nombre', 'Socia de prueba uno',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":2.1}]'::jsonb, 'sitios', '[{"nombre":"Finca Uno","area_ha":2.1,"certificado":true}]'::jsonb,
          'certificador', 'Certificador de prueba', 'fecha_ingreso', '2024-03-01'));
  select count(*) into n from public.cert_qms_historial(m1);
  insert into _res values ('01 alta por gestión + historial (1): ' || case when m1 is not null and n = 1 then 'OK' else 'FALLA n=' || n end);

  -- 02 activar
  perform public.cert_qms_cambiar_estado(m1, 'activo');
  select count(*) into n from public.cert_qms_historial(m1);
  insert into _res values ('02 activar + historial (2): ' || case when n = 2 then 'OK' else 'FALLA n=' || n end);

  -- 03 excluir sin motivo → rechazo
  begin perform public.cert_qms_cambiar_estado(m1, 'excluido'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('03 excluir sin motivo se rechaza: ' || t);

  -- 04 excluir con motivo → fecha y historial
  perform public.cert_qms_cambiar_estado(m1, 'excluido', 'Uso de producto no autorizado (prueba)');
  select (excluido_en is not null and estado = 'excluido') into ok from public.cert_qms_miembros(slug) where id = m1;
  select count(*) into n from public.cert_qms_historial(m1);
  insert into _res values ('04 excluir con motivo: ' || case when ok and n = 3 then 'OK' else 'FALLA' end);

  -- 05 misma cédula en el mismo grupo → rechazo
  begin perform public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999998', 'nombre', 'Duplicada'));
        t := 'FALLA (aceptó)';
  exception when unique_violation then t := 'OK'; when others then t := 'FALLA ' || sqlstate; end;
  insert into _res values ('05 cédula repetida en el grupo se rechaza: ' || t);
  m2 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '1799999990001', 'nombre', 'Socio de prueba dos'));

  -- 06 captura (socio o técnico) no registra socios
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-qms@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999997', 'nombre', 'Intento'));
        t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('06 captura no registra socios: ' || t);

  -- 07 lector lee pero no escribe
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated', 'email', 'l-qms@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_miembros(slug);
  begin perform public.cert_qms_cambiar_estado(m2, 'activo'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('07 lector ve ' || n || ' socios (2) y no cambia estados: ' || case when n = 2 then t else 'FALLA' end);

  -- 08 otro grupo no ve nada
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated', 'email', 'x-qms@vg.invalid')::text, true);
  set local role authenticated;
  begin select count(*) into n from public.cert_qms_miembros(slug); t := 'FALLA (vio ' || n || ')';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('08 otro grupo no ve los socios: ' || t);

  -- 09 auditor SIN autorización del grupo: nada
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'auditora-qms@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_mis_grupos();
  begin perform public.cert_qms_miembros(slug); t := 'FALLA (vio)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('09 auditor sin autorización: 0 grupos (' || n || ') y sin lectura: ' || case when n = 0 then t else 'FALLA' end);

  -- 10 la directiva autoriza (y un vencimiento de más de un año se rechaza)
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-qms@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_autorizar_auditor(slug, 'otra@vg.invalid', 'Organismo de prueba', current_date + 400); t := 'FALLA (aceptó)';
  exception when check_violation then t := 'OK'; when others then t := 'FALLA ' || sqlstate; end;
  aud := public.cert_qms_autorizar_auditor(slug, 'Auditora-QMS@vg.invalid', 'Organismo de prueba', current_date + 30);
  insert into _res values ('10 vencimiento > 1 año se rechaza: ' || t || ' · autorizado a 30 días: ' || case when aud is not null then 'OK' else 'FALLA' end);

  -- 11 el auditor entra en solo lectura
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'auditora-qms@vg.invalid')::text, true);
  set local role authenticated;
  select nivel into t from public.cert_qms_mis_grupos() where client_slug = slug;
  select count(*) into n from public.cert_qms_miembros(slug);
  insert into _res values ('11 auditor: nivel ' || coalesce(t, '<nada>') || ' (auditor), ve ' || n || ' socios (2): '
    || case when t = 'auditor' and n = 2 then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_guardar_miembro(jsonb_build_object('id', m2, 'nombre', 'Cambio del auditor')); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('12 auditor no edita: ' || t);
  begin perform public.cert_qms_auditores(slug); t := 'FALLA (vio la lista)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('13 auditor no ve la lista de auditores: ' || t);

  -- 14 revocado: deja de ver
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-qms@vg.invalid')::text, true);
  set local role authenticated;
  perform public.cert_qms_revocar_auditor(aud);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'auditora-qms@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_miembros(slug); t := 'FALLA (sigue viendo)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('14 auditor revocado deja de ver: ' || t);

  -- 15 las tablas no se tocan directo; el historial no se edita; la cédula no cambia
  begin select count(*) into n from compliance.qms_miembros; t := 'FALLA (leyó la tabla)';
  exception when insufficient_privilege then t := 'OK'; when others then t := 'FALLA ' || sqlstate; end;
  insert into _res values ('15 authenticated no lee la tabla directo: ' || t);
  reset role;
  begin update compliance.qms_miembros_historial set a = 'activo' where miembro_id = m1; t := 'FALLA (editó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('16 historial inmutable (ni el dueño de la base): ' || t);
  begin update compliance.qms_miembros set identificacion = '0999999997' where id = m2; t := 'FALLA (cambió)';
  exception when others then t := case when sqlstate = '23514' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('17 la cédula de un socio no cambia: ' || t);
  insert into _res values ('18 anónimo sin ejecución: ' ||
    case when not has_function_privilege('anon', 'public.cert_qms_miembros(text)', 'execute')
          and not has_function_privilege('anon', 'public.cert_qms_guardar_miembro(jsonb)', 'execute') then 'OK' else 'FALLA' end);
end $prueba$;
