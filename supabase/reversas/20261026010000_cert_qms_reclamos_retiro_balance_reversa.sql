-- Reversa de 20261026010000_cert_qms_reclamos_retiro_balance.sql (lo comprueba la ida y vuelta).
-- 🔴 Borra reclamos, retiros y balances: en producción, solo antes de que un grupo tenga registros reales.
drop function if exists public.cert_qms_reclamos(text);
drop function if exists public.cert_qms_reclamo_guardar(jsonb);
drop function if exists public.cert_qms_reclamo_aviso_cb(uuid, date);
drop function if exists public.cert_qms_reclamo_cerrar(uuid, text, text);
drop function if exists public.cert_qms_retiros(text);
drop function if exists public.cert_qms_retiro_guardar(jsonb);
drop function if exists public.cert_qms_retiro_cerrar(uuid, text);
drop function if exists public.cert_qms_balances(text);
drop function if exists public.cert_qms_balance_registrar(jsonb);
-- cert_qms_nc_guardar vuelve a la versión de 20261026000000 (copiada tal cual)
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
alter table compliance.qms_nc drop column if exists reclamo_id;
drop table if exists compliance.qms_balances;
drop table if exists compliance.qms_retiros;
drop table if exists compliance.qms_reclamos;
drop function if exists compliance._qms_3b_guardia();
