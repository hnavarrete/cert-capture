-- IDA Y VUELTA del registro solo para gestión y auditor (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- VG Certificaciones · 23-oct-2026 · el registro interno de miembros lo leen SOLO la directiva o calidad, VG y el auditor.
-- La parte 1 (20261023000000) dejaba leer el registro a todo nivel con acceso al grupo, incluidos los socios y técnicos
-- (captura) y el rol de solo lectura: cada socio veía la cédula, el teléfono, el correo y la dirección de todos los demás.
-- Lo señaló la revisión automática de seguridad del commit 29909c5. El QMS no lo necesita: el registro es de la
-- directiva (4.1.2.2) y del auditor. Aquí se cierran las funciones, las políticas de lectura y la lista de grupos.

create or replace function compliance.fn_qms_lee_registro(p_slug text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(compliance.fn_qms_nivel(p_slug), '') in ('admin', 'gestion', 'auditor');
$$;
revoke all on function compliance.fn_qms_lee_registro(text) from public, anon;
grant execute on function compliance.fn_qms_lee_registro(text) to authenticated;   -- lo evalúan las políticas de RLS

drop policy if exists qms_miembros_leer on compliance.qms_miembros;
create policy qms_miembros_leer on compliance.qms_miembros for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug));
drop policy if exists qms_historial_leer on compliance.qms_miembros_historial;
create policy qms_historial_leer on compliance.qms_miembros_historial for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug));

create or replace function public.cert_qms_miembros(p_slug text)
returns setof compliance.qms_miembros language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'el registro de socios lo ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query select * from compliance.qms_miembros m where m.client_slug = p_slug order by m.estado = 'excluido', m.nombre;
end;
$$;

create or replace function public.cert_qms_historial(p_miembro uuid)
returns setof compliance.qms_miembros_historial language plpgsql stable security definer set search_path = '' as $$
declare v_slug text;
begin
  select client_slug into v_slug from compliance.qms_miembros where id = p_miembro;
  if v_slug is null or not compliance.fn_qms_lee_registro(v_slug) then
    raise exception 'sin acceso a ese socio' using errcode = '42501';
  end if;
  return query select * from compliance.qms_miembros_historial h where h.miembro_id = p_miembro order by h.en;
end;
$$;

-- «Mi grupo» aparece solo donde la cuenta lee el registro (la app muestra el botón según esta lista).
create or replace function public.cert_qms_mis_grupos()
returns table (client_slug text, nivel text, vence date)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  update compliance.qms_auditores a set user_id = auth.uid()
   where a.user_id is null and a.revocado_en is null and lower(a.correo) = lower(coalesce(auth.jwt()->>'email', ''))
     and coalesce(auth.jwt()->>'email', '') <> '';
  return query
    select s.slug, compliance.fn_qms_nivel(s.slug), s.vence
      from (select unnest(up.client_slugs) slug, null::date vence from public.user_products up
             where up.user_id = auth.uid() and up.product = 'eudr'
            union
            select a.client_slug, a.vence from compliance.qms_auditores a
             where a.user_id = auth.uid() and a.revocado_en is null and a.vence >= current_date) s
     where compliance.fn_qms_lee_registro(s.slug);
end;
$$;
insert into _h select 'con_migracion', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- Prueba del registro de miembros DESPUÉS de 20261023010000: solo directiva/calidad, VG y el auditor lo leen.
-- Es la prueba de la parte 1 con lo que cambia: captura y solo lectura ya no ven el registro ni «Mi grupo».
-- (Texto de la parte 1:) Prueba del registro interno de miembros y del auditor externo (QMS 4.1.2.2). Corre DESPUÉS de la migración, dentro de
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
  select count(*) into n from public.cert_qms_mis_grupos() where nivel = 'gestion';
  insert into _res values ('02b directiva ve su grupo en «Mi grupo» (' || n || '): ' || case when n = 1 then 'OK' else 'FALLA' end);
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
  begin perform public.cert_qms_miembros(slug); t := 'FALLA (vio el registro)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  select count(*) into n from public.cert_qms_mis_grupos();
  insert into _res values ('06b captura no ve el registro ni «Mi grupo» (' || n || '): ' || case when n = 0 then t else 'FALLA' end);

  -- 07 lector lee pero no escribe
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated', 'email', 'l-qms@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_miembros(slug); t := 'FALLA (vio el registro)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_cambiar_estado(m2, 'activo'); t := t || ' / FALLA (cambió estado)';
  exception when others then t := t || case when sqlstate = '42501' then '' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('07 lector no ve el registro ni cambia estados: ' || t);

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
-- Reversa de 20261023010000_cert_qms_registro_solo_gestion_y_auditor.sql: vuelve a las definiciones de la parte 1
-- (copiadas tal cual de 20261023000000) y quita fn_qms_lee_registro. Se prueba con la huella.
drop policy if exists qms_miembros_leer on compliance.qms_miembros;
create policy qms_miembros_leer on compliance.qms_miembros for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) is not null);

drop policy if exists qms_historial_leer on compliance.qms_miembros_historial;
create policy qms_historial_leer on compliance.qms_miembros_historial for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) is not null);

create or replace function public.cert_qms_mis_grupos()
returns table (client_slug text, nivel text, vence date)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  update compliance.qms_auditores a set user_id = auth.uid()
   where a.user_id is null and a.revocado_en is null and lower(a.correo) = lower(coalesce(auth.jwt()->>'email', ''))
     and coalesce(auth.jwt()->>'email', '') <> '';
  return query
    select s.slug, compliance.fn_qms_nivel(s.slug), s.vence
      from (select unnest(up.client_slugs) slug, null::date vence from public.user_products up
             where up.user_id = auth.uid() and up.product = 'eudr'
            union
            select a.client_slug, a.vence from compliance.qms_auditores a
             where a.user_id = auth.uid() and a.revocado_en is null and a.vence >= current_date) s
     where compliance.fn_qms_nivel(s.slug) is not null;
end;
$$;

create or replace function public.cert_qms_miembros(p_slug text)
returns setof compliance.qms_miembros language plpgsql stable security definer set search_path = '' as $$
begin
  if compliance.fn_qms_nivel(p_slug) is null then
    raise exception 'sin acceso al grupo %', coalesce(p_slug, '<null>') using errcode = '42501';
  end if;
  return query select * from compliance.qms_miembros m where m.client_slug = p_slug order by m.estado = 'excluido', m.nombre;
end;
$$;

create or replace function public.cert_qms_historial(p_miembro uuid)
returns setof compliance.qms_miembros_historial language plpgsql stable security definer set search_path = '' as $$
declare v_slug text;
begin
  select client_slug into v_slug from compliance.qms_miembros where id = p_miembro;
  if v_slug is null or compliance.fn_qms_nivel(v_slug) is null then
    raise exception 'sin acceso a ese socio' using errcode = '42501';
  end if;
  return query select * from compliance.qms_miembros_historial h where h.miembro_id = p_miembro order by h.en;
end;
$$;

drop function if exists compliance.fn_qms_lee_registro(text);
insert into _h select 'despues', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  select string_agg(t, ' || ' order by t) into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, left(a, 8), left(c, 8), left(d, 8),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
