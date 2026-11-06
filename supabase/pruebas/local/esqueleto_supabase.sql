-- Esqueleto mínimo de la base erp-agricola para probar la migración Fairtrade EN LOCAL (PGlite), sin tocar producción.
-- Copia, medida el 6-nov-2026 en solo lectura, de lo que la migración usa: roles, esquemas y sus permisos, las columnas
-- de attest.certifications y compliance.cert_form_defs, y la fila «fairtrade» tal como está en producción.
-- No es la base entera: lo que no está aquí (cert_upsert_response, auth.users) la prueba lo salta en local.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create schema auth;
create schema attest;
create schema compliance;

create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claims', true)::json ->> 'sub', '')::uuid $$;

-- Permisos de esquema como en producción: attest con uso para authenticated (no anon); compliance sin uso para la app.
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema attest to authenticated, service_role;
grant usage on schema compliance to service_role;

-- Como en Supabase: lo nuevo en public se puede ejecutar por anon y authenticated salvo que se revoque, y lo nuevo en
-- attest queda con todos los permisos para authenticated (así lo muestra attest.certifications). La migración debe
-- revocar lo que no quiere abierto; este esqueleto lo pone a prueba.
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema attest grant select, insert, update, delete on tables to authenticated, service_role;

create table attest.certifications (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  version text,
  norm_owner text,
  source_ref jsonb not null default '{}'::jsonb,
  country_scope text[],
  metadata jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into attest.certifications (id, code, name, version, norm_owner, source_ref, country_scope, metadata, active, created_at, updated_at)
values ('36145446-5b38-48e5-968f-3c4cd91c9b78', 'fairtrade', 'Fairtrade International - Estandar SPO',
        'SPO v2.x (2019, NEW JAN 2027) / checklist FLOCERT 7.44', 'Fairtrade International (FLO e.V.)',
        '{"cb": "FLOCERT", "file": "fairtrade.html", "tipo": "certificacion_voluntaria"}', array['GLOBAL', 'EC'],
        '{"ranks": ["core", "major", "development", "voluntary", "reactive", "specific", "followup"], "fecha_corte_cacao_cafe": "2018-12-31", "ciclo_productores_anios": 3}',
        true, '2026-07-26T13:08:18.861452+00:00', '2026-07-26T13:08:18.861452+00:00');
alter table attest.certifications enable row level security;
create policy certifications_select on attest.certifications for select to authenticated using (true);

create table compliance.cert_form_defs (
  form_key text primary key,
  certificacion text not null,
  cultivo text,
  titulo text not null,
  schema_version integer not null default 1,
  es_compartido boolean default false,
  es_custom boolean default false,
  programa_owner text,
  legacy boolean default false,
  validation_status text default 'EN_REVISION',
  fuente_normativa text,
  n_campos integer,
  n_control_points integer,
  updated_at timestamptz default now()
);
insert into compliance.cert_form_defs (form_key, certificacion, cultivo, titulo)
values ('eudr_dds', 'EUDR', null, 'Declaración de Diligencia Debida'), ('rspo_pc_hacienda', 'RSPO', 'PALMA_AFRICANA', 'RSPO — P&C');
alter table compliance.cert_form_defs enable row level security;
create policy cert_form_defs_read on compliance.cert_form_defs for select to authenticated using (true);

create table compliance.cert_responses (
  id uuid primary key default gen_random_uuid(),
  form_key text not null references compliance.cert_form_defs (form_key),
  client_slug text
);
