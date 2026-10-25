-- IDA Y VUELTA de la auditoría interna de finca (generado por armar_ida_y_vuelta.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
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
insert into _h select 'con_migracion', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
-- Prueba de la auditoría interna de finca (QMS 05.02). Corre DESPUÉS de la migración 20261025000000, dentro de la
-- transacción de ida_y_vuelta_qms_auditoria_interna.sql. Usuarios, grupo y cédulas ficticios. Cada resultado va a _res;
-- el error final de la ida y vuelta deshace todo y trae los resultados en su mensaje.
do $prueba$
declare
  g uuid := gen_random_uuid(); q uuid := gen_random_uuid(); c uuid := gen_random_uuid(); l uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); x uuid := gen_random_uuid();
  slug text := 'prueba-qms-auditoria'; otro text := 'prueba-qms-otro2';
  m1 uuid; m2 uuid; m3 uuid; mx uuid; i1 uuid; i2 uuid; i3 uuid;
  todo_cumple jsonb; tres_minor jsonb; major_nc jsonb; sin_coment jsonb; sin_plazo jsonb; incompleto jsonb; nivel_falso jsonb;
  firma text := 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  ini text := (now() - interval '2 hours')::text; fin text := (now() - interval '50 minutes')::text;
  n int; t text; r jsonb; ok boolean; d date;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    select u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', e
      from (values (g, 'g-ai@vg.invalid'), (q, 'q-ai@vg.invalid'), (c, 'c-ai@vg.invalid'), (l, 'l-ai@vg.invalid'),
                   (a, 'auditora-ai@vg.invalid'), (x, 'x-ai@vg.invalid')) v(u, e);
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values
    (g, 'eudr', 'producer_admin',         array[slug], 'active', null),
    (q, 'eudr', 'gerente_sostenibilidad', array[slug], 'active', null),
    (c, 'eudr', 'field_worker',           array[slug], 'active', null),
    (l, 'eudr', 'lector',                 array[slug], 'active', null),
    (a, 'eudr', 'auditor',                '{}',        'active', now() + interval '60 days'),
    (x, 'eudr', 'producer_admin',         array[otro], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs,
    tier = excluded.tier, expires_at = excluded.expires_at;

  -- Los informes de prueba se arman con la lista oficial (como superusuario: la app no lee la tabla).
  select jsonb_agg(jsonb_build_object('code', code, 'resultado', 'cumple',
           'comentario', case when nivel = 'Major' then 'Verificado en finca (prueba)' end) order by orden)
    into todo_cumple from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart';
  -- 3 Minor de 71 no cumplen → 95,8 %: cumple
  select jsonb_agg(case when nivel = 'Minor' and k <= 3
           then jsonb_build_object('code', code, 'resultado', 'no_cumple', 'comentario', 'Falta registro (prueba)', 'plazo', (current_date + 30)::text)
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) end order by orden)
    into tres_minor
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;
  -- 1 Major no cumple → no cumple aunque el equipo diga que es Minor
  select jsonb_agg(case when nivel = 'Major' and k = 1
           then jsonb_build_object('code', code, 'nivel', 'Minor', 'resultado', 'no_cumple', 'comentario', 'Sin análisis de agua (prueba)', 'plazo', (current_date + 15)::text)
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) end order by orden)
    into major_nc
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;
  nivel_falso := major_nc;
  select jsonb_agg(jsonb_build_object('code', code, 'resultado', 'cumple') order by orden)
    into sin_coment from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart';
  select jsonb_agg(case when nivel = 'Minor' and k = 1
           then jsonb_build_object('code', code, 'resultado', 'no_cumple', 'comentario', 'Falta (prueba)')
           else jsonb_build_object('code', code, 'resultado', 'cumple', 'comentario', case when nivel = 'Major' then 'Verificado (prueba)' end) end order by orden)
    into sin_plazo
    from (select *, row_number() over (partition by nivel order by orden) k from compliance.qms_checklist_puntos where checklist = 'globalgap_fv_smart') s;
  select jsonb_agg(e) into incompleto from (select e from jsonb_array_elements(todo_cumple) e limit 90) s;

  -- socios y auditor externo (directiva)
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-ai@vg.invalid')::text, true);
  set local role authenticated;
  m1 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999991', 'nombre', 'Socia auditada uno',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":2.1}]'::jsonb, 'sitios', '[{"nombre":"Finca Uno","area_ha":2.1,"certificado":true}]'::jsonb));
  m2 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999992', 'nombre', 'Socio auditado dos',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1.5}]'::jsonb));
  m3 := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999993', 'nombre', 'Aspirante tres',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1.0}]'::jsonb));
  mx := public.cert_qms_guardar_miembro(jsonb_build_object('client_slug', slug, 'identificacion', '0999999994', 'nombre', 'Excluido cuatro',
          'productos', '[{"cultivo":"pitahaya amarilla","area_ha":1.0}]'::jsonb));
  perform public.cert_qms_cambiar_estado(m1, 'activo'); perform public.cert_qms_cambiar_estado(m2, 'activo');
  perform public.cert_qms_cambiar_estado(mx, 'excluido', 'Producto no autorizado (prueba)');
  perform public.cert_qms_autorizar_auditor(slug, 'auditora-ai@vg.invalid', 'Certificador de prueba', current_date + 60);

  -- 01 la directiva planifica y asigna al técnico
  i1 := public.cert_qms_planificar(slug, m1, current_date, 'C-AI@vg.invalid');
  insert into _res values ('01 la directiva planifica la auditoría: ' || case when i1 is not null then 'OK' else 'FALLA' end);
  -- 02 una sola abierta por socio
  begin perform public.cert_qms_planificar(slug, m1, current_date + 3, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when unique_violation then t := 'OK'; when others then t := 'FALLA ' || sqlstate; end;
  insert into _res values ('02 una sola auditoría abierta por socio: ' || t);
  -- 03 un excluido no se audita
  begin perform public.cert_qms_planificar(slug, mx, current_date, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('03 un socio excluido no se planifica: ' || t);
  i2 := public.cert_qms_planificar(slug, m2, current_date, 'g-ai@vg.invalid');     -- la directiva se asigna a sí misma
  i3 := public.cert_qms_planificar(slug, m3, current_date + 10, 'c-ai@vg.invalid');

  -- 04 el técnico no planifica, pero ve SOLO lo suyo, con lo necesario para la finca
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-ai@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_planificar(slug, m2, current_date, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('04 el técnico no planifica: ' || t);
  select count(*), bool_and(socio_nombre is not null and productos is not null) into n, ok from public.cert_qms_mis_inspecciones();
  insert into _res values ('05 el técnico ve sus 2 auditorías asignadas (' || n || '): ' || case when n = 2 and ok then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_cronograma(slug); t := 'FALLA (vio el cronograma)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('05b el técnico no ve el cronograma del grupo: ' || t);

  -- 06 informes incompletos: el servidor dice qué falta
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', incompleto)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%faltan 7 puntos%' then 'OK' else 'FALLA ' || sqlstate || ' ' || sqlerrm end; end;
  insert into _res values ('06 informe con 7 puntos sin resultado se rechaza: ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', sin_coment)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%26 puntos necesitan comentario%' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('07 Major sin comentario se rechaza (26): ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', sin_plazo)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%sin plazo%' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('08 incumplimiento sin plazo se rechaza: ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia',
          'firma_socio', null, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', todo_cumple)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' and sqlerrm like '%firmas%' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('09 sin la firma del socio se rechaza: ' || t);
  begin perform public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', fin, 'fin', ini, 'firmante_nombre', 'Socia',
          'firma_socio', firma, 'inspector_nombre', 'Técnico', 'firma_inspector', firma, 'resultados', todo_cumple)); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlerrm end; end;
  insert into _res values ('10 fin antes del inicio se rechaza: ' || t);

  -- 11 envío válido: 3 Minor de 71 no cumplen → 95,8 % y cumple
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socia auditada uno',
          'firma_socio', firma, 'inspector_nombre', 'Técnico de prueba', 'firma_inspector', firma, 'resultados', tres_minor));
  insert into _res values ('11 envío válido (95,8 por ciento, cumple): ' || case when (r->>'pct_minor')::numeric = 95.8 and (r->>'cumple')::boolean
    and (r->>'major_aplicables')::int = 26 and (r->>'minor_no_cumple')::int = 3 then 'OK' else 'FALLA ' || r::text end);
  -- 12 reintento tras perder la respuesta: mismo resultado, sin error
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i1, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'X',
          'firma_socio', firma, 'inspector_nombre', 'X', 'firma_inspector', firma, 'resultados', todo_cumple));
  insert into _res values ('12 reenviar es idempotente (no pisa el original): ' || case when (r->>'minor_no_cumple')::int = 3 then 'OK' else 'FALLA' end);
  select count(*) into n from public.cert_qms_mis_inspecciones();
  insert into _res values ('13 lo enviado sale de la lista del técnico (' || n || '): ' || case when n = 1 then 'OK' else 'FALLA' end);
  select count(*) into n from public.cert_qms_informe(i1) where firma_socio is not null;
  insert into _res values ('14 el técnico lee su propio informe: ' || case when n = 1 then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_decidir(i1, 'conforme', 'Técnico'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('15 el técnico no decide: ' || t);

  -- 16 el informe enviado no se edita ni se borra, ni siquiera el dueño de la base
  reset role;
  begin update compliance.qms_inspecciones set resultados = todo_cumple where id = i1; t := 'FALLA (editó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin delete from compliance.qms_inspecciones where id = i1; t := t || ' / FALLA (borró)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('16 informe enviado: ni editar ni borrar: ' || t);

  -- 17 quien audita no aprueba (la directiva se auditó m2 y no puede decidir sobre ella)
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'email', 'g-ai@vg.invalid')::text, true);
  set local role authenticated;
  r := public.cert_qms_enviar_inspeccion(jsonb_build_object('id', i2, 'inicio', ini, 'fin', fin, 'firmante_nombre', 'Socio dos',
          'firma_socio', firma, 'inspector_nombre', 'Directiva', 'firma_inspector', firma, 'resultados', nivel_falso));
  insert into _res values ('17 el nivel lo pone el servidor: Major no cumple aunque el equipo diga Minor: '
    || case when (r->>'major_no_cumple')::int = 1 and not (r->>'cumple')::boolean then 'OK' else 'FALLA ' || r::text end);
  begin perform public.cert_qms_decidir(i2, 'no_conforme', 'Directiva', 'Major sin cumplir'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('18 quien hizo la auditoría no la aprueba (12.5 a): ' || t);

  -- 19 calidad decide: conforme bloqueado si no cumple; no conforme exige motivo
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', q, 'role', 'authenticated', 'email', 'q-ai@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_decidir(i2, 'conforme', 'Calidad'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_decidir(i2, 'no_conforme', 'Calidad', ''); t := t || ' / FALLA (sin motivo)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  perform public.cert_qms_decidir(i2, 'no_conforme', 'Responsable de calidad', 'Major sin cumplir: análisis de agua');
  insert into _res values ('19 conforme bloqueado si no cumple; no conforme con motivo: ' || t);
  begin perform public.cert_qms_decidir(i1, 'conforme', ''); t := 'FALLA (sin nombre)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_decidir(i1, 'conforme', 'Responsable de calidad');
  select ultima_auditoria_interna into d from public.cert_qms_miembros(slug) where id = m1;
  insert into _res values ('20 conforme con nombre y fecha en el registro del socio: ' || case when t = 'OK'
    and d = ((ini::timestamptz) at time zone 'America/Guayaquil')::date then 'OK' else 'FALLA ' || t || ' ' || coalesce(d::text, 'sin fecha') end);
  begin perform public.cert_qms_decidir(i1, 'no_conforme', 'Otro', 'cambio'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('21 una decisión no se cambia: ' || t);

  -- 22 cancelar: con motivo y solo lo que no se hizo
  begin perform public.cert_qms_cancelar_inspeccion(i3, ' '); t := 'FALLA (sin motivo)';
  exception when others then t := case when sqlstate = '22023' then 'OK' else 'FALLA ' || sqlstate end; end;
  perform public.cert_qms_cancelar_inspeccion(i3, 'El socio viaja; se reprograma (prueba)');
  begin perform public.cert_qms_cancelar_inspeccion(i1, 'tarde'); t := t || ' / FALLA (canceló un enviado)';
  exception when others then t := t || case when sqlstate = '22023' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  select count(*) into n from public.cert_qms_cronograma(slug);
  insert into _res values ('22 cancelar exige motivo y solo lo no hecho (cronograma ' || n || '): ' || case when n = 3 then t else 'FALLA' end);

  -- 23 auditor externo: lee el cronograma y el informe con firmas
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'auditora-ai@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_cronograma(slug);
  select (firma_inspector is not null and decision = 'conforme') into ok from public.cert_qms_informe(i1);
  insert into _res values ('23 el auditor externo lee cronograma e informe: ' || case when n = 3 and ok then 'OK' else 'FALLA' end);
  begin perform public.cert_qms_planificar(slug, m3, current_date, 'c-ai@vg.invalid'); t := 'FALLA (aceptó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('24 el auditor externo no planifica: ' || t);

  -- 25 otro grupo y solo lectura: nada
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', x, 'role', 'authenticated', 'email', 'x-ai@vg.invalid')::text, true);
  set local role authenticated;
  begin perform public.cert_qms_informe(i1); t := 'FALLA (leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  begin perform public.cert_qms_cronograma(slug); t := t || ' / FALLA (leyó)';
  exception when others then t := t || case when sqlstate = '42501' then ' / OK' else ' / FALLA ' || sqlstate end; end;
  insert into _res values ('25 otro grupo no lee informe ni cronograma: ' || t);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', l, 'role', 'authenticated', 'email', 'l-ai@vg.invalid')::text, true);
  set local role authenticated;
  select count(*) into n from public.cert_qms_mis_inspecciones();
  begin perform public.cert_qms_informe(i1); t := 'FALLA (leyó)';
  exception when others then t := case when sqlstate = '42501' then 'OK' else 'FALLA ' || sqlstate end; end;
  insert into _res values ('26 solo lectura: sin auditorías ni informes (' || n || '): ' || case when n = 0 then t else 'FALLA' end);
  reset role;

  -- 27 anon no ejecuta nada; authenticated no toca las tablas
  select bool_or(has_function_privilege('anon', f, 'execute')) into ok from unnest(array[
    'public.cert_qms_cronograma(text)', 'public.cert_qms_planificar(text, uuid, date, text)', 'public.cert_qms_cancelar_inspeccion(uuid, text)',
    'public.cert_qms_mis_inspecciones()', 'public.cert_qms_enviar_inspeccion(jsonb)', 'public.cert_qms_informe(uuid)',
    'public.cert_qms_decidir(uuid, text, text, text)']) f;
  insert into _res values ('27 anon sin permiso; tablas cerradas: ' || case when not ok
    and not has_table_privilege('authenticated', 'compliance.qms_inspecciones', 'select')
    and not has_table_privilege('authenticated', 'compliance.qms_inspecciones', 'update') then 'OK' else 'FALLA' end);
end $prueba$;
-- Reversa de 20261025000000_cert_qms_auditoria_interna.sql: deja la base como estaba (lo comprueba la ida y vuelta).
-- 🔴 Borra los informes de auditoría interna: en producción, solo antes de que un grupo tenga informes reales.
drop function if exists public.cert_qms_cronograma(text);
drop function if exists public.cert_qms_planificar(text, uuid, date, text);
drop function if exists public.cert_qms_cancelar_inspeccion(uuid, text);
drop function if exists public.cert_qms_mis_inspecciones();
drop function if exists public.cert_qms_enviar_inspeccion(jsonb);
drop function if exists public.cert_qms_informe(uuid);
drop function if exists public.cert_qms_decidir(uuid, text, text, text);
drop table if exists compliance.qms_inspecciones;
drop table if exists compliance.qms_checklist_puntos;
drop function if exists compliance.fn_qms_cumplimiento(text, jsonb);
drop function if exists compliance._qms_insp_guardia();
insert into _h select 'despues', (select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s);
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  -- La API de gestión corta el mensaje hacia los 500 caracteres: se cuentan los OK y se muestran enteras solo las fallas.
  select count(*) filter (where t !~ 'FALLA') || ' de ' || count(*) || ' OK'
         || coalesce(' · FALLAS: ' || string_agg(t, ' || ' order by t) filter (where t ~ 'FALLA'), '')
    into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, left(a, 8), left(c, 8), left(d, 8),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
