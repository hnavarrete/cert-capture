-- Prueba de 20261026000000 (incumplimientos y sanciones, QMS 05.03). Corre dentro de ida_y_vuelta_qms_incumplimientos.sql
-- (el RAISE final deshace todo). Usuarios, grupo y cédulas ficticios.
do $prueba$
declare
  g uuid := gen_random_uuid(); c uuid := gen_random_uuid(); a uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  slug text := 'prueba-qms-nc'; m1 uuid; m2 uuid; i1 uuid; n int; t text; r jsonb; nc1 uuid; nc2 uuid; nm uuid; s1 uuid; s2 uuid; e text; ok boolean;
  firma text := 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  tres_minor jsonb;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', em
      from (values (g, 'g-nc@vg.invalid'), (c, 'c-nc@vg.invalid'), (a, 'aud-nc@vg.invalid'), (x, 'x-nc@vg.invalid')) v(u, em);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',   array[slug], 'active', null),
    (a, 'eudr', 'auditor',        '{}',        'active', now() + interval '60 days'),
    (x, 'eudr', 'producer_admin', array['prueba-qms-nc-otro'], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;
  select jsonb_agg(case when nivel = 'Minor' and k <= 3
           then jsonb_build_object('code', code, 'resultado', 'no_cumple', 'comentario', 'Falta registro ' || k, 'plazo', (current_date + 20 + k::int)::text)
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado' end) end order by orden)
    into tres_minor
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;

  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-nc@vg.invalid')::text, true);
  set local role authenticated;
  m1 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999971', 'nombre', 'Socia NC uno',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1}]'::jsonb));
  m2 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999972', 'nombre', 'Socio NC dos',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1}]'::jsonb));
  perform public.cert_qms_cambiar_estado(m1, 'activo'); perform public.cert_qms_cambiar_estado(m2, 'activo');
  perform public.cert_qms_autorizar_auditor(slug, 'aud-nc@vg.invalid', 'Certificador de prueba', current_date + 60);
  i1 := public.cert_qms_planificar(slug, m1, current_date, 'c-nc@vg.invalid');

  -- 01 el técnico envía con 3 Minor que no cumplen → 3 incumplimientos solos, con su plazo y gravedad
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-nc@vg.invalid')::text, true);
  set local role authenticated;
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', (now() - interval '2 hours')::text, 'fin', (now() - interval '1 hour')::text,
          'firmante_nombre', 'Socia', 'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', tres_minor));
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1));   -- reintento: no duplica
  reset role;
  select count(*), bool_and(origen = 'auditoria_interna' and gravedad = 'Minor' and plazo > current_date and estado = 'abierta' and miembro_id = m1)
    into n, ok from compliance.qms_nc where inspeccion_id = i1;
  insert into _res values ('01 informe con 3 no cumple → 3 incumplimientos solos, sin duplicar: ' || case when n = 3 and ok then 'OK' else 'FALLA n=' || n end);

  -- 02 el técnico no ve la lista; el auditor externo sí
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-nc@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_nc_lista(slug); t := 'FALLA (vio)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'aud-nc@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_nc_lista(slug);
  begin perform public.cert_qms_nc_guardar(jsonb_build_object('client_slug', slug, 'origen', 'qms', 'descripcion', 'x', 'plazo', current_date)); t := t || ' / FALLA (escribió)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  reset role;
  insert into _res values ('02 técnico no ve; auditor externo lee (' || n || ') y no escribe: ' || case when n = 3 then t else 'FALLA' end);

  -- 03 la directiva anota acción, responsable y «en curso»; lo encontrado por la auditoría no se reescribe
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-nc@vg.invalid')::text, true);
  set local role authenticated;
  select id into nc1 from public.cert_qms_nc_lista(slug) where inspeccion_id = i1 order by plazo limit 1;
  perform public.cert_qms_nc_guardar(jsonb_build_object('id', nc1, 'descripcion', 'OTRA COSA', 'accion_correctiva', 'Llevar el registro diario',
          'responsable', 'Técnico del grupo', 'plazo', current_date + 15, 'en_curso', true));
  select (estado = 'en_curso' and descripcion = 'Falta registro 1' and responsable = 'Técnico del grupo') into ok from public.cert_qms_nc_lista(slug) where id = nc1;
  insert into _res values ('03 acción, responsable y en curso; lo encontrado no se reescribe: ' || case when ok then 'OK' else 'FALLA' end);

  -- 04 a mano: de la auditoría interna no; de otro grupo no; del organismo certificador sí
  begin perform public.cert_qms_nc_guardar(jsonb_build_object('client_slug', slug, 'miembro_id', m1, 'origen', 'auditoria_interna', 'descripcion', 'x', 'plazo', current_date)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_nc_guardar(jsonb_build_object('client_slug', slug, 'origen', 'auditoria_externa', 'descripcion', 'Sin plazo')); t := t || ' / FALLA (sin plazo)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  nm := public.cert_qms_nc_guardar(jsonb_build_object('client_slug', slug, 'origen', 'auditoria_externa', 'descripcion', 'Procedimiento de retiro sin probar',
          'plazo', current_date + 30));
  select nivel into e from public.cert_qms_nc_lista(slug) where id = nm;
  insert into _res values ('04 a mano: interna no, sin plazo no, del certificador sí (nivel ' || e || '): ' || case when e = 'qms' then t else 'FALLA' end);

  -- 05 cerrar exige acción y responsable; cerrada ya no cambia
  begin perform public.cert_qms_nc_cerrar(nm, 'Simulacro hecho', 'Calidad'); t := 'FALLA (cerró sin responsable)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_nc_cerrar(nc1, '', 'Calidad'); t := t || ' / FALLA (sin evidencia)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  perform public.cert_qms_nc_cerrar(nc1, 'Registro de 30 días revisado en la finca', 'Responsable de calidad');
  begin perform public.cert_qms_nc_guardar(jsonb_build_object('id', nc1, 'accion_correctiva', 'x', 'responsable', 'y', 'plazo', current_date)); t := t || ' / FALLA (editó cerrada)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('05 cierre con acción, responsable y evidencia; cerrada no cambia: ' || t);

  -- 06 advertencia: el socio sigue activo
  s1 := public.cert_qms_sancionar(slug, m2, 'advertencia', 'Registro de cosecha atrasado', 'Responsable de calidad');
  select estado into e from public.cert_qms_miembros(slug) where id = m2;
  insert into _res values ('06 advertencia, el socio sigue activo: ' || case when e = 'activo' then 'OK' else 'FALLA ' || e end);

  -- 07 suspensión ligada a un incumplimiento abierto: socio suspendido y en su historial
  select id into nc2 from public.cert_qms_nc_lista(slug) where inspeccion_id = i1 and estado = 'abierta' order by plazo limit 1;
  begin perform public.cert_qms_sancionar(slug, m2, 'suspension', 'x', 'Calidad', nc2); t := 'FALLA (NC de otro socio)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  s2 := public.cert_qms_sancionar(slug, m1, 'suspension', 'Incumplimiento sin corregir en plazo', 'Responsable de calidad', nc2, 'pitahaya amarilla');
  select estado into e from public.cert_qms_miembros(slug) where id = m1;
  select count(*) into n from public.cert_qms_historial(m1) h where h.a = 'suspendido' and h.motivo = 'Incumplimiento sin corregir en plazo';
  insert into _res values ('07 suspensión: socio suspendido y en su historial; NC ajena rechazada: ' || case when e = 'suspendido' and n = 1 then t else 'FALLA ' || e end);

  -- 08 levantar exige el incumplimiento cerrado (05.03 h)
  begin perform public.cert_qms_sancion_levantar(s2, 'Corregido', 'Calidad'); t := 'FALLA (levantó con NC abierta)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_nc_guardar(jsonb_build_object('id', nc2, 'accion_correctiva', 'Capacitación hecha', 'responsable', 'Técnico', 'plazo', current_date + 10));
  perform public.cert_qms_nc_cerrar(nc2, 'Lista de asistencia firmada', 'Responsable de calidad');
  perform public.cert_qms_sancion_levantar(s2, 'Incumplimiento corregido y verificado', 'Responsable de calidad');
  select estado into e from public.cert_qms_miembros(slug) where id = m1;
  begin perform public.cert_qms_sancion_levantar(s1, 'x', 'y'); t := t || ' / FALLA (levantó una advertencia)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('08 levantar solo con NC cerrada; vuelve a activo; advertencia no se levanta: ' || case when e = 'activo' then t else 'FALLA ' || e end);

  -- 09 aviso al certificador: no en el futuro; una sola vez
  begin perform public.cert_qms_sancion_aviso_cb(s2, current_date + 1); t := 'FALLA (futuro)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_sancion_aviso_cb(s2, current_date);
  begin perform public.cert_qms_sancion_aviso_cb(s2, current_date - 1); t := t || ' / FALLA (cambió el aviso)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('09 aviso al certificador: no futuro, una sola vez: ' || t);

  -- 10 cancelación → excluido; ya no se sanciona otra vez
  perform public.cert_qms_sancionar(slug, m2, 'cancelacion', 'Uso de producto prohibido', 'Responsable de calidad');
  select estado into e from public.cert_qms_miembros(slug) where id = m2;
  begin perform public.cert_qms_sancionar(slug, m2, 'advertencia', 'x', 'y'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  select count(*) into n from public.cert_qms_sanciones(slug);
  insert into _res values ('10 cancelación → excluido; 3 sanciones en la lista (' || n || '): ' || case when e = 'excluido' and n = 3 then t else 'FALLA ' || e end);
  reset role;

  -- 11 ni el dueño de la base borra o edita una sanción o un incumplimiento
  begin delete from compliance.qms_sanciones where id = s1; t := 'FALLA (borró sanción)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin update compliance.qms_sanciones set motivo = 'otro' where id = s1; t := t || ' / FALLA (editó sanción)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  begin delete from compliance.qms_nc where id = nm; t := t || ' / FALLA (borró NC)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('11 sanciones e incumplimientos: ni borrar ni editar: ' || t);

  -- 12 otro grupo: nada; anon: nada
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated', 'email', 'x-nc@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_sanciones(slug); t := 'FALLA (leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_sancionar(slug, m1, 'advertencia', 'x', 'y'); t := t || ' / FALLA (sancionó)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  reset role;
  select bool_or(has_function_privilege('anon', f, 'execute')) into ok from unnest(array[
    'public.cert_qms_nc_lista(text)', 'public.cert_qms_nc_guardar(jsonb)', 'public.cert_qms_nc_cerrar(uuid, text, text)', 'public.cert_qms_sanciones(text)',
    'public.cert_qms_sancionar(text, uuid, text, text, text, uuid, text)', 'public.cert_qms_sancion_aviso_cb(uuid, date)',
    'public.cert_qms_sancion_levantar(uuid, text, text)']) f;
  insert into _res values ('12 otro grupo y anon sin acceso: ' || case when not ok and not has_table_privilege('authenticated', 'compliance.qms_nc', 'select') then t else 'FALLA' end);
end $prueba$;
