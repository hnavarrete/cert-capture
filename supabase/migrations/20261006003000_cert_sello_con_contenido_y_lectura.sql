-- Certificaciones · el sello del servidor cubre el CONTENIDO, lo sellado no se reescribe, y se puede leer lo propio
-- desde otro dispositivo. (#05, 6-oct-2026, orden de Henrry: «dale, no esperes a nadie»).
--
-- Lo que se midió antes (6-oct, 00:20):
--   · fn_seal_cert_response encadenaba prev_seal | audit_hash | created_at, pero public.cert_upsert_response NO
--     insertaba el audit_hash del cliente: el servidor sellaba un hash VACÍO. La cadena probaba orden y fecha, no
--     lo guardado.
--   · El upsert (on conflict local_id) podía reescribir data/fotos de una fila ya sellada sin volver a sellar.
--   · No había ninguna función de lectura: el esquema compliance no está expuesto en la API, así que lo guardado
--     no se podía retomar desde otro dispositivo.
--   · La tabla tiene 0 filas: no hay sellos viejos que migrar.
-- Partido de las definiciones VIVAS (pg_get_functiondef), no del SQL de referencia del repositorio.
-- Aplicada en dos pasos en la base: cert_sello_con_contenido_y_lectura y cert_upsert_rechaza_cambio_de_contenido.
-- Este archivo es el estado FINAL. Probado en transacción revertida: 11 de 11 (ver el commit).

-- 1 · El hash del contenido lo calcula el SERVIDOR (no se confía en el del cliente). jsonb::text es canónico.
alter table compliance.cert_responses add column if not exists content_hash text;

create or replace function compliance._contenido_cert(r compliance.cert_responses)
returns text language sql stable set search_path = '' as $$
  select encode(extensions.digest(jsonb_build_object(
    'local_id', r.local_id, 'client_slug', r.client_slug, 'form_key', r.form_key, 'certificacion', r.certificacion,
    'cultivo', r.cultivo, 'schema_version', r.schema_version, 'producer_id', r.producer_id, 'finca_id', r.finca_id,
    'lote_id', r.lote_id, 'poligono_id', r.poligono_id, 'crop_individual_id', r.crop_individual_id,
    'data', coalesce(r.data, '{}'::jsonb), 'fotos', coalesce(r.fotos, '[]'::jsonb),
    'geom', case when r.geom is null then null else public.st_asgeojson(r.geom)::jsonb end,
    'estado', r.estado, 'email_usuario', r.email_usuario, 'timestamp_creacion', r.timestamp_creacion
  )::text, 'sha256'), 'hex')
$$;
comment on function compliance._contenido_cert(compliance.cert_responses) is
  'Huella SHA-256 del contenido de una respuesta (datos, evidencias, ubicación, fecha). La usan el sello y la verificación.';

-- 2 · El sello encadena: sello anterior | contenido (servidor) | hash del cliente | fecha.
create or replace function compliance.fn_seal_cert_response()
returns trigger language plpgsql security definer set search_path = 'compliance', 'public', 'extensions' as $function$
declare
  v_prev_seal text; v_prev_hash text; v_seq bigint; v_scope text;
begin
  v_scope := coalesce(new.client_slug, new.tenant_id::text, 'global') || '|' || coalesce(new.form_key, '');
  select audit_chain_seq, audit_timestamp_seal, audit_hash into v_seq, v_prev_seal, v_prev_hash
  from compliance.cert_responses
  where coalesce(client_slug, tenant_id::text, 'global') || '|' || coalesce(form_key,'') = v_scope
    and audit_chain_seq is not null
  order by audit_chain_seq desc limit 1;

  new.audit_chain_seq := coalesce(v_seq, 0) + 1;
  if new.prev_hash is null then new.prev_hash := v_prev_hash; end if;
  new.created_at := coalesce(new.created_at, now());
  new.content_hash := compliance._contenido_cert(new);
  new.audit_timestamp_seal := encode(digest(
      coalesce(v_prev_seal,'') || '|' || new.content_hash || '|' || coalesce(new.audit_hash,'') || '|' || new.created_at::text,
      'sha256'), 'hex');
  new.audit_sealed := true;
  return new;
end;
$function$;

-- 3 · Lo sellado no se reescribe. Un reintento idéntico pasa (mismo contenido); otra versión va como fila nueva.
--     Siguen permitidos los campos que NO son contenido (deleted_at, auditoría externa, updated_at).
create or replace function compliance.fn_cert_inmutable()
returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  if old.audit_sealed is true then
    if compliance._contenido_cert(new) is distinct from old.content_hash
       or new.audit_timestamp_seal is distinct from old.audit_timestamp_seal
       or new.audit_chain_seq is distinct from old.audit_chain_seq
       or new.content_hash is distinct from old.content_hash
       or new.audit_hash is distinct from old.audit_hash then
      raise exception 'respuesta sellada (%): no se modifica; se guarda como una versión nueva', old.local_id
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;
drop trigger if exists trg_cert_inmutable on compliance.cert_responses;
create trigger trg_cert_inmutable before update on compliance.cert_responses
  for each row execute function compliance.fn_cert_inmutable();

-- 4 · La verificación recalcula el contenido: detecta también una fila alterada por fuera de los disparadores.
create or replace function compliance.verify_seal_chain(p_client_slug text, p_form_key text)
returns table(ok boolean, broken_at uuid, total bigint)
language plpgsql stable security definer set search_path = 'compliance', 'public', 'extensions' as $function$
declare
  r record; v_prev_seal text := ''; v_expected text; v_broken uuid := null; v_total bigint := 0;
begin
  for r in
    select c.*, compliance._contenido_cert(c) as recalculado
    from compliance.cert_responses c
    where c.client_slug = p_client_slug and c.form_key = p_form_key and c.audit_chain_seq is not null
    order by c.audit_chain_seq asc
  loop
    v_total := v_total + 1;
    v_expected := encode(digest(v_prev_seal || '|' || coalesce(r.recalculado,'') || '|' || coalesce(r.audit_hash,'') || '|' || r.created_at::text, 'sha256'), 'hex');
    if v_broken is null and (r.audit_timestamp_seal is distinct from v_expected or r.content_hash is distinct from r.recalculado) then
      v_broken := r.id;
    end if;
    v_prev_seal := r.audit_timestamp_seal;
  end loop;
  return query select (v_broken is null), v_broken, v_total;
end;
$function$;

-- 5 · Guardar: ahora también entran el audit_hash y el prev_hash del cliente (antes se descartaban).
create or replace function public.cert_upsert_response(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_id uuid;
begin
  if not (
    public.is_admin(auth.uid())
    or exists (
      select 1 from public.user_products up
      where up.user_id = auth.uid() and up.product = 'eudr'
        and (p->>'client_slug') = any(up.client_slugs)
        and coalesce(up.role, 'tecnico') <> 'lector'
        and (up.expires_at is null or up.expires_at > now())
    )
  ) then
    raise exception 'sin grant eudr de escritura para el client_slug %', coalesce(p->>'client_slug','<null>')
      using errcode = '42501';
  end if;

  -- Reenvío del mismo local_id: pasa solo si el contenido es IDÉNTICO (reintento de red). Si difiere, se rechaza
  -- con un mensaje claro: antes el «on conflict» lo ignoraba en silencio y la app creía que se había guardado.
  select c.id into v_id from compliance.cert_responses c where c.local_id = (p->>'local_id')::uuid;
  if v_id is not null then
    if not exists (select 1 from compliance.cert_responses c where c.id = v_id and c.client_slug is not distinct from p->>'client_slug') then
      raise exception 'local_id % ya existe bajo otro client_slug (no se permite sobrescribir)', p->>'local_id'
        using errcode = '42501';
    end if;
    if exists (select 1 from compliance.cert_responses c where c.id = v_id
                 and c.client_slug is not distinct from p->>'client_slug'
                 and c.form_key is not distinct from p->>'form_key'
                 and c.data = coalesce(p->'data','{}'::jsonb)
                 and c.fotos = coalesce(p->'fotos','[]'::jsonb)) then
      return v_id;
    end if;
    raise exception 'respuesta sellada (%): no se modifica; se guarda como una versión nueva', p->>'local_id'
      using errcode = '42501';
  end if;

  insert into compliance.cert_responses as r (
    local_id, client_slug, form_key, certificacion, cultivo, schema_version,
    producer_id, finca_id, lote_id, poligono_id, crop_individual_id,
    data, fotos, geom, estado, email_usuario, timestamp_creacion, audit_hash, prev_hash, created_by
  ) values (
    (p->>'local_id')::uuid, p->>'client_slug', p->>'form_key', p->>'certificacion',
    p->>'cultivo', coalesce((p->>'schema_version')::int, 1),
    p->>'producer_id', p->>'finca_id', p->>'lote_id', p->>'poligono_id',
    nullif(p->>'crop_individual_id','')::uuid,
    coalesce(p->'data','{}'::jsonb), coalesce(p->'fotos','[]'::jsonb),
    case when p->>'geom' is not null then public.st_geomfromgeojson(p->>'geom') else null end,
    coalesce(p->>'estado','completado'), p->>'email_usuario',
    coalesce((p->>'timestamp_creacion')::timestamptz, now()),
    nullif(p->>'audit_hash',''), nullif(p->>'prev_hash',''), auth.uid()
  )
  returning r.id into v_id;
  return v_id;
end;
$function$;

-- 6 · Leer lo propio (retomar desde otro dispositivo). Misma puerta que guardar, pero también puede leer «lector».
create or replace function public.cert_mis_respuestas(p_client_slug text, p_form_key text default null)
returns table(
  id uuid, local_id uuid, client_slug text, form_key text, certificacion text, producer_id text, finca_id text,
  lote_id text, poligono_id text, data jsonb, fotos jsonb, estado text, timestamp_creacion timestamptz,
  created_at timestamptz, audit_chain_seq bigint, content_hash text, audit_hash text, prev_hash text, audit_timestamp_seal text)
language plpgsql stable security definer set search_path = '' as $function$
begin
  if not (
    public.is_admin(auth.uid())
    or exists (
      select 1 from public.user_products up
      where up.user_id = auth.uid() and up.product = 'eudr' and p_client_slug = any(up.client_slugs)
        and (up.expires_at is null or up.expires_at > now())
    )
  ) then
    raise exception 'sin grant eudr para el client_slug %', coalesce(p_client_slug,'<null>') using errcode = '42501';
  end if;
  return query
    select c.id, c.local_id, c.client_slug, c.form_key, c.certificacion, c.producer_id, c.finca_id, c.lote_id,
           c.poligono_id, c.data, c.fotos, c.estado, c.timestamp_creacion, c.created_at, c.audit_chain_seq,
           c.content_hash, c.audit_hash, c.prev_hash, c.audit_timestamp_seal
    from compliance.cert_responses c
    where c.client_slug = p_client_slug and c.deleted_at is null
      and (p_form_key is null or c.form_key = p_form_key)
    order by c.form_key, c.audit_chain_seq;
end;
$function$;

-- 7 · Verificar la cadena desde la app, con la misma puerta de lectura.
create or replace function public.cert_verificar_cadena(p_client_slug text, p_form_key text)
returns table(ok boolean, broken_at uuid, total bigint)
language plpgsql stable security definer set search_path = '' as $function$
begin
  if not (
    public.is_admin(auth.uid())
    or exists (
      select 1 from public.user_products up
      where up.user_id = auth.uid() and up.product = 'eudr' and p_client_slug = any(up.client_slugs)
        and (up.expires_at is null or up.expires_at > now())
    )
  ) then
    raise exception 'sin grant eudr para el client_slug %', coalesce(p_client_slug,'<null>') using errcode = '42501';
  end if;
  return query select * from compliance.verify_seal_chain(p_client_slug, p_form_key);
end;
$function$;

revoke all on function public.cert_upsert_response(jsonb) from public, anon;
revoke all on function public.cert_mis_respuestas(text, text) from public, anon;
revoke all on function public.cert_verificar_cadena(text, text) from public, anon;
revoke all on function compliance._contenido_cert(compliance.cert_responses) from public, anon, authenticated;
grant execute on function public.cert_upsert_response(jsonb) to authenticated;
grant execute on function public.cert_mis_respuestas(text, text) to authenticated;
grant execute on function public.cert_verificar_cadena(text, text) to authenticated;
