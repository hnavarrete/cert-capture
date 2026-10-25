-- Reversa de 20261025010000: vuelve a las definiciones de 20261025000000 (lo comprueba la ida y vuelta).
drop policy if exists qms_insp_leer on compliance.qms_inspecciones;
create policy qms_insp_leer on compliance.qms_inspecciones for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug) or inspector_id = auth.uid());

create or replace function public.cert_qms_informe(p_id uuid)
returns setof compliance.qms_inspecciones language plpgsql stable security definer set search_path = '' as $$
declare v_slug text; v_insp uuid;
begin
  select client_slug, inspector_id into v_slug, v_insp from compliance.qms_inspecciones where id = p_id;
  if v_slug is null or not (compliance.fn_qms_lee_registro(v_slug) or v_insp = auth.uid()) then
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
   where i.inspector_id is null and i.estado = 'planificada' and v_correo <> '' and lower(i.inspector_correo) = v_correo;
  return query
    select i.id, i.client_slug, i.checklist, i.fecha_plan, m.identificacion, m.nombre, m.direccion, m.productos, m.sitios
      from compliance.qms_inspecciones i join compliance.qms_miembros m on m.id = i.miembro_id
     where i.estado = 'planificada' and (i.inspector_id = auth.uid() or (v_correo <> '' and lower(i.inspector_correo) = v_correo))
       and coalesce(compliance.fn_qms_nivel(i.client_slug), '') in ('admin', 'gestion', 'captura')
     order by i.fecha_plan;
end;
$$;

drop function if exists compliance.fn_qms_es_inspector(text, uuid);
