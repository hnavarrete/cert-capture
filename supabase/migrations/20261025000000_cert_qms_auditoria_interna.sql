-- VG Certificaciones · 25-oct-2026 · GlobalG.A.P. opción 2 (gestión de grupo), parte 2: AUDITORÍA INTERNA DE FINCA.
--   (1) CRONOGRAMA (QMS 05.02 a, j): la directiva o calidad planifica la auditoría interna de cada socio, con fecha y
--       auditor interno asignado por el QMS (05.02 d). Un socio tiene a lo sumo una auditoría abierta.
--   (2) INFORME (05.02 g): el auditor interno lo llena EN LA FINCA, SIN SEÑAL, y lo envía al volver la señal. El
--       servidor recalcula el cumplimiento con SU copia de los puntos y niveles oficiales: nunca confía en el equipo.
--         i socio y sitios · ii firma del socio · iii fecha · iv nombre y firma del auditor · v productos registrados ·
--         vi resultado de CADA punto · vii comentarios (Major siempre; Minor si no cumple o no aplica) ·
--         viii incumplimientos con plazo de la acción correctiva · ix cálculo del cumplimiento · x hora de inicio y fin ·
--         xi nombre de quien aprobó.
--   (3) DECISIÓN (05.02 h, i; 12.5 a): la directiva o calidad decide si el socio cumple. Quien hizo la auditoría no la
--       aprueba. «Conforme» solo si el cálculo cumple: Major 100 % y Minor ≥ 95 %.
--   El informe enviado no se edita ni se borra (05.02 f: los originales se conservan para el organismo certificador).
-- Encargo v2 de #15 (cadena de la pitahaya), aprobado por Henrry el 22-oct. Toda tabla con RLS en esta misma migración.
-- La app NO toca las tablas: todo pasa por las funciones de `public` de abajo, que comprueban el permiso.

-- ───────── puntos de control oficiales (la fuente del cálculo en el servidor) ─────────
-- Generados de src/schemas.bundle.json (globalgap_fv_smart: «GLOBALG.A.P. IFA Smart checklist FV v6.0 (Aug 2024)»).
create table if not exists compliance.qms_checklist_puntos (
  checklist text not null,
  code      text not null,
  nivel     text not null check (nivel in ('Major', 'Minor', 'Recommendation')),
  orden     int  not null,
  primary key (checklist, code)
);
insert into compliance.qms_checklist_puntos (checklist, code, nivel, orden) values
  ('globalgap_fv_smart', 'FV-Smart 03.01', 'Minor', 1),
  ('globalgap_fv_smart', 'FV-Smart 03.02', 'Major', 2),
  ('globalgap_fv_smart', 'FV-Smart 03.03', 'Minor', 3),
  ('globalgap_fv_smart', 'FV-Smart 03.04', 'Minor', 4),
  ('globalgap_fv_smart', 'FV-Smart 05.01', 'Minor', 5),
  ('globalgap_fv_smart', 'FV-Smart 05.02', 'Minor', 6),
  ('globalgap_fv_smart', 'FV-Smart 10.02', 'Minor', 7),
  ('globalgap_fv_smart', 'FV-Smart 11.01', 'Major', 8),
  ('globalgap_fv_smart', 'FV-Smart 12.01', 'Minor', 9),
  ('globalgap_fv_smart', 'FV-Smart 13.01', 'Minor', 10),
  ('globalgap_fv_smart', 'FV-Smart 13.02', 'Minor', 11),
  ('globalgap_fv_smart', 'FV-Smart 13.03', 'Major', 12),
  ('globalgap_fv_smart', 'FV-Smart 15.01', 'Minor', 13),
  ('globalgap_fv_smart', 'FV-Smart 16.01', 'Minor', 14),
  ('globalgap_fv_smart', 'FV-Smart 19.01', 'Major', 15),
  ('globalgap_fv_smart', 'FV-Smart 19.02', 'Major', 16),
  ('globalgap_fv_smart', 'FV-Smart 19.03', 'Major', 17),
  ('globalgap_fv_smart', 'FV-Smart 19.04', 'Major', 18),
  ('globalgap_fv_smart', 'FV-Smart 19.05', 'Major', 19),
  ('globalgap_fv_smart', 'FV-Smart 19.06', 'Major', 20),
  ('globalgap_fv_smart', 'FV-Smart 19.07', 'Minor', 21),
  ('globalgap_fv_smart', 'FV-Smart 19.08', 'Major', 22),
  ('globalgap_fv_smart', 'FV-Smart 20.01.01', 'Minor', 23),
  ('globalgap_fv_smart', 'FV-Smart 20.01.02', 'Minor', 24),
  ('globalgap_fv_smart', 'FV-Smart 20.01.03', 'Minor', 25),
  ('globalgap_fv_smart', 'FV-Smart 20.02.01', 'Minor', 26),
  ('globalgap_fv_smart', 'FV-Smart 20.02.02', 'Minor', 27),
  ('globalgap_fv_smart', 'FV-Smart 20.02.03', 'Minor', 28),
  ('globalgap_fv_smart', 'FV-Smart 20.02.04', 'Minor', 29),
  ('globalgap_fv_smart', 'FV-Smart 20.03.01', 'Minor', 30),
  ('globalgap_fv_smart', 'FV-Smart 20.03.02', 'Minor', 31),
  ('globalgap_fv_smart', 'FV-Smart 20.03.03', 'Minor', 32),
  ('globalgap_fv_smart', 'FV-Smart 20.03.04', 'Minor', 33),
  ('globalgap_fv_smart', 'FV-Smart 20.04.01', 'Minor', 34),
  ('globalgap_fv_smart', 'FV-Smart 20.04.02', 'Minor', 35),
  ('globalgap_fv_smart', 'FV-Smart 20.04.03', 'Minor', 36),
  ('globalgap_fv_smart', 'FV-Smart 20.04.04', 'Minor', 37),
  ('globalgap_fv_smart', 'FV-Smart 21.01', 'Minor', 38),
  ('globalgap_fv_smart', 'FV-Smart 21.02', 'Minor', 39),
  ('globalgap_fv_smart', 'FV-Smart 21.03', 'Minor', 40),
  ('globalgap_fv_smart', 'FV-Smart 21.04', 'Minor', 41),
  ('globalgap_fv_smart', 'FV-Smart 21.06', 'Major', 42),
  ('globalgap_fv_smart', 'FV-Smart 22.03.01', 'Minor', 43),
  ('globalgap_fv_smart', 'FV-Smart 23.01', 'Minor', 44),
  ('globalgap_fv_smart', 'FV-Smart 23.02', 'Minor', 45),
  ('globalgap_fv_smart', 'FV-Smart 23.03', 'Minor', 46),
  ('globalgap_fv_smart', 'FV-Smart 25.01', 'Minor', 47),
  ('globalgap_fv_smart', 'FV-Smart 25.02', 'Minor', 48),
  ('globalgap_fv_smart', 'FV-Smart 25.04', 'Minor', 49),
  ('globalgap_fv_smart', 'FV-Smart 25.06', 'Minor', 50),
  ('globalgap_fv_smart', 'FV-Smart 27.01', 'Minor', 51),
  ('globalgap_fv_smart', 'FV-Smart 27.03', 'Minor', 52),
  ('globalgap_fv_smart', 'FV-Smart 27.04', 'Minor', 53),
  ('globalgap_fv_smart', 'FV-Smart 30.01.01', 'Major', 54),
  ('globalgap_fv_smart', 'FV-Smart 30.01.02', 'Minor', 55),
  ('globalgap_fv_smart', 'FV-Smart 30.01.03', 'Minor', 56),
  ('globalgap_fv_smart', 'FV-Smart 30.02.01', 'Minor', 57),
  ('globalgap_fv_smart', 'FV-Smart 30.02.02', 'Minor', 58),
  ('globalgap_fv_smart', 'FV-Smart 30.04.02', 'Minor', 59),
  ('globalgap_fv_smart', 'FV-Smart 30.05.01', 'Major', 60),
  ('globalgap_fv_smart', 'FV-Smart 30.05.02', 'Minor', 61),
  ('globalgap_fv_smart', 'FV-Smart 30.05.04', 'Major', 62),
  ('globalgap_fv_smart', 'FV-Smart 30.05.05', 'Major', 63),
  ('globalgap_fv_smart', 'FV-Smart 30.05.06', 'Major', 64),
  ('globalgap_fv_smart', 'FV-Smart 32.01.01', 'Major', 65),
  ('globalgap_fv_smart', 'FV-Smart 32.01.02', 'Major', 66),
  ('globalgap_fv_smart', 'FV-Smart 32.02.01', 'Major', 67),
  ('globalgap_fv_smart', 'FV-Smart 32.04.01', 'Minor', 68),
  ('globalgap_fv_smart', 'FV-Smart 32.04.02', 'Minor', 69),
  ('globalgap_fv_smart', 'FV-Smart 32.04.03', 'Minor', 70),
  ('globalgap_fv_smart', 'FV-Smart 32.04.04', 'Minor', 71),
  ('globalgap_fv_smart', 'FV-Smart 32.04.05', 'Minor', 72),
  ('globalgap_fv_smart', 'FV-Smart 32.04.06', 'Minor', 73),
  ('globalgap_fv_smart', 'FV-Smart 32.05.01', 'Minor', 74),
  ('globalgap_fv_smart', 'FV-Smart 32.08.01', 'Minor', 75),
  ('globalgap_fv_smart', 'FV-Smart 32.09.01', 'Major', 76),
  ('globalgap_fv_smart', 'FV-Smart 32.09.02', 'Minor', 77),
  ('globalgap_fv_smart', 'FV-Smart 32.09.03', 'Minor', 78),
  ('globalgap_fv_smart', 'FV-Smart 32.09.04', 'Minor', 79),
  ('globalgap_fv_smart', 'FV-Smart 32.09.05', 'Minor', 80),
  ('globalgap_fv_smart', 'FV-Smart 32.09.06', 'Minor', 81),
  ('globalgap_fv_smart', 'FV-Smart 32.10.01', 'Minor', 82),
  ('globalgap_fv_smart', 'FV-Smart 32.10.02', 'Minor', 83),
  ('globalgap_fv_smart', 'FV-Smart 32.10.03', 'Minor', 84),
  ('globalgap_fv_smart', 'FV-Smart 32.10.04', 'Minor', 85),
  ('globalgap_fv_smart', 'FV-Smart 32.11.01', 'Minor', 86),
  ('globalgap_fv_smart', 'FV-Smart 33.01.01', 'Major', 87),
  ('globalgap_fv_smart', 'FV-Smart 33.01.02', 'Major', 88),
  ('globalgap_fv_smart', 'FV-Smart 33.01.03', 'Minor', 89),
  ('globalgap_fv_smart', 'FV-Smart 33.01.04', 'Major', 90),
  ('globalgap_fv_smart', 'FV-Smart 33.02.01', 'Major', 91),
  ('globalgap_fv_smart', 'FV-Smart 33.02.02', 'Major', 92),
  ('globalgap_fv_smart', 'FV-Smart 33.03.01', 'Minor', 93),
  ('globalgap_fv_smart', 'FV-Smart 33.04.01', 'Major', 94),
  ('globalgap_fv_smart', 'FV-Smart 33.04.02', 'Minor', 95),
  ('globalgap_fv_smart', 'FV-Smart 33.05.01', 'Minor', 96),
  ('globalgap_fv_smart', 'FV-Smart 33.06.01', 'Minor', 97)
on conflict (checklist, code) do update set nivel = excluded.nivel, orden = excluded.orden;

-- ───────── auditorías internas: del cronograma al informe y la decisión ─────────
create table if not exists compliance.qms_inspecciones (
  id                  uuid primary key default gen_random_uuid(),
  client_slug         text not null,
  miembro_id          uuid not null references compliance.qms_miembros(id) on delete restrict,
  checklist           text not null default 'globalgap_fv_smart',
  fecha_plan          date not null,
  inspector_correo    text not null check (inspector_correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(inspector_correo) <= 200),
  inspector_id        uuid references auth.users(id) on delete set null,
  estado              text not null default 'planificada' check (estado in ('planificada', 'enviada', 'decidida', 'cancelada')),
  planificada_por     uuid default auth.uid(),
  planificada_en      timestamptz not null default now(),
  cancelada_motivo    text check (coalesce(length(cancelada_motivo), 0) <= 500),
  -- el informe (05.02 g)
  inicio              timestamptz,
  fin                 timestamptz,
  socio_identificacion text,
  socio_nombre        text,
  productos           jsonb,
  sitios              jsonb,
  firmante_nombre     text check (coalesce(length(firmante_nombre), 0) <= 200),
  firma_socio         text check (firma_socio is null or (firma_socio like 'data:image/png;base64,%' and length(firma_socio) <= 400000)),
  inspector_nombre    text check (coalesce(length(inspector_nombre), 0) <= 200),
  firma_inspector     text check (firma_inspector is null or (firma_inspector like 'data:image/png;base64,%' and length(firma_inspector) <= 400000)),
  resultados          jsonb,
  cumplimiento        jsonb,
  enviada_en          timestamptz,
  enviada_por         uuid,
  -- la decisión (05.02 h, xi)
  decision            text check (decision in ('conforme', 'no_conforme')),
  decision_comentario text check (coalesce(length(decision_comentario), 0) <= 1000),
  decidida_por        uuid,
  decidida_por_correo text,
  decidida_por_nombre text check (coalesce(length(decidida_por_nombre), 0) <= 200),
  decidida_en         timestamptz,
  constraint qms_insp_duracion check (fin is null or (inicio is not null and fin > inicio and fin - inicio <= interval '24 hours')),
  constraint qms_insp_informe_completo check (estado not in ('enviada', 'decidida') or (
    inicio is not null and fin is not null and resultados is not null and cumplimiento is not null and firma_socio is not null
    and firma_inspector is not null and coalesce(btrim(firmante_nombre), '') <> '' and coalesce(btrim(inspector_nombre), '') <> '')),
  constraint qms_insp_decision_completa check (estado <> 'decidida' or (decision is not null and decidida_en is not null
    and coalesce(btrim(decidida_por_nombre), '') <> '')),
  constraint qms_insp_cancelada_con_motivo check (estado <> 'cancelada' or coalesce(btrim(cancelada_motivo), '') <> '')
);
create index if not exists qms_insp_slug on compliance.qms_inspecciones (client_slug, fecha_plan);
create index if not exists qms_insp_miembro on compliance.qms_inspecciones (miembro_id);
create unique index if not exists qms_insp_una_abierta on compliance.qms_inspecciones (miembro_id) where estado = 'planificada';

-- Lo enviado no cambia: de «enviada» solo se pasa a «decidida» (y solo cambian los campos de la decisión); lo decidido
-- y lo cancelado ya no cambian. El grupo, el socio y la lista de puntos no cambian nunca.
create or replace function compliance._qms_insp_guardia()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'QMS: una auditoría interna no se borra; si no se hará, se cancela con motivo' using errcode = '42501';
  end if;
  if new.client_slug is distinct from old.client_slug or new.miembro_id is distinct from old.miembro_id
     or new.checklist is distinct from old.checklist then
    raise exception 'QMS: el grupo, el socio y la lista de puntos de una auditoría no cambian' using errcode = '23514';
  end if;
  if old.estado in ('decidida', 'cancelada') then
    raise exception 'QMS: esta auditoría ya está cerrada (%)', old.estado using errcode = '42501';
  end if;
  if old.estado = 'enviada' and (new.estado <> 'decidida'
     or (new.inicio, new.fin, new.socio_identificacion, new.socio_nombre, new.productos, new.sitios, new.firmante_nombre,
         new.firma_socio, new.inspector_nombre, new.firma_inspector, new.resultados, new.cumplimiento, new.enviada_en,
         new.enviada_por, new.inspector_id, new.inspector_correo, new.fecha_plan)
        is distinct from
        (old.inicio, old.fin, old.socio_identificacion, old.socio_nombre, old.productos, old.sitios, old.firmante_nombre,
         old.firma_socio, old.inspector_nombre, old.firma_inspector, old.resultados, old.cumplimiento, old.enviada_en,
         old.enviada_por, old.inspector_id, old.inspector_correo, old.fecha_plan)) then
    raise exception 'QMS: el informe enviado no se edita (05.02 f)' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_qms_insp_guardia on compliance.qms_inspecciones;
create trigger trg_qms_insp_guardia before update or delete on compliance.qms_inspecciones
  for each row execute function compliance._qms_insp_guardia();

-- ───────── RLS (además de las funciones) ─────────
alter table compliance.qms_checklist_puntos enable row level security;
alter table compliance.qms_inspecciones     enable row level security;
drop policy if exists qms_checklist_leer on compliance.qms_checklist_puntos;
create policy qms_checklist_leer on compliance.qms_checklist_puntos for select to authenticated using (true);  -- es el texto público del estándar
drop policy if exists qms_insp_leer on compliance.qms_inspecciones;
create policy qms_insp_leer on compliance.qms_inspecciones for select to authenticated
  using (compliance.fn_qms_lee_registro(client_slug) or inspector_id = auth.uid());
-- Sin políticas de escritura: se escribe solo por las funciones de abajo.
revoke all on compliance.qms_checklist_puntos, compliance.qms_inspecciones from public, anon, authenticated;

-- ───────── el cálculo del cumplimiento (05.02 g vi-ix) ─────────
-- Valida que el informe traiga CADA punto de la lista una sola vez, con su comentario y su plazo donde corresponde, y
-- calcula con el nivel OFICIAL de cada punto (el del equipo no cuenta). Devuelve el resumen; si algo falta, lo dice.
create or replace function compliance.fn_qms_cumplimiento(p_checklist text, p_res jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  n int; v jsonb;
  ma int; mn int; ia int; inc int; ra int; rn int; na int;
begin
  if not exists (select 1 from compliance.qms_checklist_puntos where checklist = p_checklist) then
    raise exception 'QMS: lista de puntos desconocida: %', coalesce(p_checklist, '<null>') using errcode = '22023';
  end if;
  if jsonb_typeof(p_res) is distinct from 'array' then
    raise exception 'QMS: los resultados del informe van en una lista' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_res) e
              where jsonb_typeof(e) <> 'object' or coalesce(e->>'resultado', '') not in ('cumple', 'no_cumple', 'no_aplica')
                 or length(coalesce(e->>'comentario', '')) > 1000
                 or (e ? 'plazo' and e->>'plazo' is not null and e->>'plazo' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')) then
    raise exception 'QMS: hay un resultado con forma inválida (cumple, no_cumple o no_aplica; comentario de 1000 caracteres como máximo)' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_res)) <> (select count(distinct e->>'code') from jsonb_array_elements(p_res) e) then
    raise exception 'QMS: un punto de control aparece dos veces en el informe' using errcode = '22023';
  end if;
  select count(*) into n from jsonb_array_elements(p_res) e
   where not exists (select 1 from compliance.qms_checklist_puntos p where p.checklist = p_checklist and p.code = e->>'code');
  if n > 0 then raise exception 'QMS: % puntos del informe no son de la lista oficial', n using errcode = '22023'; end if;
  select count(*) into n from compliance.qms_checklist_puntos p
   where p.checklist = p_checklist and not exists (select 1 from jsonb_array_elements(p_res) e where e->>'code' = p.code);
  if n > 0 then raise exception 'QMS: faltan % puntos de control sin resultado (05.02 g vi)', n using errcode = '22023'; end if;

  select count(*) into n from jsonb_array_elements(p_res) e
    join compliance.qms_checklist_puntos p on p.checklist = p_checklist and p.code = e->>'code'
   where (p.nivel = 'Major' or (p.nivel = 'Minor' and e->>'resultado' <> 'cumple')) and coalesce(btrim(e->>'comentario'), '') = '';
  if n > 0 then
    raise exception 'QMS: % puntos necesitan comentario: los Major siempre, y los Minor que no cumplen o no aplican (05.02 g vii)', n using errcode = '22023';
  end if;
  select count(*) into n from jsonb_array_elements(p_res) e
    join compliance.qms_checklist_puntos p on p.checklist = p_checklist and p.code = e->>'code'
   where e->>'resultado' = 'no_cumple' and p.nivel <> 'Recommendation' and coalesce(e->>'plazo', '') = '';
  if n > 0 then raise exception 'QMS: % incumplimientos sin plazo para la acción correctiva (05.02 g viii)', n using errcode = '22023'; end if;

  select count(*) filter (where p.nivel = 'Major' and e->>'resultado' <> 'no_aplica'),
         count(*) filter (where p.nivel = 'Major' and e->>'resultado' = 'no_cumple'),
         count(*) filter (where p.nivel = 'Minor' and e->>'resultado' <> 'no_aplica'),
         count(*) filter (where p.nivel = 'Minor' and e->>'resultado' = 'no_cumple'),
         count(*) filter (where p.nivel = 'Recommendation' and e->>'resultado' <> 'no_aplica'),
         count(*) filter (where p.nivel = 'Recommendation' and e->>'resultado' = 'no_cumple'),
         count(*) filter (where e->>'resultado' = 'no_aplica')
    into ma, mn, ia, inc, ra, rn, na
    from jsonb_array_elements(p_res) e join compliance.qms_checklist_puntos p on p.checklist = p_checklist and p.code = e->>'code';
  v := jsonb_build_object(
    'major_aplicables', ma, 'major_no_cumple', mn,
    'pct_major', case when ma = 0 then 100 else round(100.0 * (ma - mn) / ma, 1) end,
    'minor_aplicables', ia, 'minor_no_cumple', inc,
    'pct_minor', case when ia = 0 then 100 else round(100.0 * (ia - inc) / ia, 1) end,
    'recom_aplicables', ra, 'recom_no_cumple', rn, 'no_aplica', na);
  return v || jsonb_build_object('cumple', mn = 0 and (v->>'pct_minor')::numeric >= 95);
end;
$$;

-- ───────── funciones que llama la app ─────────
-- (1) Cronograma del grupo: lo ven la directiva o calidad, VG y el auditor externo. Sin firmas ni resultados (pesan);
-- el informe completo se pide aparte con cert_qms_informe.
create or replace function public.cert_qms_cronograma(p_slug text)
returns table (id uuid, miembro_id uuid, socio_nombre text, socio_estado text, fecha_plan date, inspector_correo text,
               estado text, inicio timestamptz, fin timestamptz, cumplimiento jsonb, decision text,
               decidida_por_nombre text, decidida_en timestamptz, cancelada_motivo text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not compliance.fn_qms_lee_registro(p_slug) then
    raise exception 'el cronograma lo ven la directiva, calidad y el auditor del grupo' using errcode = '42501';
  end if;
  return query
    select i.id, i.miembro_id, m.nombre, m.estado, i.fecha_plan, i.inspector_correo, i.estado, i.inicio, i.fin, i.cumplimiento,
           i.decision, i.decidida_por_nombre, i.decidida_en, i.cancelada_motivo
      from compliance.qms_inspecciones i join compliance.qms_miembros m on m.id = i.miembro_id
     where i.client_slug = p_slug
     order by i.estado = 'cancelada', i.fecha_plan desc;
end;
$$;

create or replace function public.cert_qms_planificar(p_slug text, p_miembro uuid, p_fecha date, p_inspector text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_estado text;
begin
  if coalesce(compliance.fn_qms_nivel(p_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo planifica auditorías internas' using errcode = '42501';
  end if;
  select estado into v_estado from compliance.qms_miembros where id = p_miembro and client_slug = p_slug;
  if v_estado is null then raise exception 'ese socio no es de este grupo' using errcode = '42501'; end if;
  if v_estado = 'excluido' then raise exception 'un socio excluido no se audita; primero se readmite' using errcode = '22023'; end if;
  if p_fecha is null or p_fecha > current_date + 400 then
    raise exception 'la auditoría necesita una fecha dentro del próximo año' using errcode = '22023';
  end if;
  if coalesce(btrim(p_inspector), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'falta el correo del auditor interno' using errcode = '22023';
  end if;
  insert into compliance.qms_inspecciones (client_slug, miembro_id, fecha_plan, inspector_correo)
  values (p_slug, p_miembro, p_fecha, lower(btrim(p_inspector))) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.cert_qms_cancelar_inspeccion(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_slug text; v_estado text;
begin
  select client_slug, estado into v_slug, v_estado from compliance.qms_inspecciones where id = p_id;
  if v_slug is null or coalesce(compliance.fn_qms_nivel(v_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo cancela una auditoría' using errcode = '42501';
  end if;
  if v_estado <> 'planificada' then raise exception 'solo se cancela una auditoría que todavía no se hizo' using errcode = '22023'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'cancelar una auditoría exige el motivo' using errcode = '22023'; end if;
  update compliance.qms_inspecciones set estado = 'cancelada', cancelada_motivo = btrim(p_motivo) where id = p_id;
end;
$$;

-- (2) Las auditorías que el usuario actual tiene asignadas y abiertas, con lo que necesita para llevarlas a la finca
-- sin señal: socio, cédula, dirección, productos y sitios (no el teléfono ni el correo de los demás socios).
-- Entra quien tiene acceso al grupo (también el técnico, «captura»): el QMS lo asigna como auditor interno.
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

-- Envío del informe hecho sin señal. Se puede reintentar: si la respuesta se perdió y ya quedó enviado por la misma
-- persona, devuelve el mismo resultado en vez de fallar. El socio y sus productos salen del registro, no del equipo.
-- p: {id, inicio, fin, firmante_nombre, firma_socio, inspector_nombre, firma_inspector, resultados: [{code, resultado, comentario, plazo}]}
create or replace function public.cert_qms_enviar_inspeccion(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v compliance.qms_inspecciones%rowtype; v_correo text := lower(coalesce(auth.jwt()->>'email', ''));
  v_ini timestamptz; v_fin timestamptz; v_cump jsonb; m compliance.qms_miembros%rowtype; n int;
begin
  select * into v from compliance.qms_inspecciones where id = nullif(p->>'id', '')::uuid for update;
  if v.id is null then raise exception 'esa auditoría no existe' using errcode = '42501'; end if;
  if v.estado in ('enviada', 'decidida') and v.enviada_por = auth.uid() then return v.cumplimiento; end if;
  if not (v.inspector_id = auth.uid() or (v_correo <> '' and lower(v.inspector_correo) = v_correo))
     or coalesce(compliance.fn_qms_nivel(v.client_slug), '') not in ('admin', 'gestion', 'captura') then
    raise exception 'esta auditoría está asignada a otro auditor interno' using errcode = '42501';
  end if;
  if v.estado <> 'planificada' then
    raise exception 'esta auditoría ya no está abierta (%)', v.estado using errcode = '22023';
  end if;
  begin
    v_ini := (p->>'inicio')::timestamptz; v_fin := (p->>'fin')::timestamptz;
  exception when others then raise exception 'falta la hora de inicio o de fin de la auditoría (05.02 g x)' using errcode = '22023';
  end;
  if v_ini is null or v_fin is null or v_fin <= v_ini then
    raise exception 'la hora de fin tiene que ser posterior a la de inicio (05.02 g x)' using errcode = '22023';
  end if;
  if v_fin > now() + interval '15 minutes' then
    raise exception 'la hora de fin está en el futuro: revise la hora del equipo' using errcode = '22023';
  end if;
  if coalesce(btrim(p->>'firmante_nombre'), '') = '' or coalesce(btrim(p->>'inspector_nombre'), '') = '' then
    raise exception 'faltan el nombre de quien firma por el socio o el del auditor (05.02 g ii, iv)' using errcode = '22023';
  end if;
  if coalesce(p->>'firma_socio', '') not like 'data:image/png;base64,%' or coalesce(p->>'firma_inspector', '') not like 'data:image/png;base64,%' then
    raise exception 'faltan las firmas del socio y del auditor (05.02 g ii, iv)' using errcode = '22023';
  end if;
  v_cump := compliance.fn_qms_cumplimiento(v.checklist, p->'resultados');
  select count(*) into n from jsonb_array_elements(p->'resultados') e
   where e->>'resultado' = 'no_cumple' and coalesce(e->>'plazo', '') <> ''
     and (e->>'plazo')::date < (v_ini at time zone 'America/Guayaquil')::date;
  if n > 0 then raise exception 'QMS: % plazos de acción correctiva son anteriores a la auditoría', n using errcode = '22023'; end if;

  select * into m from compliance.qms_miembros where id = v.miembro_id;
  update compliance.qms_inspecciones set
    estado = 'enviada', inicio = v_ini, fin = v_fin, socio_identificacion = m.identificacion, socio_nombre = m.nombre,
    productos = m.productos, sitios = m.sitios, firmante_nombre = btrim(p->>'firmante_nombre'), firma_socio = p->>'firma_socio',
    inspector_nombre = btrim(p->>'inspector_nombre'), firma_inspector = p->>'firma_inspector',
    resultados = (select jsonb_agg(jsonb_build_object('code', e->>'code', 'resultado', e->>'resultado',
                    'comentario', nullif(btrim(coalesce(e->>'comentario', '')), ''), 'plazo', nullif(e->>'plazo', ''))
                    order by pt.orden)
                    from jsonb_array_elements(p->'resultados') e
                    join compliance.qms_checklist_puntos pt on pt.checklist = v.checklist and pt.code = e->>'code'),
    cumplimiento = v_cump, enviada_en = now(), enviada_por = auth.uid(), inspector_id = auth.uid()
   where id = v.id;
  return v_cump;
end;
$$;

-- El informe completo, con firmas y resultados: la directiva o calidad, VG, el auditor externo y quien lo hizo.
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

-- (3) Decisión de la directiva o calidad (05.02 h). Quien hizo la auditoría no la aprueba (12.5 a; si hay un solo
-- auditor interno, aprueba el responsable del QMS: 05.02 i). Al decidir se anota la fecha en el registro del socio.
create or replace function public.cert_qms_decidir(p_id uuid, p_decision text, p_nombre text, p_comentario text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v compliance.qms_inspecciones%rowtype; v_correo text := lower(coalesce(auth.jwt()->>'email', ''));
begin
  select * into v from compliance.qms_inspecciones where id = p_id for update;
  if v.id is null or coalesce(compliance.fn_qms_nivel(v.client_slug), '') not in ('admin', 'gestion') then
    raise exception 'solo la directiva o calidad del grupo decide sobre una auditoría interna' using errcode = '42501';
  end if;
  if v.estado <> 'enviada' then raise exception 'esta auditoría no espera decisión (%)', v.estado using errcode = '22023'; end if;
  if v.enviada_por = auth.uid() or v.inspector_id = auth.uid() or lower(v.inspector_correo) = v_correo then
    raise exception 'quien hizo la auditoría no la aprueba (QMS 12.5 a)' using errcode = '42501';
  end if;
  if p_decision not in ('conforme', 'no_conforme') then raise exception 'la decisión es conforme o no conforme' using errcode = '22023'; end if;
  if coalesce(btrim(p_nombre), '') = '' then raise exception 'falta el nombre de quien aprueba (05.02 g xi)' using errcode = '22023'; end if;
  if p_decision = 'conforme' and not coalesce((v.cumplimiento->>'cumple')::boolean, false) then
    raise exception 'no se puede declarar conforme: el cálculo no cumple (Major 100 %% y Minor 95 %%)' using errcode = '22023';
  end if;
  if p_decision = 'no_conforme' and coalesce(btrim(p_comentario), '') = '' then
    raise exception 'declarar no conforme exige el motivo' using errcode = '22023';
  end if;
  update compliance.qms_inspecciones set estado = 'decidida', decision = p_decision, decision_comentario = nullif(btrim(p_comentario), ''),
    decidida_por = auth.uid(), decidida_por_correo = v_correo, decidida_por_nombre = btrim(p_nombre), decidida_en = now()
   where id = p_id;
  update compliance.qms_miembros set ultima_auditoria_interna =
      greatest(coalesce(ultima_auditoria_interna, '1900-01-01'::date), (v.inicio at time zone 'America/Guayaquil')::date)
   where id = v.miembro_id;
end;
$$;

-- ───────── permisos de ejecución ─────────
do $$ declare f text; begin
  foreach f in array array[
    'public.cert_qms_cronograma(text)', 'public.cert_qms_planificar(text, uuid, date, text)',
    'public.cert_qms_cancelar_inspeccion(uuid, text)', 'public.cert_qms_mis_inspecciones()',
    'public.cert_qms_enviar_inspeccion(jsonb)', 'public.cert_qms_informe(uuid)', 'public.cert_qms_decidir(uuid, text, text, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['compliance.fn_qms_cumplimiento(text, jsonb)', 'compliance._qms_insp_guardia()']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
