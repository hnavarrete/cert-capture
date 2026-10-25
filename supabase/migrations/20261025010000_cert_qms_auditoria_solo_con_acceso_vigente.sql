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
