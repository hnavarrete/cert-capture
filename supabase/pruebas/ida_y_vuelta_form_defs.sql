-- IDA Y VUELTA del catálogo al día con la app (generado por armar_ida_y_vuelta_form_defs.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', ((select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s) || ':' || (select count(*)::text from compliance.cert_form_defs));
-- VG Certificaciones · 26-oct-2026 · el catálogo del servidor (compliance.cert_form_defs) se pone al día con la app.
-- Hallado al preparar la prueba de la parte 3c: la app ofrece 62 formularios y el servidor conocía 50. Los 21 que faltaban
-- —entre ellos los cuatro de GlobalG.A.P. v6 (IFA Smart, IFA GFS, QMS y CoC), RSPO, ISCC, PEFC, Carbono, GUIA y los
-- registros de campo— no se podían respaldar: cert_upsert_response chocaba con la llave foránea form_key y la respuesta
-- quedaba solo en el equipo. Medido el 26-oct: 0 respuestas en el servidor de esos formularios (nada se perdió del lado
-- del servidor). Generado de src/schemas.bundle.json; solo AGREGA lo que falta: no toca los 50 existentes.
insert into compliance.cert_form_defs (form_key, certificacion, cultivo, titulo, schema_version, es_compartido, es_custom,
                                       programa_owner, legacy, validation_status, fuente_normativa, n_campos, n_control_points)
values
  ('carbono_arr_mrv', 'CARBONO', 'FORESTAL_TECA', 'Carbono — Proyecto ARR (MRV sobre FSC)', 1, false, false, null, false, 'EN_REVISION', 'Estructura basada en las metodologías públicas ARR/A-R: Verra VCS (AR-ACM0003 / AR-AM tools de adicionalidad y línea base, AFOLU non-permanence risk tool), Plan Vivo Standard, Gold Standard for the Global Goals (A/R). MRV = Measurement/Reporting/Verification. Co-beneficio y cadena de custodia: FSC (ya LIVE en el catálogo).', 44, 0),
  ('globalgap_coc', 'GLOBAL_GAP', 'MULTI', 'GLOBAL G.A.P. - Cadena de Custodia (CoC v6.1)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'GLOBALG.A.P. Chain of Custody (CoC) checklist v6.1 (Dec 2022)', 83, 83),
  ('globalgap_fv_gfs', 'GLOBAL_GAP', 'MULTI', 'GLOBAL G.A.P. - IFA Fruta y Verdura (P&C v6 GFS)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'GLOBALG.A.P. IFA GFS Principles & Criteria for Fruit and Vegetables v6.0-GFS (Aug 2024)', 191, 191),
  ('globalgap_fv_smart', 'GLOBAL_GAP', 'MULTI', 'GLOBAL G.A.P. - IFA Fruta y Verdura (edicion Smart)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'GLOBALG.A.P. IFA Smart checklist FV v6.0 (Aug 2024)', 97, 97),
  ('globalgap_qms', 'GLOBAL_GAP', 'MULTI', 'GLOBAL G.A.P. - QMS (certificacion grupal, Opcion 2)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'GLOBALG.A.P. IFA Smart QMS checklist v6.0 (Aug 2024)', 136, 136),
  ('guia_agrocalidad_registro_operador', 'GUIA_AGROCALIDAD', 'CACAO', 'Sistema GUIA · Registro de Operador (AgroServicios)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'Agrocalidad — Manual "Registro de Operador en AgroServicios" (Sistema GUIA) + Acuerdo Ministerial 023-2024 (Lineamientos Generales de Trazabilidad) + Lineamientos Geográficos de Trazabilidad 2024 (CGINA). Proyecto validación de lotes de cacao EUDR (AL-INVEST Verde / FIIAPP / Trias).', 25, 0),
  ('iscc_eu_hacienda', 'ISCC', 'PALMA_AFRICANA', 'ISCC EU / PLUS — hacienda (Principios 1-6)', 1, false, false, null, false, 'EN_REVISION', 'ISCC EU 202 (Sustainability Requirements) + ISCC PLUS; estructura basada en los 6 Principios públicos de ISCC y RED II UE. Complementan: ISCC 203 (Traceability and Chain of Custody) y ISCC 205 (Greenhouse Gas Emissions). Redacción de los Principios aproximada a partir de la lista pública de ISCC e ISCC 201-5 (Guidance for ISH), que comparte los mismos Principios 1-6.', 59, 0),
  ('iscc_ish_smallholder', 'ISCC', 'PALMA_AFRICANA', 'ISCC — Pequeño productor independiente (201-5)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'ISCC 201-5 "Guidance for the Certification of Independent Smallholders", Version 3.0, valid from 01 December 2017 (� ISCC System GmbH). Referencia a los documentos del sistema ISCC: 202 Sustainability Requirements (Principles 1-6), 203 Traceability and Chain of Custody, 204 Audit Requirements and Risk Management, 205 Greenhouse Gas Emissions, 206 Group Certification.', 79, 0),
  ('legacy_clmrs', 'REGISTROS_CAMPO', 'CACAO', 'CLMRS — Monitoreo de trabajo infantil', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR CLMRS (legacy Vue) — CADENA-02', 59, 0),
  ('legacy_cosecha', 'REGISTROS_CAMPO', 'CACAO', 'Cosecha (registro de campo)', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 7, 0),
  ('legacy_eudr_check', 'REGISTROS_CAMPO', 'CACAO', 'Checklist documental EUDR', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 14, 0),
  ('legacy_eudr_finca', 'REGISTROS_CAMPO', 'CACAO', 'Finca EUDR', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 4, 0),
  ('legacy_fertilizacion', 'REGISTROS_CAMPO', 'CACAO', 'Fertilizacion (registro de campo)', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 14, 0),
  ('legacy_fumigacion', 'REGISTROS_CAMPO', 'CACAO', 'Fumigacion (registro de campo)', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 19, 0),
  ('legacy_nominas', 'REGISTROS_CAMPO', 'CACAO', 'Nomina y EPP (registro de campo)', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 18, 0),
  ('legacy_recoleccion_envase', 'REGISTROS_CAMPO', 'CACAO', 'Recoleccion de envases (registro de campo)', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 8, 0),
  ('legacy_siembra', 'REGISTROS_CAMPO', 'CACAO', 'Siembra (registro de campo)', 1, false, false, null, false, 'PORTADO_LEGACY', 'Encuestador EUDR/PV (legacy Vue+PHP) — CADENA-02', 6, 0),
  ('pefc_cadena_custodia', 'PEFC_CoC', 'FORESTAL_TECA', 'PEFC — Cadena de Custodia', 1, false, false, null, false, 'EN_REVISION', 'PEFC ST 2002:2020 — Chain of Custody of Forest and Tree Based Products — Requirements (en vigor 2020-02-14). Complementos: PEFC ST 2001 (uso de marca/logo PEFC) y PEFC ST 2003 (requisitos para organismos de certificación).', 39, 0),
  ('pefc_manejo_forestal', 'PEFC_FM', 'FORESTAL_TECA', 'PEFC — Manejo Forestal Sostenible', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'PEFC ST 1003:2024 — Sustainable Forest Management — Requirements (PEFC Council, aprobado por la Asamblea General 2024-11-13). Benchmark internacional; los estándares nacionales endosados deben cumplirlo como mínimo. Criterios 1-6 (sección 8) + performance evaluation (sección 9).', 60, 0),
  ('rspo_ish_smallholder', 'RSPO', 'PALMA_AFRICANA', 'RSPO — Pequeño productor independiente (ISH)', 1, false, false, null, false, 'VALIDADO_OFICIAL', '2024 RSPO Independent Smallholder (ISH) Standard (IS_V2-0) for the Production of Sustainable Palm Oil and Oil Palm Products — adoptado en la 21ª Asamblea General de RSPO el 13-nov-2024, efectivo 13-nov-2025; reemplaza la ISH 2019 (IS_V1-0). Composición oficial: 4 Principles, 22 Criteria, 66 Indicators sobre los Impact Pillars Prosperity / People / Planet, con enfoque fasado Eligibility → Milestone A → Milestone B. Certificación GRUPAL: la Unit of Certification es el group manager y todos los miembros del grupo (el certificado lo ostenta el grupo). El Internal Control System añade 7 Criteria y 42 Indicators aplicables solo al group manager.', 33, 0),
  ('rspo_pc_hacienda', 'RSPO', 'PALMA_AFRICANA', 'RSPO — Principios y Criterios (hacienda)', 1, false, false, null, false, 'VALIDADO_OFICIAL', 'RSPO Principles & Criteria for the Production of Sustainable Palm Oil 2024 — RSPO Principles & Criteria for the Sustainable Cultivation of Oil Palms & Production of Sustainable Palm Oil and Oil Palm Products, Version 4-0 (Roundtable on Sustainable Palm Oil). Adoptado en la 21ª Asamblea General de RSPO el 13 de noviembre de 2024 (Adoption Date 2024-11-13); fecha efectiva y vinculante 12 meses después (13 de noviembre de 2025). Sección IV "Principles, Criteria, and Indicators": Principios 1 a 7.', 184, 0)
on conflict (form_key) do nothing;
insert into _h select 'con_migracion', ((select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s) || ':' || (select count(*)::text from compliance.cert_form_defs));
-- Prueba de 20261026019000: con el catálogo al día, la app ya puede respaldar respuestas de los formularios que faltaban.
-- Usa la MISMA función que la app (cert_upsert_response), como un técnico con acceso al grupo. Datos ficticios.
do $prueba$
declare c uuid := gen_random_uuid(); slug text := 'prueba-form-defs'; n int; t text; k text; v uuid; cert jsonb;
begin
  insert into auth.users (id, instance_id, aud, role, email)
    values (c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c-fd@vg.invalid');
  insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values (c, 'eudr', 'field_worker', array[slug], 'active', null)
  on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs, tier = excluded.tier, expires_at = excluded.expires_at;
  select count(*) into n from compliance.cert_form_defs;
  insert into _res values ('01 el catálogo tiene 71 formularios (' || n || '): ' || case when n = 71 then 'OK' else 'FALLA' end);

  -- la certificación de cada formulario se toma ANTES de cambiar al rol de la app (que no lee el esquema compliance)
  select jsonb_object_agg(form_key, certificacion) into cert from compliance.cert_form_defs;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'email', 'c-fd@vg.invalid')::text, true);
  set local role authenticated;
  t := '';
  foreach k in array array['globalgap_fv_smart', 'globalgap_qms', 'rspo_pc_hacienda', 'legacy_cosecha'] loop
    begin
      v := public.cert_upsert_response(jsonb_build_object('local_id', gen_random_uuid(), 'client_slug', slug, 'form_key', k,
             'certificacion', cert->>k, 'finca_id', 'finca-fd',
             'data', jsonb_build_object('prueba', true)));
      t := t || k || ' OK; ';
    exception when others then t := t || k || ' FALLA ' || sqlstate || ' ' || left(sqlerrm, 90) || '; ';
    end;
  end loop;
  reset role;
  insert into _res values ('02 la app respalda IFA Smart, QMS, RSPO y registros de campo: ' || case when t !~ 'FALLA' then 'OK' else t end);
end $prueba$;
delete from compliance.cert_responses where client_slug = 'prueba-form-defs';
-- Reversa de 20261026019000_cert_form_defs_al_dia_con_la_app.sql: quita los 21 formularios agregados, solo si ninguna
-- respuesta los usa (si alguna los usa, la llave foránea lo impide y la reversa falla: es lo correcto).
delete from compliance.cert_form_defs where form_key in ('carbono_arr_mrv', 'globalgap_coc', 'globalgap_fv_gfs', 'globalgap_fv_smart', 'globalgap_qms', 'guia_agrocalidad_registro_operador', 'iscc_eu_hacienda', 'iscc_ish_smallholder', 'legacy_clmrs', 'legacy_cosecha', 'legacy_eudr_check', 'legacy_eudr_finca', 'legacy_fertilizacion', 'legacy_fumigacion', 'legacy_nominas', 'legacy_recoleccion_envase', 'legacy_siembra', 'pefc_cadena_custodia', 'pefc_manejo_forestal', 'rspo_ish_smallholder', 'rspo_pc_hacienda');
insert into _h select 'despues', ((select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance') and p.prokind = 'f' and (n.nspname = 'compliance' or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema = 'compliance'
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname = 'compliance'
) s) || ':' || (select count(*)::text from compliance.cert_form_defs));
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  select count(*) filter (where t !~ 'FALLA') || ' de ' || count(*) || ' OK'
         || coalesce(' · FALLAS: ' || string_agg(t, ' || ' order by t) filter (where t ~ 'FALLA'), '')
    into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, right(a, 12), right(c, 12), right(d, 12),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
