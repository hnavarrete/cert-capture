-- VG Certificaciones · 23-oct-2026 · el registro interno de miembros lo leen SOLO la directiva o calidad, VG y el auditor.
-- La parte 1 (20261023000000) dejaba leer el registro a todo nivel con acceso al grupo, incluidos los socios y técnicos
-- (captura) y el rol de solo lectura: cada socio veía la cédula, el teléfono, el correo y la dirección de todos los demás.
-- Lo señaló la revisión automática de seguridad del commit 29909c5. El QMS no lo necesita: el registro es de la
-- directiva (4.1.2.2) y del auditor. Aquí se cierran las funciones, las políticas de lectura y la lista de grupos.

create or replace function compliance.fn_qms_lee_registro(p_slug text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(compliance.fn_qms_nivel(p_slug), '') in ('admin', 'gestion', 'auditor');
$$;
revoke all on function compliance.fn_qms_lee_registro(text) from public, anon;
grant execute on function compliance.fn_qms_lee_registro(text) to authenticated;   -- lo evalúan las políticas de RLS

drop policy if exists qms_miembros_leer on compliance.qms_miembros;
create policy qms_miembros_leer on compliance.qms_miembros for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug));
drop policy if exists qms_historial_leer on compliance.qms_miembros_historial;
create policy qms_historial_leer on compliance.qms_miembros_historial for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug));

create or replace function public.cert_qms_miembros(p_slug text)
returns setof compliance.qms_miembros language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'el registro de socios lo ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query select * from compliance.qms_miembros m where m.client_slug = p_slug order by m.estado = 'excluido', m.nombre;
end;
$$;

create or replace function public.cert_qms_historial(p_miembro uuid)
returns setof compliance.qms_miembros_historial language plpgsql stable security definer set search_path = '' as $$
declare v_slug text;
begin
  select client_slug into v_slug from compliance.qms_miembros where id = p_miembro;
  if v_slug is null or not compliance.fn_qms_lee_registro(v_slug) then
    raise exception 'sin acceso a ese socio' using errcode = '42501';
  end if;
  return query select * from compliance.qms_miembros_historial h where h.miembro_id = p_miembro order by h.en;
end;
$$;

-- «Mi grupo» aparece solo donde la cuenta lee el registro (la app muestra el botón según esta lista).
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
     where compliance.fn_qms_lee_registro(s.slug);
end;
$$;
