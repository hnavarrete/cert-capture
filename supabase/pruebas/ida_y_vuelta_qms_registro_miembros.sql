-- IDA Y VUELTA del registro de miembros del QMS (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- VG Certificaciones · 23-oct-2026 · GlobalG.A.P. opción 2 (gestión de grupo), parte 1:
--   (1) REGISTRO INTERNO DE MIEMBROS (QMS v6.0 4.1.2.2): socio, contacto, cédula/RUC, productos con su área, sitios
--       certificados y no, certificador, estado interno y fecha de la última auditoría interna.
--   (2) PRODUCTORES EXCLUIDOS (4.1.2.2 b): un socio no se borra; se excluye con motivo, y cada cambio de estado queda
--       en un historial que no se edita.
--   (3) AUDITOR EXTERNO EN SOLO LECTURA: el rol `auditor` de la Capa 0 nunca lleva client_slugs (fn_roles_alianza_guard)
--       y fn_user_has_product_access lo excluye a propósito. Su acceso a un grupo va en compliance.qms_auditores, que
--       solo leen estas funciones, y vence (máximo un año, como el rol).
-- Encargo v2 de #15 (cadena de la pitahaya), aprobado por Henrry el 22-oct. Toda tabla con RLS en esta misma migración.
-- La app NO toca las tablas: todo pasa por las funciones de `public` de abajo, que comprueban el permiso.

-- ───────── (3) auditor externo del grupo ─────────
create table if not exists compliance.qms_auditores (
  id           uuid primary key default gen_random_uuid(),
  client_slug  text not null,
  correo       text not null check (correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(correo) <= 200),
  user_id      uuid references auth.users(id) on delete set null,
  organismo    text check (coalesce(length(organismo), 0) <= 160),   -- organismo certificador
  vence        date not null,
  otorgado_por uuid default auth.uid(),
  otorgado_en  timestamptz not null default now(),
  revocado_en  timestamptz,
  constraint qms_auditores_vence_max_un_anio check (vence <= (otorgado_en at time zone 'America/Guayaquil')::date + 366)
);
create unique index if not exists qms_auditores_vigente_unico on compliance.qms_auditores (client_slug, lower(correo)) where revocado_en is null;

-- ───────── quién es quién en un grupo ─────────
-- Nivel del usuario actual en el grupo (client_slug): admin (VG) · gestion · captura · lectura · auditor · null.
-- Gestión = la directiva y el responsable de calidad del grupo (los roles «gerente» y dueño de la Capa 0).
create or replace function compliance.fn_qms_nivel(p_slug text)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() is null or coalesce(p_slug, '') = '' then null
    when public.is_admin(auth.uid()) then 'admin'
    when public.fn_user_has_product_access(auth.uid(), p_slug, 'eudr') then
      (select case
                when bool_or(up.role in ('god','producer_admin','gerente_general','gerente_agricola','gerente_sostenibilidad',
                                         'gerente_hacienda','manager')) then 'gestion'
                when bool_or(coalesce(up.role, 'tecnico') <> 'lector') then 'captura'
                else 'lectura' end
         from public.user_products up
        where up.user_id = auth.uid() and up.product = 'eudr' and p_slug = any(up.client_slugs)
          and up.tier in ('active', 'preview') and (up.expires_at is null or up.expires_at > now()))
    when exists (select 1 from public.user_products up
                  where up.user_id = auth.uid() and up.product = 'eudr' and up.role = 'auditor'
                    and up.tier in ('active', 'preview') and up.expires_at > now())
     and exists (select 1 from compliance.qms_auditores a
                  where a.client_slug = p_slug and a.revocado_en is null and a.vence >= current_date
                    and (a.user_id = auth.uid() or lower(a.correo) = lower(coalesce(auth.jwt()->>'email', ''))))
      then 'auditor'
    else null end;
$$;

-- ───────── (1) registro interno de miembros ─────────
create table if not exists compliance.qms_miembros (
  id               uuid primary key default gen_random_uuid(),
  client_slug      text not null,
  identificacion   text not null check (identificacion ~ '^[0-9]{10}([0-9]{3})?$'),
  producer_id      uuid references public.producer_canonical(id) on delete set null,  -- lo enlaza VG; nunca el cliente
  nombre           text not null check (length(btrim(nombre)) between 2 and 200),
  telefono         text check (coalesce(length(telefono), 0) <= 40),
  correo           text check (coalesce(length(correo), 0) <= 200),
  direccion        text check (coalesce(length(direccion), 0) <= 300),
  -- productos: [{"cultivo": "pitahaya amarilla", "area_ha": 2.1}] · sitios: [{"nombre": "...", "area_ha": 2.1, "certificado": true}]
  productos        jsonb not null default '[]' check (jsonb_typeof(productos) = 'array' and jsonb_array_length(productos) <= 50),
  sitios           jsonb not null default '[]' check (jsonb_typeof(sitios) = 'array' and jsonb_array_length(sitios) <= 50),
  certificador     text check (coalesce(length(certificador), 0) <= 120),
  ggn              text check (ggn is null or ggn ~ '^[0-9]{13}$'),
  estado           text not null default 'aspirante' check (estado in ('aspirante', 'activo', 'suspendido', 'excluido')),
  fecha_ingreso    date,
  contrato_fecha   date,                                                                 -- 4.1.1.1
  contrato_ref     text check (coalesce(length(contrato_ref), 0) <= 200),
  ultima_auditoria_interna date,
  estado_motivo    text check (coalesce(length(estado_motivo), 0) <= 500),
  excluido_en      timestamptz,
  creado_por       uuid default auth.uid(),
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  unique (client_slug, identificacion),
  constraint qms_miembros_excluido_con_motivo check (estado <> 'excluido' or (excluido_en is not null and coalesce(btrim(estado_motivo), '') <> ''))
);
create index if not exists qms_miembros_slug_estado on compliance.qms_miembros (client_slug, estado);

-- ───────── (2) historial de estados: solo se agrega ─────────
create table if not exists compliance.qms_miembros_historial (
  id          bigint generated always as identity primary key,
  miembro_id  uuid not null references compliance.qms_miembros(id) on delete cascade,
  client_slug text not null,
  de          text,
  a           text not null,
  motivo      text,
  por         uuid,
  por_correo  text,
  en          timestamptz not null default now()
);
create index if not exists qms_hist_miembro on compliance.qms_miembros_historial (miembro_id, en);

create or replace function compliance._qms_miembros_guardia()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.client_slug is distinct from old.client_slug or new.identificacion is distinct from old.identificacion then
      raise exception 'QMS: el grupo y la cédula de un socio no cambian; se registra otro socio' using errcode = '23514';
    end if;
    if new.producer_id is distinct from old.producer_id and not public.is_admin(auth.uid()) then
      raise exception 'QMS: el enlace con el padrón de la Capa 0 lo hace VG' using errcode = '42501';
    end if;
  elsif new.producer_id is not null and not public.is_admin(auth.uid()) then
    raise exception 'QMS: el enlace con el padrón de la Capa 0 lo hace VG' using errcode = '42501';
  end if;
  if new.estado = 'excluido' and (tg_op = 'INSERT' or old.estado <> 'excluido') then new.excluido_en := now(); end if;
  if new.estado <> 'excluido' then new.excluido_en := null; end if;
  new.actualizado_en := now();
  return new;
end;
$$;
drop trigger if exists trg_qms_miembros_guardia on compliance.qms_miembros;
create trigger trg_qms_miembros_guardia before insert or update on compliance.qms_miembros
  for each row execute function compliance._qms_miembros_guardia();

-- El historial va en AFTER: en BEFORE la fila del socio todavía no existe y la llave foránea del historial falla.
create or replace function compliance._qms_miembros_historial_alta()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.estado is distinct from old.estado then
    insert into compliance.qms_miembros_historial (miembro_id, client_slug, de, a, motivo, por, por_correo)
    values (new.id, new.client_slug, case when tg_op = 'UPDATE' then old.estado end, new.estado, new.estado_motivo,
            auth.uid(), auth.jwt()->>'email');
  end if;
  return null;
end;
$$;
drop trigger if exists trg_qms_miembros_historial on compliance.qms_miembros;
create trigger trg_qms_miembros_historial after insert or update on compliance.qms_miembros
  for each row execute function compliance._qms_miembros_historial_alta();

create or replace function compliance._qms_historial_inmutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'QMS: el historial de estados no se edita ni se borra' using errcode = '42501';
end;
$$;
drop trigger if exists trg_qms_historial_inmutable on compliance.qms_miembros_historial;
create trigger trg_qms_historial_inmutable before update or delete on compliance.qms_miembros_historial
  for each row execute function compliance._qms_historial_inmutable();

-- ───────── RLS (además de las funciones: si algún día se expone el esquema, las reglas ya están) ─────────
alter table compliance.qms_miembros           enable row level security;
alter table compliance.qms_miembros_historial enable row level security;
alter table compliance.qms_auditores          enable row level security;

drop policy if exists qms_miembros_leer on compliance.qms_miembros;
create policy qms_miembros_leer on compliance.qms_miembros for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) is not null);
drop policy if exists qms_miembros_escribir on compliance.qms_miembros;
create policy qms_miembros_escribir on compliance.qms_miembros for insert to authenticated
  with check (compliance.fn_qms_nivel(client_slug) in ('admin', 'gestion'));
drop policy if exists qms_miembros_editar on compliance.qms_miembros;
create policy qms_miembros_editar on compliance.qms_miembros for update to authenticated
  using (compliance.fn_qms_nivel(client_slug) in ('admin', 'gestion'))
  with check (compliance.fn_qms_nivel(client_slug) in ('admin', 'gestion'));
-- Sin política de DELETE: un socio no se borra, se excluye (4.1.2.2 b).

drop policy if exists qms_historial_leer on compliance.qms_miembros_historial;
create policy qms_historial_leer on compliance.qms_miembros_historial for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) is not null);

drop policy if exists qms_auditores_leer on compliance.qms_auditores;
create policy qms_auditores_leer on compliance.qms_auditores for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) in ('admin', 'gestion') or user_id = auth.uid());
drop policy if exists qms_auditores_escribir on compliance.qms_auditores;
create policy qms_auditores_escribir on compliance.qms_auditores for all to authenticated
  using (compliance.fn_qms_nivel(client_slug) in ('admin', 'gestion'))
  with check (compliance.fn_qms_nivel(client_slug) in ('admin', 'gestion'));

revoke all on compliance.qms_miembros, compliance.qms_miembros_historial, compliance.qms_auditores from public, anon, authenticated;

-- ───────── funciones que llama la app ─────────
-- Grupos donde el usuario actual entra al QMS. Al auditor le devuelve los que le autorizaron (su user_products no
-- lleva client_slugs); a los demás, los de su permiso eudr. De paso enlaza el user_id del auditor por su correo.
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

-- Alta o edición de un socio. p: {id?, client_slug, identificacion, nombre, telefono, correo, direccion, productos, sitios,
-- certificador, ggn, fecha_ingreso, contrato_fecha, contrato_ref, ultima_auditoria_interna}. El estado NO se cambia aquí.
create or replace function public.cert_qms_guardar_miembro(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_slug text := p->>'client_slug';
begin
  if v_id is not null then select client_slug into v_slug from compliance.qms_miembros where id = v_id; end if;
  if coalesce(compliance.fn_qms_nivel(v_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo registra socios' using errcode = '42501';
  end if;
  if v_id is null then
    insert into compliance.qms_miembros (client_slug, identificacion, nombre, telefono, correo, direccion, productos, sitios,
      certificador, ggn, fecha_ingreso, contrato_fecha, contrato_ref, ultima_auditoria_interna)
    values (v_slug, btrim(p->>'identificacion'), btrim(p->>'nombre'), nullif(btrim(p->>'telefono'), ''), nullif(btrim(p->>'correo'), ''),
      nullif(btrim(p->>'direccion'), ''), coalesce(p->'productos', '[]'), coalesce(p->'sitios', '[]'),
      nullif(btrim(p->>'certificador'), ''), nullif(btrim(p->>'ggn'), ''), nullif(p->>'fecha_ingreso', '')::date,
      nullif(p->>'contrato_fecha', '')::date, nullif(btrim(p->>'contrato_ref'), ''), nullif(p->>'ultima_auditoria_interna', '')::date)
    returning id into v_id;
  else
    update compliance.qms_miembros m set
      nombre = btrim(p->>'nombre'), telefono = nullif(btrim(p->>'telefono'), ''), correo = nullif(btrim(p->>'correo'), ''),
      direccion = nullif(btrim(p->>'direccion'), ''), productos = coalesce(p->'productos', '[]'), sitios = coalesce(p->'sitios', '[]'),
      certificador = nullif(btrim(p->>'certificador'), ''), ggn = nullif(btrim(p->>'ggn'), ''),
      fecha_ingreso = nullif(p->>'fecha_ingreso', '')::date, contrato_fecha = nullif(p->>'contrato_fecha', '')::date,
      contrato_ref = nullif(btrim(p->>'contrato_ref'), ''), ultima_auditoria_interna = nullif(p->>'ultima_auditoria_interna', '')::date
     where m.id = v_id;
  end if;
  return v_id;
end;
$$;

-- Cambio de estado (activar, suspender, excluir, readmitir). Excluir y suspender exigen motivo.
create or replace function public.cert_qms_cambiar_estado(p_miembro uuid, p_estado text, p_motivo text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_slug text;
begin
  select client_slug into v_slug from compliance.qms_miembros where id = p_miembro;
  if v_slug is null or coalesce(compliance.fn_qms_nivel(v_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo cambia el estado de un socio' using errcode = '42501';
  end if;
  if p_estado in ('suspendido', 'excluido') and coalesce(btrim(p_motivo), '') = '' then
    raise exception 'suspender o excluir a un socio exige el motivo' using errcode = '22023';
  end if;
  update compliance.qms_miembros set estado = p_estado, estado_motivo = nullif(btrim(p_motivo), '') where id = p_miembro;
end;
$$;

-- Autorizar a un auditor externo (por correo), con vencimiento. VG le da después el rol `auditor` en la Capa 0.
create or replace function public.cert_qms_autorizar_auditor(p_slug text, p_correo text, p_organismo text, p_vence date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if coalesce(compliance.fn_qms_nivel(p_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo autoriza auditores' using errcode = '42501';
  end if;
  if p_vence is null or p_vence < current_date then
    raise exception 'el permiso del auditor necesita una fecha de vencimiento futura' using errcode = '22023';
  end if;
  insert into compliance.qms_auditores (client_slug, correo, organismo, vence)
  values (p_slug, lower(btrim(p_correo)), nullif(btrim(p_organismo), ''), p_vence) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.cert_qms_revocar_auditor(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_slug text;
begin
  select client_slug into v_slug from compliance.qms_auditores where id = p_id and revocado_en is null;
  if v_slug is null or coalesce(compliance.fn_qms_nivel(v_slug), '') not in ('admin', 'gestion') then
    raise exception 'sin permiso para revocar ese auditor' using errcode = '42501';
  end if;
  update compliance.qms_auditores set revocado_en = now() where id = p_id;
end;
$$;

create or replace function public.cert_qms_auditores(p_slug text)
returns setof compliance.qms_auditores language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(compliance.fn_qms_nivel(p_slug), '') not in ('admin', 'gestion') then
    raise exception 'sin acceso a los auditores del grupo' using errcode = '42501';
  end if;
  return query select * from compliance.qms_auditores a where a.client_slug = p_slug order by a.revocado_en nulls first, a.vence desc;
end;
$$;

-- ───────── permisos de ejecución ─────────
do $$ declare f text; begin
  foreach f in array array[
    'public.cert_qms_mis_grupos()', 'public.cert_qms_miembros(text)', 'public.cert_qms_historial(uuid)',
    'public.cert_qms_guardar_miembro(jsonb)', 'public.cert_qms_cambiar_estado(uuid, text, text)',
    'public.cert_qms_autorizar_auditor(text, text, text, date)', 'public.cert_qms_revocar_auditor(uuid)',
    'public.cert_qms_auditores(text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['compliance.fn_qms_nivel(text)', 'compliance._qms_miembros_guardia()',
                           'compliance._qms_miembros_historial_alta()', 'compliance._qms_historial_inmutable()']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
-- Las políticas de RLS llaman a compliance.fn_qms_nivel: el rol que evalúa la política necesita EXECUTE. Solo
-- authenticated lo recibe (anon no tiene ninguna política ni permiso sobre estas tablas).
grant execute on function compliance.fn_qms_nivel(text) to authenticated;
insert into _h select 'con_migracion', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
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
-- Reversa de 20261023000000_cert_qms_registro_miembros_y_auditor.sql: deja la base como estaba (se prueba con la huella).
drop function if exists public.cert_qms_mis_grupos();
drop function if exists public.cert_qms_miembros(text);
drop function if exists public.cert_qms_historial(uuid);
drop function if exists public.cert_qms_guardar_miembro(jsonb);
drop function if exists public.cert_qms_cambiar_estado(uuid, text, text);
drop function if exists public.cert_qms_autorizar_auditor(text, text, text, date);
drop function if exists public.cert_qms_revocar_auditor(uuid);
drop function if exists public.cert_qms_auditores(text);
drop table if exists compliance.qms_miembros_historial;
drop table if exists compliance.qms_auditores;
drop table if exists compliance.qms_miembros;
drop function if exists compliance._qms_miembros_guardia();
drop function if exists compliance._qms_miembros_historial_alta();
drop function if exists compliance._qms_historial_inmutable();
drop function if exists compliance.fn_qms_nivel(text);
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
