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
