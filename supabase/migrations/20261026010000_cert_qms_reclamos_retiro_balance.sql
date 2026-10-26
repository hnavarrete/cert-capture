-- VG Certificaciones · 26-oct-2026 · GlobalG.A.P. opción 2 (QMS v6.0), parte 3b: RECLAMOS, RETIRO Y BALANCE DE MASAS.
--   (1) RECLAMOS (QMS 04 a, b, d, e): se reciben, se registran, se investigan, se sigue y se cierran; contra el grupo o
--       contra un socio. Los de inocuidad, trabajadores o ambiente exigen anotar el aviso al organismo certificador (e)
--       antes de cerrarse. Un reclamo puede abrir un incumplimiento (qms_nc.reclamo_id, origen «reclamo»).
--   (2) RETIRO DE PRODUCTO (QMS 07 a, b, d): real o SIMULACRO, con el evento que lo origina, quién decidió, a quién se
--       avisó (clientes y, si es real, el organismo certificador) y la CONCILIACIÓN de cantidades (afectada vs localizada).
--       07 d: un ejercicio al año; uno real en los últimos 12 meses cuenta como prueba.
--   (3) BALANCE DE MASAS (QMS 06 b, k): uno al año por producto registrado, certificado y no certificado por separado,
--       con su fuente (VG Custody). Registrado, no cambia.
-- Encargo v2 de #15 (cadena de la pitahaya). Toda tabla con RLS en esta misma migración; la app solo usa funciones.

-- ───────── (1) reclamos ─────────
create table if not exists compliance.qms_reclamos (
  id                 uuid primary key default gen_random_uuid(),
  client_slug        text not null,
  recibido_en        date not null,
  origen             text not null check (origen in ('cliente', 'autoridad', 'socio', 'otro')),
  miembro_id         uuid references compliance.qms_miembros(id) on delete restrict,   -- null = contra el grupo
  tema               text not null check (tema in ('inocuidad', 'trabajadores', 'ambiente', 'calidad', 'otro')),
  descripcion        text not null check (length(btrim(descripcion)) between 3 and 2000),
  investigacion      text check (coalesce(length(investigacion), 0) <= 2000),
  seguimiento        text check (coalesce(length(seguimiento), 0) <= 2000),
  estado             text not null default 'recibido' check (estado in ('recibido', 'en_investigacion', 'cerrado')),
  aviso_cb_en        date,
  conclusion         text check (coalesce(length(conclusion), 0) <= 2000),
  cerrado_por_nombre text check (coalesce(length(cerrado_por_nombre), 0) <= 200),
  cerrado_en         timestamptz,
  creado_por         uuid default auth.uid(),
  creado_en          timestamptz not null default now(),
  constraint qms_reclamo_cerrado_completo check (estado <> 'cerrado' or (cerrado_en is not null and coalesce(btrim(conclusion), '') <> ''
    and coalesce(btrim(investigacion), '') <> '' and coalesce(btrim(cerrado_por_nombre), '') <> ''
    and (tema not in ('inocuidad', 'trabajadores', 'ambiente') or aviso_cb_en is not null)))
);
create index if not exists qms_reclamos_slug on compliance.qms_reclamos (client_slug, estado, recibido_en desc);

alter table compliance.qms_nc add column if not exists reclamo_id uuid references compliance.qms_reclamos(id) on delete restrict;

-- ───────── (2) retiro de producto ─────────
create table if not exists compliance.qms_retiros (
  id                  uuid primary key default gen_random_uuid(),
  client_slug         text not null,
  tipo                text not null check (tipo in ('simulacro', 'real')),
  iniciado_en         timestamptz not null,
  terminado_en        timestamptz,
  producto            text not null check (length(btrim(producto)) between 2 and 120),
  lotes               text check (coalesce(length(lotes), 0) <= 2000),        -- códigos de lote (VG Custody)
  motivo              text not null check (length(btrim(motivo)) between 3 and 1000),   -- el evento que lo origina (07 b)
  decide_nombre       text not null check (length(btrim(decide_nombre)) between 2 and 200),
  clientes_avisados   text check (coalesce(length(clientes_avisados), 0) <= 1000),
  aviso_cb_en         date,
  unidad              text check (unidad in ('kg', 'gavetas', 'cajas', 'unidades')),
  cantidad_afectada   numeric check (cantidad_afectada is null or cantidad_afectada > 0),
  cantidad_localizada numeric check (cantidad_localizada is null or cantidad_localizada >= 0),
  resultado           text check (coalesce(length(resultado), 0) <= 2000),
  estado              text not null default 'en_curso' check (estado in ('en_curso', 'cerrado')),
  cerrado_por_nombre  text check (coalesce(length(cerrado_por_nombre), 0) <= 200),
  creado_por          uuid default auth.uid(),
  creado_en           timestamptz not null default now(),
  constraint qms_retiro_cerrado_completo check (estado <> 'cerrado' or (terminado_en is not null and terminado_en > iniciado_en
    and unidad is not null and cantidad_afectada is not null and cantidad_localizada is not null
    and coalesce(btrim(resultado), '') <> '' and coalesce(btrim(cerrado_por_nombre), '') <> ''
    and coalesce(btrim(clientes_avisados), '') <> '' and (tipo <> 'real' or aviso_cb_en is not null)))
);
create index if not exists qms_retiros_slug on compliance.qms_retiros (client_slug, iniciado_en desc);

-- ───────── (3) balance de masas ─────────
create table if not exists compliance.qms_balances (
  id                   uuid primary key default gen_random_uuid(),
  client_slug          text not null,
  producto             text not null check (length(btrim(producto)) between 2 and 120),
  desde                date not null,
  hasta                date not null,
  unidad               text not null check (unidad in ('kg', 'gavetas', 'cajas', 'unidades')),
  entradas_cert        numeric not null check (entradas_cert >= 0),
  entradas_no_cert     numeric not null default 0 check (entradas_no_cert >= 0),
  salidas_cert         numeric not null check (salidas_cert >= 0),
  salidas_no_cert      numeric not null default 0 check (salidas_no_cert >= 0),
  existencias_cert     numeric not null default 0 check (existencias_cert >= 0),
  existencias_no_cert  numeric not null default 0 check (existencias_no_cert >= 0),
  conclusion           text not null check (length(btrim(conclusion)) between 3 and 2000),
  fuente               text check (coalesce(length(fuente), 0) <= 300),
  hecho_por_nombre     text not null check (length(btrim(hecho_por_nombre)) between 2 and 200),
  hecho_por            uuid default auth.uid(),
  hecho_en             timestamptz not null default now(),
  constraint qms_balance_periodo check (hasta >= desde and hasta - desde <= 400)
);
create index if not exists qms_balances_slug on compliance.qms_balances (client_slug, producto, hasta desc);

-- ───────── guardias: lo cerrado no cambia; nada se borra ─────────
-- Una sola función para las tres tablas: compara por NOMBRE de campo (to_jsonb), porque new.recibido_en no existe en un
-- retiro y PL/pgSQL fallaría al evaluarlo.
create or replace function compliance._qms_3b_guardia()
returns trigger language plpgsql set search_path = '' as $$
declare k text; inm text[];
begin
  if tg_op = 'DELETE' then raise exception 'QMS: este registro no se borra' using errcode = '42501'; end if;
  if tg_table_name = 'qms_balances' then raise exception 'QMS: un balance de masas registrado no se edita; se registra otro' using errcode = '42501'; end if;
  if (to_jsonb(old)->>'estado') = 'cerrado' then raise exception 'QMS: este registro ya está cerrado' using errcode = '42501'; end if;
  inm := case tg_table_name
           when 'qms_reclamos' then array['client_slug', 'recibido_en', 'origen', 'miembro_id', 'tema', 'descripcion', 'creado_en', 'creado_por']
           else array['client_slug', 'tipo', 'iniciado_en', 'creado_en', 'creado_por'] end;
  foreach k in array inm loop
    if (to_jsonb(new)->k) is distinct from (to_jsonb(old)->k) then
      raise exception 'QMS: «%» no cambia en este registro', k using errcode = '42501';
    end if;
  end loop;
  return new;
end;
$$;
drop trigger if exists trg_qms_reclamos_guardia on compliance.qms_reclamos;
create trigger trg_qms_reclamos_guardia before update or delete on compliance.qms_reclamos for each row execute function compliance._qms_3b_guardia();
drop trigger if exists trg_qms_retiros_guardia on compliance.qms_retiros;
create trigger trg_qms_retiros_guardia before update or delete on compliance.qms_retiros for each row execute function compliance._qms_3b_guardia();
drop trigger if exists trg_qms_balances_guardia on compliance.qms_balances;
create trigger trg_qms_balances_guardia before update or delete on compliance.qms_balances for each row execute function compliance._qms_3b_guardia();

-- ───────── RLS (además de las funciones) ─────────
alter table compliance.qms_reclamos enable row level security;
alter table compliance.qms_retiros  enable row level security;
alter table compliance.qms_balances enable row level security;
drop policy if exists qms_reclamos_leer on compliance.qms_reclamos;
create policy qms_reclamos_leer on compliance.qms_reclamos for select to authenticated using (compliance.fn_qms_lee_registro(client_slug));
drop policy if exists qms_retiros_leer on compliance.qms_retiros;
create policy qms_retiros_leer on compliance.qms_retiros for select to authenticated using (compliance.fn_qms_lee_registro(client_slug));
drop policy if exists qms_balances_leer on compliance.qms_balances;
create policy qms_balances_leer on compliance.qms_balances for select to authenticated using (compliance.fn_qms_lee_registro(client_slug));
revoke all on compliance.qms_reclamos, compliance.qms_retiros, compliance.qms_balances from public, anon, authenticated;

-- ───────── funciones que llama la app ─────────
create or replace function public.cert_qms_reclamos(p_slug text)
returns table (id uuid, recibido_en date, origen text, miembro_id uuid, socio_nombre text, tema text, descripcion text, investigacion text,
               seguimiento text, estado text, aviso_cb_en date, requiere_aviso boolean, conclusion text, cerrado_por_nombre text,
               cerrado_en timestamptz, nc_abiertas int)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'los reclamos los ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query
    select r.id, r.recibido_en, r.origen, r.miembro_id, m.nombre, r.tema, r.descripcion, r.investigacion, r.seguimiento, r.estado,
           r.aviso_cb_en, r.tema in ('inocuidad', 'trabajadores', 'ambiente'), r.conclusion, r.cerrado_por_nombre, r.cerrado_en,
           (select count(*)::int from compliance.qms_nc n where n.reclamo_id = r.id and n.estado <> 'cerrada')
      from compliance.qms_reclamos r left join compliance.qms_miembros m on m.id = r.miembro_id
     where r.client_slug = p_slug
     order by r.estado = 'cerrado', r.recibido_en desc;
end;
$$;

-- Alta o seguimiento de uno abierto. p: {id?, client_slug, recibido_en, origen, miembro_id?, tema, descripcion, investigacion, seguimiento}
create or replace function public.cert_qms_reclamo_guardar(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_slug text := p->>'client_slug'; v_m uuid := nullif(p->>'miembro_id', '')::uuid; v_f date;
begin
  if v_id is not null then select client_slug into v_slug from compliance.qms_reclamos where id = v_id; end if;
  perform compliance._qms_gestiona(v_slug);
  if v_id is null then
    begin v_f := (p->>'recibido_en')::date; exception when others then v_f := null; end;
    if v_f is null or v_f > current_date then raise exception 'el reclamo necesita la fecha en que se recibió (no futura)' using errcode = '22023'; end if;
    if v_m is not null and not exists (select 1 from compliance.qms_miembros where id = v_m and client_slug = v_slug) then
      raise exception 'ese socio no es de este grupo' using errcode = '42501';
    end if;
    insert into compliance.qms_reclamos (client_slug, recibido_en, origen, miembro_id, tema, descripcion, investigacion, seguimiento, estado)
    values (v_slug, v_f, p->>'origen', v_m, p->>'tema', btrim(coalesce(p->>'descripcion', '')), nullif(btrim(p->>'investigacion'), ''),
            nullif(btrim(p->>'seguimiento'), ''), case when coalesce(btrim(p->>'investigacion'), '') <> '' then 'en_investigacion' else 'recibido' end)
    returning id into v_id;
  else
    update compliance.qms_reclamos set investigacion = nullif(btrim(p->>'investigacion'), ''), seguimiento = nullif(btrim(p->>'seguimiento'), ''),
      estado = case when coalesce(btrim(p->>'investigacion'), '') <> '' then 'en_investigacion' else 'recibido' end
     where id = v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.cert_qms_reclamo_aviso_cb(p_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = '' as $$
declare v_slug text; v_aviso date;
begin
  select client_slug, aviso_cb_en into v_slug, v_aviso from compliance.qms_reclamos where id = p_id;
  if v_slug is null then raise exception 'ese reclamo no existe' using errcode = '42501'; end if;
  perform compliance._qms_gestiona(v_slug);
  if v_aviso is not null then raise exception 'el aviso de este reclamo ya está anotado' using errcode = '22023'; end if;
  if p_fecha is null or p_fecha > current_date then raise exception 'la fecha del aviso no puede estar en el futuro' using errcode = '22023'; end if;
  update compliance.qms_reclamos set aviso_cb_en = p_fecha where id = p_id;
end;
$$;

-- Cierre: con investigación, conclusión y nombre; los de inocuidad, trabajadores o ambiente, con el aviso al certificador (04 e).
create or replace function public.cert_qms_reclamo_cerrar(p_id uuid, p_conclusion text, p_nombre text)
returns void language plpgsql security definer set search_path = '' as $$
declare v compliance.qms_reclamos%rowtype;
begin
  select * into v from compliance.qms_reclamos where id = p_id;
  if v.id is null then raise exception 'ese reclamo no existe' using errcode = '42501'; end if;
  perform compliance._qms_gestiona(v.client_slug);
  if coalesce(btrim(v.investigacion), '') = '' then raise exception 'antes de cerrar, anote la investigación (QMS 04 b)' using errcode = '22023'; end if;
  if v.tema in ('inocuidad', 'trabajadores', 'ambiente') and v.aviso_cb_en is null then
    raise exception 'un reclamo de inocuidad, trabajadores o ambiente se cierra con el aviso al organismo certificador (QMS 04 e)' using errcode = '22023';
  end if;
  if coalesce(btrim(p_conclusion), '') = '' or coalesce(btrim(p_nombre), '') = '' then
    raise exception 'cerrar exige la conclusión y el nombre de quien cierra' using errcode = '22023';
  end if;
  update compliance.qms_reclamos set estado = 'cerrado', conclusion = btrim(p_conclusion), cerrado_por_nombre = btrim(p_nombre), cerrado_en = now()
   where id = p_id;
end;
$$;

-- Incumplimientos: la parte 3a más el enlace con el reclamo que lo originó (p.reclamo_id, del mismo grupo).
create or replace function public.cert_qms_nc_guardar(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_slug text := p->>'client_slug'; v_plazo date; v_m uuid := nullif(p->>'miembro_id', '')::uuid;
        v_rec uuid := nullif(p->>'reclamo_id', '')::uuid;
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
    if v_rec is not null and not exists (select 1 from compliance.qms_reclamos where id = v_rec and client_slug = v_slug) then
      raise exception 'ese reclamo no es de este grupo' using errcode = '42501';
    end if;
    insert into compliance.qms_nc (client_slug, miembro_id, nivel, origen, descripcion, accion_correctiva, responsable, plazo, estado, reclamo_id)
    values (v_slug, v_m, coalesce(nullif(p->>'nivel', ''), case when v_m is null then 'qms' else 'socio' end),
            case when v_rec is not null then 'reclamo' else p->>'origen' end,
            btrim(coalesce(p->>'descripcion', '')), nullif(btrim(p->>'accion_correctiva'), ''), nullif(btrim(p->>'responsable'), ''), v_plazo,
            case when coalesce((p->>'en_curso')::boolean, false) then 'en_curso' else 'abierta' end, v_rec)
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

create or replace function public.cert_qms_retiros(p_slug text)
returns setof compliance.qms_retiros language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'los retiros los ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query select * from compliance.qms_retiros r where r.client_slug = p_slug order by r.estado = 'cerrado', r.iniciado_en desc;
end;
$$;

-- Alta o avance de un retiro en curso. p: {id?, client_slug, tipo, iniciado_en, producto, lotes, motivo, decide_nombre,
-- clientes_avisados, aviso_cb_en, unidad, cantidad_afectada, cantidad_localizada, resultado}
create or replace function public.cert_qms_retiro_guardar(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p->>'id', '')::uuid; v_slug text := p->>'client_slug'; v_ini timestamptz; v_aviso date;
begin
  if v_id is not null then select client_slug into v_slug from compliance.qms_retiros where id = v_id; end if;
  perform compliance._qms_gestiona(v_slug);
  begin v_aviso := nullif(p->>'aviso_cb_en', '')::date; exception when others then v_aviso := null; end;
  if v_aviso > current_date then raise exception 'la fecha del aviso no puede estar en el futuro' using errcode = '22023'; end if;
  if v_id is null then
    begin v_ini := (p->>'iniciado_en')::timestamptz; exception when others then v_ini := null; end;
    if v_ini is null or v_ini > now() + interval '15 minutes' then raise exception 'el retiro necesita su fecha y hora de inicio (no futura)' using errcode = '22023'; end if;
    insert into compliance.qms_retiros (client_slug, tipo, iniciado_en, producto, lotes, motivo, decide_nombre, clientes_avisados, aviso_cb_en,
                                        unidad, cantidad_afectada, cantidad_localizada, resultado)
    values (v_slug, p->>'tipo', v_ini, btrim(coalesce(p->>'producto', '')), nullif(btrim(p->>'lotes'), ''), btrim(coalesce(p->>'motivo', '')),
            btrim(coalesce(p->>'decide_nombre', '')), nullif(btrim(p->>'clientes_avisados'), ''), v_aviso, nullif(p->>'unidad', ''),
            nullif(p->>'cantidad_afectada', '')::numeric, nullif(p->>'cantidad_localizada', '')::numeric, nullif(btrim(p->>'resultado'), ''))
    returning id into v_id;
  else
    update compliance.qms_retiros set lotes = nullif(btrim(p->>'lotes'), ''), clientes_avisados = nullif(btrim(p->>'clientes_avisados'), ''),
      aviso_cb_en = coalesce(aviso_cb_en, v_aviso), unidad = nullif(p->>'unidad', ''),
      cantidad_afectada = nullif(p->>'cantidad_afectada', '')::numeric, cantidad_localizada = nullif(p->>'cantidad_localizada', '')::numeric,
      resultado = nullif(btrim(p->>'resultado'), ''), producto = coalesce(nullif(btrim(p->>'producto'), ''), producto),
      motivo = coalesce(nullif(btrim(p->>'motivo'), ''), motivo)
     where id = v_id;
  end if;
  return v_id;
end;
$$;

-- Cierre: hora de fin, conciliación (cantidad afectada y localizada), clientes avisados, resultado y, si es real, el aviso al certificador.
create or replace function public.cert_qms_retiro_cerrar(p_id uuid, p_nombre text)
returns void language plpgsql security definer set search_path = '' as $$
declare v compliance.qms_retiros%rowtype;
begin
  select * into v from compliance.qms_retiros where id = p_id;
  if v.id is null then raise exception 'ese retiro no existe' using errcode = '42501'; end if;
  perform compliance._qms_gestiona(v.client_slug);
  if v.unidad is null or v.cantidad_afectada is null or v.cantidad_localizada is null then
    raise exception 'antes de cerrar, anote la conciliación: cantidad afectada y cantidad localizada (QMS 07 b)' using errcode = '22023';
  end if;
  if coalesce(btrim(v.clientes_avisados), '') = '' then raise exception 'antes de cerrar, anote a qué clientes se avisó (QMS 07 b)' using errcode = '22023'; end if;
  if v.tipo = 'real' and v.aviso_cb_en is null then raise exception 'un retiro real se cierra con el aviso al organismo certificador (QMS 07 b)' using errcode = '22023'; end if;
  if coalesce(btrim(v.resultado), '') = '' or coalesce(btrim(p_nombre), '') = '' then
    raise exception 'cerrar exige el resultado y el nombre de quien cierra' using errcode = '22023';
  end if;
  update compliance.qms_retiros set estado = 'cerrado', terminado_en = greatest(now(), iniciado_en + interval '1 minute'), cerrado_por_nombre = btrim(p_nombre)
   where id = p_id;
end;
$$;

create or replace function public.cert_qms_balances(p_slug text)
returns setof compliance.qms_balances language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'los balances los ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query select * from compliance.qms_balances b where b.client_slug = p_slug order by b.producto, b.hasta desc;
end;
$$;

create or replace function public.cert_qms_balance_registrar(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_slug text := p->>'client_slug'; v_d date; v_h date;
begin
  perform compliance._qms_gestiona(v_slug);
  begin v_d := (p->>'desde')::date; v_h := (p->>'hasta')::date; exception when others then v_d := null; end;
  if v_d is null or v_h is null or v_h < v_d or v_h > current_date then
    raise exception 'el balance necesita un periodo válido que ya terminó' using errcode = '22023';
  end if;
  insert into compliance.qms_balances (client_slug, producto, desde, hasta, unidad, entradas_cert, entradas_no_cert, salidas_cert, salidas_no_cert,
                                       existencias_cert, existencias_no_cert, conclusion, fuente, hecho_por_nombre)
  values (v_slug, btrim(coalesce(p->>'producto', '')), v_d, v_h, p->>'unidad', (p->>'entradas_cert')::numeric, coalesce(nullif(p->>'entradas_no_cert', '')::numeric, 0),
          (p->>'salidas_cert')::numeric, coalesce(nullif(p->>'salidas_no_cert', '')::numeric, 0), coalesce(nullif(p->>'existencias_cert', '')::numeric, 0),
          coalesce(nullif(p->>'existencias_no_cert', '')::numeric, 0), btrim(coalesce(p->>'conclusion', '')), nullif(btrim(p->>'fuente'), ''),
          btrim(coalesce(p->>'hecho_por_nombre', '')))
  returning id into v_id;
  return v_id;
end;
$$;

-- ───────── permisos de ejecución ─────────
do $$ declare f text; begin
  foreach f in array array[
    'public.cert_qms_reclamos(text)', 'public.cert_qms_reclamo_guardar(jsonb)', 'public.cert_qms_reclamo_aviso_cb(uuid, date)',
    'public.cert_qms_reclamo_cerrar(uuid, text, text)', 'public.cert_qms_nc_guardar(jsonb)', 'public.cert_qms_retiros(text)',
    'public.cert_qms_retiro_guardar(jsonb)', 'public.cert_qms_retiro_cerrar(uuid, text)', 'public.cert_qms_balances(text)',
    'public.cert_qms_balance_registrar(jsonb)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  execute 'revoke all on function compliance._qms_3b_guardia() from public, anon, authenticated';
end $$;
