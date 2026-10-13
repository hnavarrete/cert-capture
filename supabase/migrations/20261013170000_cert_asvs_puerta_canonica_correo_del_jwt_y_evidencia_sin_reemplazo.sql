-- VG Certificaciones · 13-oct-2026 · arreglos de base del ASVS L1 de hoy
--
-- (1) LA PUERTA CANÓNICA. cert_upsert_response, cert_mis_respuestas y cert_verificar_cadena comprobaban
--     user_products por su cuenta y no exigían lo que sí exige fn_user_has_product_access: permiso vigente
--     (tier activo o de prueba) y que el rol no sea de un aliado externo. Un permiso suspendido seguía leyendo y
--     escribiendo. Ahora pasan por fn_user_has_product_access, y para escribir además el rol no puede ser lector.
-- (2) LA ATRIBUCIÓN NO LA ESCRIBE EL CLIENTE. email_usuario sale del JWT, no del cuerpo (antes se podía firmar a
--     nombre de otra persona). estado solo admite «completado» o «borrador» (la app no lo envía: queda completado).
-- (3) LA EVIDENCIA NO SE SUSTITUYE. Las políticas de UPDATE y DELETE del depósito cert-evidencias usaban la misma
--     regla de lectura: cualquiera con acceso a la finca, lector incluido, podía reemplazar o borrar una evidencia
--     ya sellada (el sello cubre la ruta, no el contenido). Ahora solo VG (is_admin) reemplaza o borra; la app sube
--     sin reemplazo (upsert:false) y guarda la huella sha256 del archivo. Subir sigue igual, pero no el lector.

-- ───────── (1) y (2) ─────────
create or replace function public.cert_upsert_response(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_estado text := coalesce(p->>'estado', 'completado');
begin
  if not (
    public.is_admin(auth.uid())
    or (public.fn_user_has_product_access(auth.uid(), p->>'client_slug', 'eudr')
        and exists (select 1 from public.user_products up
                     where up.user_id = auth.uid() and up.product = 'eudr'
                       and (p->>'client_slug') = any(up.client_slugs)
                       and coalesce(up.role, 'tecnico') <> 'lector'
                       and (up.expires_at is null or up.expires_at > now())))
  ) then
    raise exception 'sin grant eudr de escritura para el client_slug %', coalesce(p->>'client_slug','<null>')
      using errcode = '42501';
  end if;
  if v_estado not in ('completado', 'borrador') then
    raise exception 'estado no admitido: %', v_estado using errcode = '22023';
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
    v_estado, coalesce(auth.jwt()->>'email', p->>'email_usuario'),
    coalesce((p->>'timestamp_creacion')::timestamptz, now()),
    nullif(p->>'audit_hash',''), nullif(p->>'prev_hash',''), auth.uid()
  )
  returning r.id into v_id;
  return v_id;
end;
$$;

create or replace function public.cert_mis_respuestas(p_client_slug text, p_form_key text default null)
returns table(id uuid, local_id uuid, client_slug text, form_key text, certificacion text, producer_id text, finca_id text,
              lote_id text, poligono_id text, data jsonb, fotos jsonb, estado text, timestamp_creacion timestamptz,
              created_at timestamptz, audit_chain_seq bigint, content_hash text, audit_hash text, prev_hash text,
              audit_timestamp_seal text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.is_admin(auth.uid()) or public.fn_user_has_product_access(auth.uid(), p_client_slug, 'eudr')) then
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
$$;

create or replace function public.cert_verificar_cadena(p_client_slug text, p_form_key text)
returns table(ok boolean, broken_at uuid, total bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.is_admin(auth.uid()) or public.fn_user_has_product_access(auth.uid(), p_client_slug, 'eudr')) then
    raise exception 'sin grant eudr para el client_slug %', coalesce(p_client_slug,'<null>') using errcode = '42501';
  end if;
  return query select * from compliance.verify_seal_chain(p_client_slug, p_form_key);
end;
$$;

-- compliance.verify_seal_chain es security definer y no comprueba acceso: solo se llega por cert_verificar_cadena.
revoke execute on function compliance.verify_seal_chain(text, text) from public, anon, authenticated;

-- ───────── (3) ─────────
drop policy if exists cert_evidencias_update on storage.objects;
drop policy if exists cert_evidencias_delete on storage.objects;
create policy cert_evidencias_update on storage.objects for update to authenticated
  using (bucket_id = 'cert-evidencias' and public.is_admin((select auth.uid())));
create policy cert_evidencias_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cert-evidencias' and public.is_admin((select auth.uid())));
drop policy if exists cert_evidencias_insert on storage.objects;
create policy cert_evidencias_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'cert-evidencias' and (public.is_admin((select auth.uid())) or (
              public.fn_user_has_product_access(auth.uid(), split_part(name, '/', 1), 'eudr')
              and exists (select 1 from public.user_products up
                           where up.user_id = auth.uid() and up.product = 'eudr'
                             and split_part(name, '/', 1) = any(up.client_slugs)
                             and coalesce(up.role, 'tecnico') <> 'lector'))));
