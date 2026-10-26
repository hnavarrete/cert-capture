-- VG Certificaciones · 26-oct-2026 · GlobalG.A.P. opción 2 (QMS), parte 3c: el AUDITOR EXTERNO ve las evidencias de la IFA.
-- Punto 4 de la demo del encargo v2 de #15. Hasta hoy, `cert_mis_respuestas` y la lectura del depósito `cert-evidencias`
-- exigían acceso de producto al grupo, que el rol `auditor` de la Capa 0 nunca tiene (no lleva client_slugs). El auditor
-- veía el registro, las auditorías internas y los incumplimientos, pero no lo que cada finca respondió de la IFA.
--   · public.cert_qms_evidencias_ifa(slug): las respuestas de GlobalG.A.P. del grupo, en solo lectura, para quien lee el
--     registro (directiva o calidad, VG y el auditor autorizado). SOLO certificacion = 'GLOBAL_GAP': un auditor de
--     GlobalG.A.P. no ve lo que el grupo captura para EUDR u otras normas. Sin el correo de quien capturó.
--   · Lectura de las fotos y documentos de esas mismas respuestas en `cert-evidencias` (la ruta es
--     <grupo>/<local_id de la respuesta>/...): una política nueva, solo de lectura, que comprueba que el archivo
--     pertenece a una respuesta de GlobalG.A.P. viva del grupo que el auditor tiene autorizado.
-- No toca `cert_mis_respuestas` ni las políticas existentes: el resto de los roles sigue igual.

-- 🔴 En `public`, no en `compliance`: la política del depósito la evalúa el rol de la app, que no tiene acceso al esquema
-- compliance. Con la función allí, TODA lectura de fotos del depósito habría fallado con «permission denied for schema
-- compliance», para todos los usuarios (lo atrapó la prueba de ida y vuelta, 26-oct). Mismo patrón que is_admin y
-- fn_user_has_product_access, que ya usan las otras políticas del depósito.
create or replace function public.fn_qms_auditor_ve_evidencia(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(compliance.fn_qms_nivel(split_part(p_name, '/', 1)), '') = 'auditor'
     and exists (select 1 from compliance.cert_responses c
                  where c.client_slug = split_part(p_name, '/', 1)
                    and c.local_id::text = split_part(p_name, '/', 2)
                    and c.certificacion = 'GLOBAL_GAP' and c.deleted_at is null);
$$;
revoke all on function public.fn_qms_auditor_ve_evidencia(text) from public, anon;
grant execute on function public.fn_qms_auditor_ve_evidencia(text) to authenticated;   -- la evalúa la política del depósito

drop policy if exists cert_evidencias_select_auditor_qms on storage.objects;
create policy cert_evidencias_select_auditor_qms on storage.objects for select to authenticated
  using (bucket_id = 'cert-evidencias' and public.fn_qms_auditor_ve_evidencia(name));

create or replace function public.cert_qms_evidencias_ifa(p_slug text)
returns table (id uuid, local_id uuid, form_key text, producer_id text, finca_id text, lote_id text, data jsonb, fotos jsonb,
               estado text, created_at timestamptz, audit_chain_seq bigint, audit_hash text, audit_timestamp_seal text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'las evidencias de la IFA las ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query
    select c.id, c.local_id, c.form_key, c.producer_id, c.finca_id, c.lote_id, c.data, c.fotos, c.estado, c.created_at,
           c.audit_chain_seq, c.audit_hash, c.audit_timestamp_seal
      from compliance.cert_responses c
     where c.client_slug = p_slug and c.certificacion = 'GLOBAL_GAP' and c.deleted_at is null
     order by c.finca_id nulls last, c.form_key, c.audit_chain_seq;
end;
$$;
revoke all on function public.cert_qms_evidencias_ifa(text) from public, anon;
grant execute on function public.cert_qms_evidencias_ifa(text) to authenticated, service_role;
