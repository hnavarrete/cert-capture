-- IDA Y VUELTA del acceso vigente al grupo (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- VG Certificaciones · 25-oct-2026 · la auditoría interna, solo con acceso VIGENTE al grupo.
-- La parte 2 (20261025000000) dejaba que quien hizo una auditoría siguiera leyendo su informe (con la cédula del socio y
-- las firmas) aunque después le quitaran el acceso al grupo, y vinculaba como auditor interno a cualquier cuenta cuyo
-- correo coincidiera, tuviera o no acceso al grupo. Lo señaló la revisión automática de seguridad del commit ebe6988.
-- Ahora el auditor interno lee su informe y queda vinculado solo mientras tenga nivel en el grupo.

create or replace function compliance.fn_qms_es_inspector(p_slug text, p_inspector uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_inspector = auth.uid() and coalesce(compliance.fn_qms_nivel(p_slug), '') in ('admin', 'gestion', 'captura');
$$;
revoke all on function compliance.fn_qms_es_inspector(text, uuid) from public, anon;
grant execute on function compliance.fn_qms_es_inspector(text, uuid) to authenticated;   -- lo evalúa la política de RLS

drop policy if exists qms_insp_leer on compliance.qms_inspecciones;
create policy qms_insp_leer on compliance.qms_inspecciones for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug) or compliance.fn_qms_es_inspector(client_slug, inspector_id));

create or replace function public.cert_qms_informe(p_id uuid)
returns setof compliance.qms_inspecciones language plpgsql stable security definer set search_path = '' as $$
declare v_slug text; v_insp uuid;
begin
  select client_slug, inspector_id into v_slug, v_insp from compliance.qms_inspecciones where id = p_id;
  if v_slug is null or not (compliance.fn_qms_lee_registro(v_slug) or compliance.fn_qms_es_inspector(v_slug, v_insp)) then
    raise exception 'sin acceso a ese informe' using errcode = '42501';
  end if;
  return query select * from compliance.qms_inspecciones where id = p_id;
end;
$$;

create or replace function public.cert_qms_mis_inspecciones()
returns table (id uuid, client_slug text, checklist text, fecha_plan date, socio_identificacion text, socio_nombre text,
               direccion text, productos jsonb, sitios jsonb)
language plpgsql security definer set search_path = '' as $$
declare v_correo text := lower(coalesce(auth.jwt()->>'email', ''));
begin
  if auth.uid() is null then return; end if;
  update compliance.qms_inspecciones i set inspector_id = auth.uid()
   where i.inspector_id is null and i.estado = 'planificada' and v_correo <> '' and lower(i.inspector_correo) = v_correo
     and coalesce(compliance.fn_qms_nivel(i.client_slug), '') in ('admin', 'gestion', 'captura');
  return query
    select i.id, i.client_slug, i.checklist, i.fecha_plan, m.identificacion, m.nombre, m.direccion, m.productos, m.sitios
      from compliance.qms_inspecciones i join compliance.qms_miembros m on m.id = i.miembro_id
     where i.estado = 'planificada' and (i.inspector_id = auth.uid() or (v_correo <> '' and lower(i.inspector_correo) = v_correo))
       and coalesce(compliance.fn_qms_nivel(i.client_slug), '') in ('admin', 'gestion', 'captura')
     order by i.fecha_plan;
end;
$$;
insert into _h select 'con_migracion', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
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
-- Reversa de 20261025010000: vuelve a las definiciones de 20261025000000 (lo comprueba la ida y vuelta).
drop policy if exists qms_insp_leer on compliance.qms_inspecciones;
create policy qms_insp_leer on compliance.qms_inspecciones for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug) or inspector_id = auth.uid());

create or replace function public.cert_qms_informe(p_id uuid)
returns setof compliance.qms_inspecciones language plpgsql stable security definer set search_path = '' as $$
declare v_slug text; v_insp uuid;
begin
  select client_slug, inspector_id into v_slug, v_insp from compliance.qms_inspecciones where id = p_id;
  if v_slug is null or not (compliance.fn_qms_lee_registro(v_slug) or v_insp = auth.uid()) then
    raise exception 'sin acceso a ese informe' using errcode = '42501';
  end if;
  return query select * from compliance.qms_inspecciones where id = p_id;
end;
$$;

create or replace function public.cert_qms_mis_inspecciones()
returns table (id uuid, client_slug text, checklist text, fecha_plan date, socio_identificacion text, socio_nombre text,
               direccion text, productos jsonb, sitios jsonb)
language plpgsql security definer set search_path = '' as $$
declare v_correo text := lower(coalesce(auth.jwt()->>'email', ''));
begin
  if auth.uid() is null then return; end if;
  update compliance.qms_inspecciones i set inspector_id = auth.uid()
   where i.inspector_id is null and i.estado = 'planificada' and v_correo <> '' and lower(i.inspector_correo) = v_correo;
  return query
    select i.id, i.client_slug, i.checklist, i.fecha_plan, m.identificacion, m.nombre, m.direccion, m.productos, m.sitios
      from compliance.qms_inspecciones i join compliance.qms_miembros m on m.id = i.miembro_id
     where i.estado = 'planificada' and (i.inspector_id = auth.uid() or (v_correo <> '' and lower(i.inspector_correo) = v_correo))
       and coalesce(compliance.fn_qms_nivel(i.client_slug), '') in ('admin', 'gestion', 'captura')
     order by i.fecha_plan;
end;
$$;

drop function if exists compliance.fn_qms_es_inspector(text, uuid);
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
