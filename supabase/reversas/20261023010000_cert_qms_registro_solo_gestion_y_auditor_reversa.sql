-- Reversa de 20261023010000_cert_qms_registro_solo_gestion_y_auditor.sql: vuelve a las definiciones de la parte 1
-- (copiadas tal cual de 20261023000000) y quita fn_qms_lee_registro. Se prueba con la huella.
drop policy if exists qms_miembros_leer on compliance.qms_miembros;
create policy qms_miembros_leer on compliance.qms_miembros for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) is not null);

drop policy if exists qms_historial_leer on compliance.qms_miembros_historial;
create policy qms_historial_leer on compliance.qms_miembros_historial for select to authenticated
  using (compliance.fn_qms_nivel(client_slug) is not null);

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

drop function if exists compliance.fn_qms_lee_registro(text);
