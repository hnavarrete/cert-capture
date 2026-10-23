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
