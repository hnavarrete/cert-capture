-- IDA Y VUELTA de incumplimientos y sanciones (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- VG Certificaciones · 25/26-oct-2026 · GlobalG.A.P. opción 2 (QMS v6.0), parte 3a: INCUMPLIMIENTOS Y SANCIONES.
--   (1) INCUMPLIMIENTOS (QMS 05.03 a, b, c; 05.01 f): cada uno con su origen (auditoría interna, auditoría del organismo
--       certificador, reclamo o falla del QMS), su nivel (socio, QMS o centro de manipulación), la acción correctiva, el
--       RESPONSABLE (c) y el PLAZO (b). Se cierra con evidencia y quién verificó; cerrado, ya no cambia.
--       🔴 Los de la auditoría interna los crea la base sola, uno por cada «no cumple», en cuanto el informe se envía:
--       ninguno se queda sin seguimiento, venga el informe de donde venga.
--   (2) SANCIONES (05.03 d, e, f, g, h): advertencia, suspensión (del producto entero) y cancelación, decididas por el
--       QMS, con motivo y nombre. La suspensión pasa al socio a «suspendido» y la cancelación a «excluido» (el historial
--       de la parte 1 lo registra). Se anota cuándo se avisó al organismo certificador (f). Una suspensión solo se
--       levanta cuando su incumplimiento está cerrado (h).
-- Encargo v2 de #15 (cadena de la pitahaya). Toda tabla con RLS en esta misma migración; la app solo usa funciones.

-- ───────── (1) incumplimientos ─────────
create table if not exists compliance.qms_nc (
  id                uuid primary key default gen_random_uuid(),
  client_slug       text not null,
  miembro_id        uuid references compliance.qms_miembros(id) on delete restrict,   -- null = del grupo (QMS o centro)
  nivel             text not null default 'socio' check (nivel in ('socio', 'qms', 'phu')),
  origen            text not null check (origen in ('auditoria_interna', 'auditoria_externa', 'reclamo', 'qms')),
  inspeccion_id     uuid references compliance.qms_inspecciones(id) on delete restrict,
  code              text check (coalesce(length(code), 0) <= 40),                      -- punto de control, si lo hay
  gravedad          text check (gravedad in ('Major', 'Minor', 'Recommendation')),
  descripcion       text not null check (length(btrim(descripcion)) between 3 and 1000),
  accion_correctiva text check (coalesce(length(accion_correctiva), 0) <= 1000),
  responsable       text check (coalesce(length(responsable), 0) <= 200),
  plazo             date not null,
  estado            text not null default 'abierta' check (estado in ('abierta', 'en_curso', 'cerrada')),
  cierre_evidencia  text check (coalesce(length(cierre_evidencia), 0) <= 1000),
  cerrada_por       uuid,
  cerrada_por_correo text,
  cerrada_por_nombre text check (coalesce(length(cerrada_por_nombre), 0) <= 200),
  cerrada_en        timestamptz,
  creada_por        uuid default auth.uid(),
  creada_en         timestamptz not null default now(),
  actualizada_en    timestamptz not null default now(),
  constraint qms_nc_socio_con_socio check (nivel <> 'socio' or miembro_id is not null),
  constraint qms_nc_interna_con_informe check (origen <> 'auditoria_interna' or inspeccion_id is not null),
  constraint qms_nc_cerrada_completa check (estado <> 'cerrada' or (cerrada_en is not null and coalesce(btrim(cierre_evidencia), '') <> ''
    and coalesce(btrim(cerrada_por_nombre), '') <> '' and coalesce(btrim(accion_correctiva), '') <> '' and coalesce(btrim(responsable), '') <> ''))
);
create index if not exists qms_nc_slug_estado on compliance.qms_nc (client_slug, estado, plazo);
create index if not exists qms_nc_miembro on compliance.qms_nc (miembro_id);
create unique index if not exists qms_nc_una_por_punto on compliance.qms_nc (inspeccion_id, code) where inspeccion_id is not null;

-- Cerrada no cambia; el grupo, el socio, el origen y el informe no cambian nunca; no se borra.
create or replace function compliance._qms_nc_guardia()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'QMS: un incumplimiento no se borra; se cierra con evidencia' using errcode = '42501'; end if;
  if old.estado = 'cerrada' then raise exception 'QMS: este incumplimiento ya está cerrado' using errcode = '42501'; end if;
  if (new.client_slug, new.miembro_id, new.nivel, new.origen, new.inspeccion_id, new.code, new.gravedad, new.creada_en)
     is distinct from (old.client_slug, old.miembro_id, old.nivel, old.origen, old.inspeccion_id, old.code, old.gravedad, old.creada_en) then
    raise exception 'QMS: el origen y el socio de un incumplimiento no cambian' using errcode = '23514';
  end if;
  if old.origen = 'auditoria_interna' and new.descripcion is distinct from old.descripcion then
    raise exception 'QMS: lo que encontró la auditoría interna no se reescribe (05.02 f)' using errcode = '42501';
  end if;
  new.actualizada_en := now();
  return new;
end;
$$;
drop trigger if exists trg_qms_nc_guardia on compliance.qms_nc;
create trigger trg_qms_nc_guardia before update or delete on compliance.qms_nc
  for each row execute function compliance._qms_nc_guardia();

-- Al enviarse un informe de auditoría interna: un incumplimiento por cada «no cumple», con su plazo y su comentario.
create or replace function compliance._qms_nc_desde_informe()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'enviada' and old.estado = 'planificada' then
    insert into compliance.qms_nc (client_slug, miembro_id, nivel, origen, inspeccion_id, code, gravedad, descripcion, plazo, creada_por)
    select new.client_slug, new.miembro_id, 'socio', 'auditoria_interna', new.id, e->>'code', p.nivel,
           coalesce(nullif(btrim(e->>'comentario'), ''), 'No cumple ' || (e->>'code')),
           coalesce(nullif(e->>'plazo', '')::date, (new.inicio at time zone 'America/Guayaquil')::date + 28), new.enviada_por
      from jsonb_array_elements(new.resultados) e
      join compliance.qms_checklist_puntos p on p.checklist = new.checklist and p.code = e->>'code'
     where e->>'resultado' = 'no_cumple'
    on conflict (inspeccion_id, code) where inspeccion_id is not null do nothing;
  end if;
  return null;
end;
$$;
drop trigger if exists trg_qms_nc_desde_informe on compliance.qms_inspecciones;
create trigger trg_qms_nc_desde_informe after update on compliance.qms_inspecciones
  for each row execute function compliance._qms_nc_desde_informe();

-- ───────── (2) sanciones ─────────
create table if not exists compliance.qms_sanciones (
  id                  uuid primary key default gen_random_uuid(),
  client_slug         text not null,
  miembro_id          uuid not null references compliance.qms_miembros(id) on delete restrict,
  nc_id               uuid references compliance.qms_nc(id) on delete restrict,
  tipo                text not null check (tipo in ('advertencia', 'suspension', 'cancelacion')),
  producto            text check (coalesce(length(producto), 0) <= 120),   -- 05.03 e: el producto ENTERO
  motivo              text not null check (length(btrim(motivo)) between 3 and 1000),
  decidida_por        uuid default auth.uid(),
  decidida_por_correo text,
  decidida_por_nombre text not null check (length(btrim(decidida_por_nombre)) between 2 and 200),
  decidida_en         timestamptz not null default now(),
  aviso_cb_en         date,                                                 -- 05.03 f
  levantada_en        timestamptz,
  levantada_motivo    text check (coalesce(length(levantada_motivo), 0) <= 1000),
  levantada_por_nombre text check (coalesce(length(levantada_por_nombre), 0) <= 200),
  constraint qms_sancion_levantar_solo_suspension check (levantada_en is null or tipo = 'suspension')
);
create index if not exists qms_sanciones_slug on compliance.qms_sanciones (client_slug, decidida_en desc);

-- Una sanción no se edita ni se borra: solo se le anota el aviso al certificador (una vez) y, si es suspensión, se levanta (una vez).
create or replace function compliance._qms_sancion_guardia()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'QMS: una sanción no se borra (05.03 g)' using errcode = '42501'; end if;
  if (new.client_slug, new.miembro_id, new.nc_id, new.tipo, new.producto, new.motivo, new.decidida_por, new.decidida_por_nombre, new.decidida_en)
     is distinct from (old.client_slug, old.miembro_id, old.nc_id, old.tipo, old.producto, old.motivo, old.decidida_por, old.decidida_por_nombre, old.decidida_en)
     or (old.aviso_cb_en is not null and new.aviso_cb_en is distinct from old.aviso_cb_en)
     or (old.levantada_en is not null and (new.levantada_en, new.levantada_motivo, new.levantada_por_nombre)
         is distinct from (old.levantada_en, old.levantada_motivo, old.levantada_por_nombre)) then
    raise exception 'QMS: una sanción no se edita; solo se anota el aviso al certificador y, si es suspensión, se levanta' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_qms_sancion_guardia on compliance.qms_sanciones;
create trigger trg_qms_sancion_guardia before update or delete on compliance.qms_sanciones
  for each row execute function compliance._qms_sancion_guardia();

-- ───────── RLS (además de las funciones) ─────────
alter table compliance.qms_nc        enable row level security;
alter table compliance.qms_sanciones enable row level security;
drop policy if exists qms_nc_leer on compliance.qms_nc;
create policy qms_nc_leer on compliance.qms_nc for select to authenticated using (compliance.fn_qms_lee_registro(client_slug));
drop policy if exists qms_sanciones_leer on compliance.qms_sanciones;
create policy qms_sanciones_leer on compliance.qms_sanciones for select to authenticated using (compliance.fn_qms_lee_registro(client_slug));
revoke all on compliance.qms_nc, compliance.qms_sanciones from public, anon, authenticated;

-- ───────── funciones que llama la app ─────────
create or replace function compliance._qms_gestiona(p_slug text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(compliance.fn_qms_nivel(p_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo hace esto' using errcode = '42501';
  end if;
end;
$$;

-- Incumplimientos del grupo: la directiva o calidad, VG y el auditor externo.
create or replace function public.cert_qms_nc_lista(p_slug text)
returns table (id uuid, miembro_id uuid, socio_nombre text, nivel text, origen text, inspeccion_id uuid, code text, gravedad text,
               descripcion text, accion_correctiva text, responsable text, plazo date, estado text, cierre_evidencia text,
               cerrada_por_nombre text, cerrada_en timestamptz, creada_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'los incumplimientos los ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query
    select n.id, n.miembro_id, m.nombre, n.nivel, n.origen, n.inspeccion_id, n.code, n.gravedad, n.descripcion, n.accion_correctiva,
           n.responsable, n.plazo, n.estado, n.cierre_evidencia, n.cerrada_por_nombre, n.cerrada_en, n.creada_en
      from compliance.qms_nc n left join compliance.qms_miembros m on m.id = n.miembro_id
     where n.client_slug = p_slug
     order by n.estado = 'cerrada', n.plazo, n.creada_en;
end;
$$;

-- Alta (de origen externo, reclamo o del QMS) o edición de uno abierto: acción correctiva, responsable, plazo, estado en curso.
-- p: {id?, client_slug, miembro_id?, nivel, origen, descripcion, accion_correctiva, responsable, plazo, en_curso}
create or replace function public.cert_qms_nc_guardar(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_slug text := p->>'client_slug'; v_plazo date; v_m uuid := nullif(p->>'miembro_id', '')::uuid;
begin
  if v_id is not null then select client_slug into v_slug from compliance.qms_nc where id = v_id; end if;
  perform compliance._qms_gestiona(v_slug);
  begin v_plazo := (p->>'plazo')::date; exception when others then v_plazo := null; end;
  if v_plazo is null then raise exception 'el incumplimiento necesita un plazo para la acción correctiva (05.03 b)' using errcode = '22023'; end if;
  if v_id is null then
    if coalesce(p->>'origen', '') = 'auditoria_interna' then
      raise exception 'los de la auditoría interna los crea el informe, no se cargan a mano' using errcode = '22023';
    end if;
    if v_m is not null and not exists (select 1 from compliance.qms_miembros where id = v_m and client_slug = v_slug) then
      raise exception 'ese socio no es de este grupo' using errcode = '42501';
    end if;
    insert into compliance.qms_nc (client_slug, miembro_id, nivel, origen, descripcion, accion_correctiva, responsable, plazo, estado)
    values (v_slug, v_m, coalesce(nullif(p->>'nivel', ''), case when v_m is null then 'qms' else 'socio' end), p->>'origen',
            btrim(coalesce(p->>'descripcion', '')), nullif(btrim(p->>'accion_correctiva'), ''), nullif(btrim(p->>'responsable'), ''), v_plazo,
            case when coalesce((p->>'en_curso')::boolean, false) then 'en_curso' else 'abierta' end)
    returning id into v_id;
  else
    update compliance.qms_nc set
      descripcion = case when origen = 'auditoria_interna' then descripcion else coalesce(nullif(btrim(p->>'descripcion'), ''), descripcion) end,
      accion_correctiva = nullif(btrim(p->>'accion_correctiva'), ''), responsable = nullif(btrim(p->>'responsable'), ''), plazo = v_plazo,
      estado = case when coalesce((p->>'en_curso')::boolean, false) then 'en_curso' else estado end
     where id = v_id;
  end if;
  return v_id;
end;
$$;

-- Cierre con evidencia y nombre de quien verificó (05.01 f, 05.03 g). Exige acción correctiva y responsable.
create or replace function public.cert_qms_nc_cerrar(p_id uuid, p_evidencia text, p_nombre text)
returns void language plpgsql security definer set search_path = '' as $$
declare v compliance.qms_nc%rowtype;
begin
  select * into v from compliance.qms_nc where id = p_id;
  if v.id is null then raise exception 'ese incumplimiento no existe' using errcode = '42501'; end if;
  perform compliance._qms_gestiona(v.client_slug);
  if coalesce(btrim(v.accion_correctiva), '') = '' or coalesce(btrim(v.responsable), '') = '' then
    raise exception 'antes de cerrar, anote la acción correctiva y su responsable (05.03 c)' using errcode = '22023';
  end if;
  if coalesce(btrim(p_evidencia), '') = '' or coalesce(btrim(p_nombre), '') = '' then
    raise exception 'cerrar exige la evidencia y el nombre de quien verificó' using errcode = '22023';
  end if;
  update compliance.qms_nc set estado = 'cerrada', cierre_evidencia = btrim(p_evidencia), cerrada_por = auth.uid(),
    cerrada_por_correo = lower(coalesce(auth.jwt()->>'email', '')), cerrada_por_nombre = btrim(p_nombre), cerrada_en = now()
   where id = p_id;
end;
$$;

create or replace function public.cert_qms_sanciones(p_slug text)
returns table (id uuid, miembro_id uuid, socio_nombre text, nc_id uuid, nc_descripcion text, nc_estado text, tipo text, producto text,
               motivo text, decidida_por_nombre text, decidida_en timestamptz, aviso_cb_en date, levantada_en timestamptz,
               levantada_motivo text, levantada_por_nombre text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'las sanciones las ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query
    select s.id, s.miembro_id, m.nombre, s.nc_id, n.descripcion, n.estado, s.tipo, s.producto, s.motivo, s.decidida_por_nombre,
           s.decidida_en, s.aviso_cb_en, s.levantada_en, s.levantada_motivo, s.levantada_por_nombre
      from compliance.qms_sanciones s join compliance.qms_miembros m on m.id = s.miembro_id
      left join compliance.qms_nc n on n.id = s.nc_id
     where s.client_slug = p_slug
     order by s.decidida_en desc;
end;
$$;

-- Sancionar (05.03 d). Suspensión → socio «suspendido»; cancelación → «excluido» (queda en su historial con el motivo).
create or replace function public.cert_qms_sancionar(p_slug text, p_miembro uuid, p_tipo text, p_motivo text, p_nombre text,
                                                     p_nc uuid default null, p_producto text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_estado text;
begin
  perform compliance._qms_gestiona(p_slug);
  select estado into v_estado from compliance.qms_miembros where id = p_miembro and client_slug = p_slug;
  if v_estado is null then raise exception 'ese socio no es de este grupo' using errcode = '42501'; end if;
  if v_estado = 'excluido' then raise exception 'ese socio ya está excluido' using errcode = '22023'; end if;
  if p_tipo = 'suspension' and v_estado = 'suspendido' then raise exception 'ese socio ya está suspendido' using errcode = '22023'; end if;
  if p_nc is not null and not exists (select 1 from compliance.qms_nc where id = p_nc and client_slug = p_slug and miembro_id = p_miembro) then
    raise exception 'ese incumplimiento no es de este socio' using errcode = '22023';
  end if;
  insert into compliance.qms_sanciones (client_slug, miembro_id, nc_id, tipo, producto, motivo, decidida_por_correo, decidida_por_nombre)
  values (p_slug, p_miembro, p_nc, p_tipo, nullif(btrim(p_producto), ''), btrim(coalesce(p_motivo, '')),
          lower(coalesce(auth.jwt()->>'email', '')), btrim(coalesce(p_nombre, '')))
  returning id into v_id;
  if p_tipo in ('suspension', 'cancelacion') then
    update compliance.qms_miembros set estado = case p_tipo when 'suspension' then 'suspendido' else 'excluido' end,
      estado_motivo = btrim(p_motivo) where id = p_miembro;
  end if;
  return v_id;
end;
$$;

create or replace function public.cert_qms_sancion_aviso_cb(p_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = '' as $$
declare v_slug text;
begin
  select client_slug into v_slug from compliance.qms_sanciones where id = p_id;
  if v_slug is null then raise exception 'esa sanción no existe' using errcode = '42501'; end if;
  perform compliance._qms_gestiona(v_slug);
  if p_fecha is null or p_fecha > current_date then raise exception 'la fecha del aviso no puede estar en el futuro' using errcode = '22023'; end if;
  update compliance.qms_sanciones set aviso_cb_en = p_fecha where id = p_id;
end;
$$;

-- Levantar una suspensión (05.03 h): solo si su incumplimiento está cerrado. El socio vuelve a «activo».
create or replace function public.cert_qms_sancion_levantar(p_id uuid, p_motivo text, p_nombre text)
returns void language plpgsql security definer set search_path = '' as $$
declare v compliance.qms_sanciones%rowtype;
begin
  select * into v from compliance.qms_sanciones where id = p_id;
  if v.id is null then raise exception 'esa sanción no existe' using errcode = '42501'; end if;
  perform compliance._qms_gestiona(v.client_slug);
  if v.tipo <> 'suspension' then raise exception 'solo se levanta una suspensión' using errcode = '22023'; end if;
  if v.levantada_en is not null then raise exception 'esta suspensión ya se levantó' using errcode = '22023'; end if;
  if v.nc_id is not null and (select estado from compliance.qms_nc where id = v.nc_id) <> 'cerrada' then
    raise exception 'la suspensión se levanta cuando su incumplimiento está cerrado (05.03 h)' using errcode = '22023';
  end if;
  if coalesce(btrim(p_motivo), '') = '' or coalesce(btrim(p_nombre), '') = '' then
    raise exception 'levantar exige el motivo y el nombre de quien decide' using errcode = '22023';
  end if;
  update compliance.qms_sanciones set levantada_en = now(), levantada_motivo = btrim(p_motivo), levantada_por_nombre = btrim(p_nombre)
   where id = p_id;
  update compliance.qms_miembros set estado = 'activo', estado_motivo = btrim(p_motivo)
   where id = v.miembro_id and estado = 'suspendido';
end;
$$;

-- ───────── permisos de ejecución ─────────
do $$ declare f text; begin
  foreach f in array array[
    'public.cert_qms_nc_lista(text)', 'public.cert_qms_nc_guardar(jsonb)', 'public.cert_qms_nc_cerrar(uuid, text, text)',
    'public.cert_qms_sanciones(text)', 'public.cert_qms_sancionar(text, uuid, text, text, text, uuid, text)',
    'public.cert_qms_sancion_aviso_cb(uuid, date)', 'public.cert_qms_sancion_levantar(uuid, text, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['compliance._qms_nc_guardia()', 'compliance._qms_nc_desde_informe()', 'compliance._qms_sancion_guardia()',
                           'compliance._qms_gestiona(text)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
insert into _h select 'con_migracion', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
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
-- Reversa de 20261026000000_cert_qms_incumplimientos_y_sanciones.sql (lo comprueba la ida y vuelta).
-- 🔴 Borra incumplimientos y sanciones: en producción, solo antes de que un grupo tenga registros reales.
drop function if exists public.cert_qms_nc_lista(text);
drop function if exists public.cert_qms_nc_guardar(jsonb);
drop function if exists public.cert_qms_nc_cerrar(uuid, text, text);
drop function if exists public.cert_qms_sanciones(text);
drop function if exists public.cert_qms_sancionar(text, uuid, text, text, text, uuid, text);
drop function if exists public.cert_qms_sancion_aviso_cb(uuid, date);
drop function if exists public.cert_qms_sancion_levantar(uuid, text, text);
drop trigger if exists trg_qms_nc_desde_informe on compliance.qms_inspecciones;
drop table if exists compliance.qms_sanciones;
drop table if exists compliance.qms_nc;
drop function if exists compliance._qms_nc_guardia();
drop function if exists compliance._qms_nc_desde_informe();
drop function if exists compliance._qms_sancion_guardia();
drop function if exists compliance._qms_gestiona(text);
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
