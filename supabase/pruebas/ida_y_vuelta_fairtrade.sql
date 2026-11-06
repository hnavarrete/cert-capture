-- IDA Y VUELTA de Fairtrade (generado por armar_ida_y_vuelta_fairtrade.sh). El RAISE final deshace TODO.
create temp table _res (t text); create temp table _h (cuando text, h text); grant insert, select on _res to authenticated;
insert into _h select 'antes', ((select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance', 'attest') and p.prokind = 'f'
     and (n.nspname in ('compliance', 'attest') or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema in ('compliance', 'attest')
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname in ('compliance', 'attest')
  union all select 'n:form_defs:'||count(*) from compliance.cert_form_defs
  union all select 'c:'||md5(c::text) from attest.certifications c where code = 'fairtrade'
) s));
-- VG Certificaciones · 6-nov-2026 · Fairtrade desde cero: formularios en el catálogo y Precios Mínimos y Primas como DATOS.
-- Compromiso de #05 con #15 (plan de cultivos del 23-oct). Medido el 6-nov, solo lectura: compliance.cert_form_defs tiene
-- 71 formularios y ninguno Fairtrade; attest.certifications ya tiene la fila «fairtrade» (26-jul, solo SPO); no hay
-- respuestas fairtrade_* en compliance.cert_responses ni procesos Fairtrade en attest.certification_processes.
--
-- 1. attest.precio_referencia: Precios Mínimos y Primas con vigencia, fuente (documento, página, URL), fecha de consulta y
--    certeza. NUNCA dentro de un formulario. Solo «verificado» se usa en cálculos (columna usable_en_calculo).
--    Lectura para usuarios con sesión: son datos públicos de Fairtrade International. Nadie escribe desde la app.
-- 2. attest.v_precio_referencia_vigente (security_invoker): lo verificado que rige hoy, para Custody y la app.
-- 3. public.cert_precios_referencia(programa): lo que lee la app (security invoker, search_path vacío).
-- 4. Los 8 formularios Fairtrade en compliance.cert_form_defs: sin ellos cert_upsert_response choca con la llave foránea y
--    la captura se queda solo en el equipo (lección del 26-oct).
-- 5. attest.certifications «fairtrade»: nombre, versión y metadatos al día (SPO + HL). La reversa deja lo de antes.
-- Reversa: supabase/reversas/20261106000000_cert_fairtrade_formularios_y_precios_reversa.sql

-- 1 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
create table attest.precio_referencia (
  id                    text primary key,
  programa              text not null check (programa ~ '^[a-z_]+$'),
  producto              text not null,
  forma                 text,
  calidad               text not null check (calidad in ('convencional', 'organico')),
  origen                text,
  pais                  text,
  alcance               text,
  base                  text,
  punto                 text,
  unidad                text,
  moneda                text,
  precio_minimo         numeric(14, 4) check (precio_minimo >= 0),
  precio_minimo_texto   text,
  prima                 numeric(14, 4) check (prima >= 0),
  prima_porcentaje      numeric(6, 3) check (prima_porcentaje between 0 and 100),
  prima_base            text,
  diferencial_organico  numeric(14, 4) check (diferencial_organico >= 0),
  vigente_desde         date not null,
  vigente_hasta         date check (vigente_hasta >= vigente_desde),
  fuente_documento      text not null,
  fuente_url            text not null check (fuente_url ~ '^https://'),
  consultado_el         date not null,
  certeza               text not null check (certeza in ('verificado', 'parcial', 'por_verificar')),
  usable_en_calculo     boolean generated always as (certeza = 'verificado') stored,
  notas                 text,
  creado_el             timestamptz not null default now(),
  -- lo «por_verificar» no lleva cifras: así no hay manera de usarlo por error
  constraint precio_referencia_sin_cifras_si_por_verificar check (
    certeza <> 'por_verificar' or (precio_minimo is null and prima is null and prima_porcentaje is null and diferencial_organico is null))
);
comment on table attest.precio_referencia is
  'Precios Mínimos y Primas de programas de certificación (hoy Fairtrade), con vigencia, fuente y certeza. Fuente única: '
  'encuestador-eudr/frontend/src/form-schemas/fairtrade/precios_minimos_primas.json. Solo certeza = verificado entra en cálculos.';
create index precio_referencia_busqueda on attest.precio_referencia (programa, producto, vigente_desde);

alter table attest.precio_referencia enable row level security;
-- Lectura para cualquier usuario con sesión: son datos públicos de la tabla oficial de Fairtrade International.
-- anon no lee: la app los trae en su bundle para trabajar sin sesión ni red.
create policy precio_referencia_lectura on attest.precio_referencia for select to authenticated using (true);
revoke all on attest.precio_referencia from anon, authenticated;
grant select on attest.precio_referencia to authenticated;
grant all on attest.precio_referencia to service_role;

-- 2 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
create view attest.v_precio_referencia_vigente with (security_invoker = true) as
  select * from attest.precio_referencia
   where usable_en_calculo
     and vigente_desde <= (now() at time zone 'America/Guayaquil')::date
     and (vigente_hasta is null or vigente_hasta >= (now() at time zone 'America/Guayaquil')::date);
comment on view attest.v_precio_referencia_vigente is 'Precios Mínimos y Primas verificados que rigen hoy (hora de Ecuador).';
revoke all on attest.v_precio_referencia_vigente from anon, authenticated;
grant select on attest.v_precio_referencia_vigente to authenticated;

-- 3 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
create function public.cert_precios_referencia(p_programa text)
returns setof attest.precio_referencia
language sql stable security invoker set search_path = ''
as $$
  select * from attest.precio_referencia
   where programa = p_programa
   order by producto, forma, calidad, base, punto nulls first, vigente_desde;
$$;
comment on function public.cert_precios_referencia(text) is 'La app de Certificaciones lee aquí los Precios Mínimos y Primas (con RLS).';
revoke all on function public.cert_precios_referencia(text) from public, anon;
grant execute on function public.cert_precios_referencia(text) to authenticated;

-- 1 y 4: datos ───────────────────────────────────────────────────────────────────────────────────────────────────
-- >>> DATOS GENERADOS por scripts/sql_fairtrade.py desde src/schemas.bundle.json (no editar a mano)
insert into attest.precio_referencia (id, programa, producto, forma, calidad, origen, pais, alcance, base, punto, unidad, moneda, precio_minimo, precio_minimo_texto, prima, prima_porcentaje, prima_base, diferencial_organico, vigente_desde, vigente_hasta, fuente_documento, fuente_url, consultado_el, certeza, notas)
values
  ('cacao-grano-convencional-mundial_excepto_costa_de_marfil_y_ghana-fob-2019-10-01', 'fairtrade', 'cacao', 'grano', 'convencional', 'Mundial (excepto Costa de Marfil y Ghana)', null, 'SPO', 'FOB', null, 't', 'USD', 2400, null, 240, null, null, null, '2019-10-01', '2025-09-30', 'Anuncio de precios del cacao de Fairtrade International, 30-04-2025 (valor vigente antes del aumento)', 'https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/standards-and-pricing-work-in-progress/cocoa/2025-04-30_Cocoa-Price-Announcement_EN.pdf', '2026-11-06', 'parcial', 'La tabla vigente ya no lista esta fila; el inicio en 2019 se toma de la fila de Ghana. No entra en cálculos.'),
  ('cacao-grano-convencional-mundial_excepto_costa_de_marfil_y_ghana-fob-2025-10-01', 'fairtrade', 'cacao', 'grano', 'convencional', 'Mundial (excepto Costa de Marfil y Ghana)', null, 'SPO', 'FOB', null, 't', 'USD', 3500, null, 240, null, null, null, '2025-10-01', '2026-06-10', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 7', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'Rige para contratos firmados desde el 1-oct-2025.'),
  ('cacao-grano-convencional-mundial_excepto_costa_de_marfil_y_ghana-fob-2026-06-11', 'fairtrade', 'cacao', 'grano', 'convencional', 'Mundial (excepto Costa de Marfil y Ghana)', null, 'SPO', 'FOB', null, 't', 'USD', 3500, null, 275, null, null, null, '2026-06-11', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 7', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('cacao-grano-organico-mundial_excepto_costa_de_marfil_y_ghana-fob-2025-10-01', 'fairtrade', 'cacao', 'grano', 'organico', 'Mundial (excepto Costa de Marfil y Ghana)', null, 'SPO', 'FOB', null, 't', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 240, null, null, 300, '2025-10-01', '2026-06-10', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 8', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('cacao-grano-organico-mundial_excepto_costa_de_marfil_y_ghana-fob-2026-06-11', 'fairtrade', 'cacao', 'grano', 'organico', 'Mundial (excepto Costa de Marfil y Ghana)', null, 'SPO', 'FOB', null, 't', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 275, null, null, 450, '2026-06-11', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 8', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('cafe-arabica_lavado-convencional-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'arabica_lavado', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.8, null, 0.2, null, null, null, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-arabica_lavado-convencional-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'arabica_lavado', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 2, null, 0.2, null, null, null, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9; anuncio de precios del café, 30-07-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5). Rige para contratos firmados desde el 1-dic-2026; los contratos por fijar firmados antes conservan el precio anterior.'),
  ('cafe-arabica_lavado-organico-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'arabica_lavado', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-arabica_lavado-organico-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'arabica_lavado', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-arabica_natural-convencional-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'arabica_natural', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.75, null, 0.2, null, null, null, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-arabica_natural-convencional-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'arabica_natural', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.95, null, 0.2, null, null, null, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9; anuncio de precios del café, 30-07-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5). Rige para contratos firmados desde el 1-dic-2026; los contratos por fijar firmados antes conservan el precio anterior.'),
  ('cafe-arabica_natural-organico-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'arabica_natural', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-arabica_natural-organico-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'arabica_natural', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-robusta_lavado-convencional-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'robusta_lavado', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.25, null, 0.2, null, null, null, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-robusta_lavado-convencional-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'robusta_lavado', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.35, null, 0.2, null, null, null, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9; anuncio de precios del café, 30-07-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5). Rige para contratos firmados desde el 1-dic-2026; los contratos por fijar firmados antes conservan el precio anterior.'),
  ('cafe-robusta_lavado-organico-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'robusta_lavado', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-robusta_lavado-organico-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'robusta_lavado', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-robusta_natural-convencional-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'robusta_natural', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.2, null, 0.2, null, null, null, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-robusta_natural-convencional-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'robusta_natural', 'convencional', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', 1.3, null, 0.2, null, null, null, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 9; anuncio de precios del café, 30-07-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5). Rige para contratos firmados desde el 1-dic-2026; los contratos por fijar firmados antes conservan el precio anterior.'),
  ('cafe-robusta_natural-organico-mundial-fob-2023-08-01', 'fairtrade', 'cafe', 'robusta_natural', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2023-08-01', '2026-11-30', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('cafe-robusta_natural-organico-mundial-fob-2026-12-01', 'fairtrade', 'cafe', 'robusta_natural', 'organico', 'Mundial', null, 'SPO', 'FOB', null, 'lb', 'USD', null, 'Precio Mínimo convencional + diferencial orgánico', 0.2, null, null, 0.4, '2026-12-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, págs. 9-10', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'De la Prima, al menos 0,05 USD/lb van a productividad o calidad (Norma del Café 4.1.5).'),
  ('banano-fresco-convencional-ecuador-exw-2025-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'EXW', null, 'caja 18,14 kg', 'USD', 7.25, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 14', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-exw-2026-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'EXW', null, 'caja 18,14 kg', 'USD', 7.85, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-exw-2027-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'EXW', null, 'caja 18,14 kg', 'USD', 8.3, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-sin_puerto_especificado-2025-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'sin puerto especificado', 'caja 18,14 kg', 'USD', 11.05, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-sin_puerto_especificado-2026-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'sin puerto especificado', 'caja 18,14 kg', 'USD', 11.75, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-guayaquil_desde_santa_elena-2025-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Santa Elena', 'caja 18,14 kg', 'USD', 11.13, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-posorja_desde_santa_elena-2025-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Santa Elena', 'caja 18,14 kg', 'USD', 11.13, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-guayaquil_desde_machala-2025-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Machala', 'caja 18,14 kg', 'USD', 11.37, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-guayaquil_desde_santa_elena-2026-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Santa Elena', 'caja 18,14 kg', 'USD', 11.85, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-posorja_desde_santa_elena-2026-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Santa Elena', 'caja 18,14 kg', 'USD', 11.85, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-guayaquil_desde_machala-2026-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Machala', 'caja 18,14 kg', 'USD', 12.1, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-posorja_desde_machala-2026-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Machala', 'caja 18,14 kg', 'USD', 12.05, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-puerto_bolívar_desde_el_oro-2027-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Puerto Bolívar, desde El Oro', 'caja 18,14 kg', 'USD', 12.25, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-guayaquil_desde_santa_elena_los_ríos_guayas_cañar_o_cotopaxi-2027-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Santa Elena, Los Ríos, Guayas, Cañar o Cotopaxi', 'caja 18,14 kg', 'USD', 12.45, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-posorja_desde_santa_elena_los_ríos_guayas_cañar_o_cotopaxi-2027-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Santa Elena, Los Ríos, Guayas, Cañar o Cotopaxi', 'caja 18,14 kg', 'USD', 12.5, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-guayaquil_desde_el_oro-2027-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde El Oro', 'caja 18,14 kg', 'USD', 12.6, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-convencional-ecuador-fob-posorja_desde_el_oro-2027-01-01', 'fairtrade', 'banano', 'fresco', 'convencional', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde El Oro', 'caja 18,14 kg', 'USD', 12.9, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 15; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-exw-2025-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'EXW', null, 'caja 18,14 kg', 'USD', 9.95, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-exw-2026-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'EXW', null, 'caja 18,14 kg', 'USD', 10.65, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-exw-2027-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'EXW', null, 'caja 18,14 kg', 'USD', 11.15, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-puerto_bolívar-2025-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Puerto Bolívar', 'caja 18,14 kg', 'USD', 13.85, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-puerto_bolívar-2026-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Puerto Bolívar', 'caja 18,14 kg', 'USD', 14.65, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-guayaquil_desde_santa_elena-2025-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Santa Elena', 'caja 18,14 kg', 'USD', 13.93, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-posorja_desde_santa_elena-2025-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Santa Elena', 'caja 18,14 kg', 'USD', 13.93, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-guayaquil_desde_machala-2025-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Machala', 'caja 18,14 kg', 'USD', 14.17, null, 1, null, null, null, '2025-01-01', '2025-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 17', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-guayaquil_desde_santa_elena-2026-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Santa Elena', 'caja 18,14 kg', 'USD', 14.75, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-posorja_desde_santa_elena-2026-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Santa Elena', 'caja 18,14 kg', 'USD', 14.75, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-guayaquil_desde_machala-2026-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Machala', 'caja 18,14 kg', 'USD', 15, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-posorja_desde_machala-2026-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Machala', 'caja 18,14 kg', 'USD', 14.95, null, 1, null, null, null, '2026-01-01', '2026-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-puerto_bolívar_desde_el_oro-2027-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Puerto Bolívar, desde El Oro', 'caja 18,14 kg', 'USD', 15.25, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-guayaquil_desde_santa_elena_los_ríos_guayas_cañar_o_cotopaxi-2027-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde Santa Elena, Los Ríos, Guayas, Cañar o Cotopaxi', 'caja 18,14 kg', 'USD', 15.4, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-posorja_desde_santa_elena_los_ríos_guayas_cañar_o_cotopaxi-2027-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde Santa Elena, Los Ríos, Guayas, Cañar o Cotopaxi', 'caja 18,14 kg', 'USD', 15.45, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-guayaquil_desde_el_oro-2027-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Guayaquil, desde El Oro', 'caja 18,14 kg', 'USD', 15.6, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-fresco-organico-ecuador-fob-posorja_desde_el_oro-2027-01-01', 'fairtrade', 'banano', 'fresco', 'organico', 'Ecuador', 'Ecuador', 'SPO/HL', 'FOB', 'Posorja, desde El Oro', 'caja 18,14 kg', 'USD', 15.85, null, 1, null, null, null, '2027-01-01', '2027-12-31', 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 18; anuncio del precio del banano, 05-10-2026', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('banano-salario_digno_referencia-convencional-ecuador-exw-2027-01-01', 'fairtrade', 'banano', 'salario_digno_referencia', 'convencional', 'Ecuador', 'Ecuador', 'HL', 'EXW', null, 'caja 18,14 kg', 'USD', null, null, null, null, null, null, '2027-01-01', null, 'Precios de referencia de salario digno del banano (LWRP) 2027, listados en los anuncios de Fairtrade International', 'https://www.fairtrade.net/en/standard/minimum-price-info.html', '2026-11-06', 'por_verificar', 'Se vio en el listado de anuncios pero no se leyó el documento. Sin cifra; no entra en cálculos.'),
  ('flores-tallos-convencional-mundial-fob-2008-10-31', 'fairtrade', 'flores', 'tallos', 'convencional', 'Mundial', null, 'HL', 'FOB', null, 'tallo', null, null, 'Sin Precio Mínimo: precio comercial negociado', null, 10, 'precio comercial FOB', null, '2008-10-31', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('flores-tallos-convencional-mundial-subasta-2023-10-15', 'fairtrade', 'flores', 'tallos', 'convencional', 'Mundial', null, 'HL', 'subasta', null, 'tallo', null, null, 'Precio bruto de venta en subasta (reloj)', null, 6, 'precio bruto de venta en subasta', null, '2023-10-15', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('flores-ramos-convencional-mundial-fob-2008-10-31', 'fairtrade', 'flores', 'ramos', 'convencional', 'Mundial', null, 'HL', 'FOB', null, 'ramo', null, null, 'Sin Precio Mínimo: precio comercial negociado', null, 10, 'precio comercial FOB', null, '2008-10-31', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('flores-ramos-convencional-mundial-subasta-2023-10-15', 'fairtrade', 'flores', 'ramos', 'convencional', 'Mundial', null, 'HL', 'subasta', null, 'ramo', null, null, 'Precio bruto de venta en subasta (reloj)', null, 6, 'precio bruto de venta en subasta', null, '2023-10-15', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('flores-bouquets-convencional-mundial-fob-2008-10-31', 'fairtrade', 'flores', 'bouquets', 'convencional', 'Mundial', null, 'HL', 'FOB', null, 'bouquet', null, null, 'Sin Precio Mínimo: precio comercial negociado', null, 10, 'precio comercial FOB', null, '2008-10-31', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('flores-bouquets-convencional-mundial-subasta-2023-10-15', 'fairtrade', 'flores', 'bouquets', 'convencional', 'Mundial', null, 'HL', 'subasta', null, 'bouquet', null, null, 'Precio bruto de venta en subasta (reloj)', null, 6, 'precio bruto de venta en subasta', null, '2023-10-15', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null),
  ('flores-plantas_en_maceta-convencional-mundial-fob-2008-10-31', 'fairtrade', 'flores', 'plantas_en_maceta', 'convencional', 'Mundial', null, 'HL', 'FOB', null, 'unidad', null, null, 'Sin Precio Mínimo: precio comercial negociado', null, 10, 'precio comercial FOB', null, '2008-10-31', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', 'Incluye plantas de jardín y bulbos.'),
  ('flores-material_vegetal_joven-convencional-mundial-fob-2022-11-01', 'fairtrade', 'flores', 'material_vegetal_joven', 'convencional', 'Mundial', null, 'HL', 'FOB', null, 'unidad', 'EUR', null, 'Sin Precio Mínimo: precio comercial negociado', 0.01, null, null, null, '2022-11-01', null, 'Fairtrade Minimum Price and Fairtrade Premium Table, versión 05/10/2026, pág. 12', 'https://www.fairtrade.net/content/dam/fairtrade/global/minimum-price-table/Fairtrade_Minimum_Price_and_Premium_Table_EN_PUBLIC.pdf', '2026-11-06', 'verificado', null)
on conflict (id) do nothing;

insert into compliance.cert_form_defs (form_key, certificacion, cultivo, titulo, schema_version, es_compartido, es_custom,
                                       programa_owner, legacy, validation_status, fuente_normativa, n_campos, n_control_points)
values
  ('fairtrade_hl_empresa', 'FAIRTRADE', 'MULTI', 'Fairtrade — Empresa con trabajo contratado (norma HL)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para Trabajo Contratado (Fairtrade Hired Labour Standard), versión 16.04.2024_v2.4; v2.0 del 16-04-2024, aplica desde el 1-ene-2025; marcados NEW 2025* desde el 1-ene-2026 y NEW 2025** / NEW JAN 2027 desde el 1-ene-2027; último cambio el 30-06-2026 (4.2.1, 6.1.4 y requisito nuevo 6.3.5). PDF oficial: https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/hired-labour-/HL_EN.pdf (consultado el 2026-11-06). Próxima revisión: 2029.', 202, 189),
  ('fairtrade_prima_plan', 'FAIRTRADE', 'MULTI', 'Fairtrade — Plan de Desarrollo y uso de la Prima', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para Organizaciones de Pequeños Productores 03.04.2019_v2.10, sección 4.1 (Plan de Desarrollo Fairtrade y Prima); Norma Fairtrade para Trabajo Contratado 16.04.2024_v2.4, sección 2.1 (Comité y Plan de la Prima); Norma Fairtrade para Flores y Plantas 15.10.2023_v2.9, 2.1.2 a 2.1.6; Norma Fairtrade para el Café 15.07.2021_v.2.12, 4.1.5. Consultadas el 2026-11-06.', 68, 0),
  ('fairtrade_producto_banano', 'FAIRTRADE', 'BANANO', 'Fairtrade — Criterios del banano (pequeños productores o plantación)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para Frutas y Verduras (organizaciones de pequeños productores), versión 31.03.2026_v1.01 (rige desde el 1-ene-2027; hasta el 31-dic-2026 rige Fruta Fresca SPO 01.04.2018_v2.6): https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/small-scale-producer/fresh-veggies/Fruits_Vegetables_SPO_EN.pdf · Norma Fairtrade para Frutas y Verduras (organizaciones de trabajo contratado), versión 31.03.2026_v1.01 (rige desde el 1-ene-2027; hasta el 31-dic-2026 rige Fruta Fresca HL 01.04.2018_v2.8): https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/specific-products/Fruits_Vegetables_HLO_EN.pdf (consultadas el 2026-11-06).', 24, 18),
  ('fairtrade_producto_cacao', 'FAIRTRADE', 'CACAO', 'Fairtrade — Criterios del cacao (pequeños productores)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para el Cacao, versión 27.09.2023_v.2.15: https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards-spo-cocoa/Cocoa_SPO_EN.pdf (consultadas el 2026-11-06).', 40, 35),
  ('fairtrade_producto_cafe', 'FAIRTRADE', 'CAFE', 'Fairtrade — Criterios del café (pequeños productores)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para el Café, versión 15.07.2021_v.2.12: https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/small-scale-producer/coffee/Coffee_SPO_EN.pdf (consultadas el 2026-11-06).', 21, 16),
  ('fairtrade_producto_flores', 'FAIRTRADE', 'FLORES', 'Fairtrade — Criterios de flores y plantas (trabajo contratado)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para Flores y Plantas, versión 15.10.2023_v2.9: https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/hired-labour-/flowers-plants/Flowers%20and%20Plants%20Standard_EN.pdf (consultadas el 2026-11-06).', 43, 38),
  ('fairtrade_spo_miembro', 'FAIRTRADE', 'MULTI', 'Fairtrade — Inspección interna del miembro (finca)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para Organizaciones de Pequeños Productores 03.04.2019_v2.10; Norma Fairtrade para el Cacao 27.09.2023_v.2.15; Norma Fairtrade para el Café 15.07.2021_v.2.12; Norma Fairtrade para Frutas y Verduras (organizaciones de pequeños productores) 31.03.2026_v1.01 (rige desde el 1-ene-2027; hasta el 31-dic-2026 rige Fruta Fresca SPO 01.04.2018_v2.6). Consultadas el 2026-11-06.', 46, 0),
  ('fairtrade_spo_organizacion', 'FAIRTRADE', 'MULTI', 'Fairtrade — Organización de pequeños productores (norma SPO)', 1, false, false, null, false, 'EN_REVISION', 'Norma Fairtrade para Organizaciones de Pequeños Productores (Fairtrade Standard for Small-scale Producer Organizations), versión 03.04.2019_v2.10; base publicada el 03-04-2019, último cambio el 30-06-2026 (2.1.7 y requisito nuevo 2.3.5, marcado NEW JAN 2027). PDF oficial: https://www.fairtrade.net/content/dam/fairtrade/fairtrade-international/standards/small-scale-producer/SPO_EN.pdf (consultado el 2026-11-06). La revisión de fondo (proyecto STEP) se publicará en 2027 y se certificará desde 2028.', 162, 151)
on conflict (form_key) do nothing;
-- <<< FIN DE LOS DATOS GENERADOS

-- 5 ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Solo si la fila sigue como la dejó el alta del 26-jul (si alguien la cambió, no se pisa).
update attest.certifications
   set name = 'Fairtrade International - Pequeños Productores (SPO) y Trabajo Contratado (HL)',
       version = 'SPO 03.04.2019_v2.10 / HL 16.04.2024_v2.4 (vigentes al 6-nov-2026) / checklist FLOCERT 7.44',
       metadata = metadata || jsonb_build_object(
         'normas', jsonb_build_object(
           'spo', '03.04.2019_v2.10', 'hl', '16.04.2024_v2.4', 'cacao', '27.09.2023_v.2.15', 'cafe', '15.07.2021_v.2.12',
           'banano', 'Frutas y Verduras 31.03.2026_v1.01 (desde 1-ene-2027)', 'flores', '15.10.2023_v2.9',
           'consultado_el', '2026-11-06'),
         'formularios_app', 'fairtrade_* (8)',
         'precios', 'attest.precio_referencia'),
       updated_at = now()
 where code = 'fairtrade'
   and version = 'SPO v2.x (2019, NEW JAN 2027) / checklist FLOCERT 7.44';
insert into _h select 'con_migracion', ((select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance', 'attest') and p.prokind = 'f'
     and (n.nspname in ('compliance', 'attest') or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema in ('compliance', 'attest')
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname in ('compliance', 'attest')
  union all select 'n:form_defs:'||count(*) from compliance.cert_form_defs
  union all select 'c:'||md5(c::text) from attest.certifications c where code = 'fairtrade'
) s));
-- Prueba de 20261106000000 (Fairtrade). Escribe cada resultado en _res; el armador decide al final. Datos ficticios.
-- Corre igual en la base local (PGlite con el esqueleto de supabase/pruebas/local/) y, si Henrry lo autoriza, en la
-- ida y vuelta de producción (todo dentro de una transacción que se deshace con el RAISE final).
do $prueba$
declare a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); n int; m int; t text; ok boolean;
begin
  -- 01-02 catálogo y datos
  select count(*) into n from compliance.cert_form_defs where certificacion = 'FAIRTRADE';
  insert into _res values ('01 los 8 formularios Fairtrade están en el catálogo (' || n || '): ' || case when n = 8 then 'OK' else 'FALLA' end);
  select count(*), count(*) filter (where certeza <> 'verificado') into n, m from attest.precio_referencia where programa = 'fairtrade';
  insert into _res values ('02 64 precios, 2 no verificados (' || n || ', ' || m || '): ' || case when n = 64 and m = 2 then 'OK' else 'FALLA' end);
  select count(*) into n from attest.precio_referencia where not usable_en_calculo and (precio_minimo is not null or prima is not null) and certeza = 'por_verificar';
  insert into _res values ('03 lo por verificar no trae cifras: ' || case when n = 0 then 'OK' else 'FALLA' end);

  -- 04 la restricción impide cargar cifras en algo por verificar (como dueño de la tabla)
  begin
    insert into attest.precio_referencia (id, programa, producto, calidad, vigente_desde, fuente_documento, fuente_url, consultado_el, certeza, prima)
      values ('prueba-x', 'fairtrade', 'cacao', 'convencional', '2026-01-01', 'x', 'https://x', '2026-11-06', 'por_verificar', 1);
    insert into _res values ('04 una fila por verificar con cifra se rechaza: FALLA (entró)');
  exception when check_violation then insert into _res values ('04 una fila por verificar con cifra se rechaza: OK');
  end;

  -- 05-08 usuario A y usuario B con sesión: los dos leen lo mismo; ninguno escribe
  foreach t in array array[a::text, b::text] loop
    perform set_config('request.jwt.claims', json_build_object('sub', t, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into n from attest.precio_referencia;
    select count(*) into m from public.cert_precios_referencia('fairtrade');
    reset role;
    insert into _res values ('05 usuario ' || case when t = a::text then 'A' else 'B' end || ' lee 64 filas en la tabla y por la función (' || n || ', ' || m || '): '
      || case when n = 64 and m = 64 then 'OK' else 'FALLA' end);
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*), bool_and(usable_en_calculo) into n, ok from attest.v_precio_referencia_vigente;
  reset role;
  insert into _res values ('06 la vista de vigentes solo da lo verificado (' || n || ' filas): ' || case when n > 0 and ok then 'OK' else 'FALLA' end);
  set local role authenticated;
  begin
    update attest.precio_referencia set prima = 0 where programa = 'fairtrade';
    reset role; insert into _res values ('07 un usuario con sesión no puede cambiar un precio: FALLA (pudo)');
  exception when insufficient_privilege then reset role; insert into _res values ('07 un usuario con sesión no puede cambiar un precio: OK');
  end;
  set local role authenticated;
  begin
    insert into attest.precio_referencia (id, programa, producto, calidad, vigente_desde, fuente_documento, fuente_url, consultado_el, certeza)
      values ('prueba-y', 'fairtrade', 'cacao', 'convencional', '2026-01-01', 'x', 'https://x', '2026-11-06', 'verificado');
    reset role; insert into _res values ('08 un usuario con sesión no puede agregar precios: FALLA (pudo)');
  exception when insufficient_privilege then reset role; insert into _res values ('08 un usuario con sesión no puede agregar precios: OK');
  end;

  -- 09 sin sesión (anon) no lee
  set local role anon;
  begin
    select count(*) into n from attest.precio_referencia;
    reset role; insert into _res values ('09 sin sesión no se lee la tabla: FALLA (leyó ' || n || ')');
  exception when insufficient_privilege then reset role; insert into _res values ('09 sin sesión no se lee la tabla: OK');
  end;
  set local role anon;
  begin
    perform public.cert_precios_referencia('fairtrade');
    reset role; insert into _res values ('10 sin sesión no se ejecuta la función: FALLA (se ejecutó)');
  exception when insufficient_privilege then reset role; insert into _res values ('10 sin sesión no se ejecuta la función: OK');
  end;

  -- 11-12 seguridad de fábrica: función invoker con search_path vacío; vista con security_invoker
  select not p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=""%' into ok
    from pg_proc p where p.oid = 'public.cert_precios_referencia(text)'::regprocedure;
  insert into _res values ('11 la función es security invoker con search_path vacío: ' || case when ok then 'OK' else 'FALLA' end);
  select coalesce(array_to_string(c.reloptions, ','), '') like '%security_invoker=true%' into ok
    from pg_class c where c.oid = 'attest.v_precio_referencia_vigente'::regclass;
  insert into _res values ('12 la vista tiene security_invoker: ' || case when ok then 'OK' else 'FALLA' end);
  select relrowsecurity into ok from pg_class where oid = 'attest.precio_referencia'::regclass;
  insert into _res values ('13 la tabla tiene RLS: ' || case when ok then 'OK' else 'FALLA' end);

  -- 14 la fila de la certificación quedó al día
  select version like 'SPO 03.04.2019_v2.10 / HL 16.04.2024_v2.4%' and metadata ? 'normas' into ok from attest.certifications where code = 'fairtrade';
  insert into _res values ('14 attest.certifications fairtrade con SPO v2.10 y HL v2.4: ' || case when ok then 'OK' else 'FALLA' end);

  -- 15 (solo donde existe la función de la app) la app respalda una respuesta de un formulario Fairtrade
  if to_regprocedure('public.cert_upsert_response(jsonb)') is not null then
    insert into auth.users (id, instance_id, aud, role, email)
      values (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ft-a@vg.invalid');
    insert into public.user_products (user_id, product, role, client_slugs, tier, expires_at) values (a, 'eudr', 'field_worker', array['prueba-fairtrade'], 'active', null)
    on conflict (user_id, product) do update set role = excluded.role, client_slugs = excluded.client_slugs, tier = excluded.tier, expires_at = excluded.expires_at;
    perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'email', 'ft-a@vg.invalid')::text, true);
    set local role authenticated;
    begin
      perform public.cert_upsert_response(jsonb_build_object('local_id', gen_random_uuid(), 'client_slug', 'prueba-fairtrade',
        'form_key', 'fairtrade_spo_miembro', 'certificacion', 'FAIRTRADE', 'finca_id', 'finca-ft', 'data', jsonb_build_object('prueba', true)));
      reset role; insert into _res values ('15 la app respalda una inspección interna Fairtrade: OK');
    exception when others then reset role; insert into _res values ('15 la app respalda una inspección interna Fairtrade: FALLA ' || sqlstate || ' ' || left(sqlerrm, 90));
    end;
  end if;
end $prueba$;
delete from compliance.cert_responses where client_slug = 'prueba-fairtrade';
-- Reversa de 20261106000000_cert_fairtrade_formularios_y_precios.sql: deja la base como estaba antes.
-- Si ya hay respuestas capturadas en algún formulario Fairtrade, NO borra su definición (se perderían las capturas
-- por la llave foránea): se detiene y lo dice.
do $r$
begin
  if exists (select 1 from compliance.cert_responses where form_key like 'fairtrade\_%') then
    raise exception 'Hay respuestas de formularios Fairtrade en compliance.cert_responses: la reversa no las borra. Revisar antes.';
  end if;
end $r$;

-- 5. La fila «fairtrade» vuelve a como la dejó el alta del 26-jul (solo si la cambió esta migración).
update attest.certifications
   set name = 'Fairtrade International - Estandar SPO',
       version = 'SPO v2.x (2019, NEW JAN 2027) / checklist FLOCERT 7.44',
       metadata = metadata - 'normas' - 'formularios_app' - 'precios',
       updated_at = '2026-07-26T13:08:18.861452+00:00'
 where code = 'fairtrade'
   and version = 'SPO 03.04.2019_v2.10 / HL 16.04.2024_v2.4 (vigentes al 6-nov-2026) / checklist FLOCERT 7.44';

-- 4. Los 8 formularios salen del catálogo.
delete from compliance.cert_form_defs
 where form_key in ('fairtrade_spo_organizacion', 'fairtrade_spo_miembro', 'fairtrade_hl_empresa', 'fairtrade_prima_plan',
                    'fairtrade_producto_cacao', 'fairtrade_producto_cafe', 'fairtrade_producto_banano', 'fairtrade_producto_flores');

-- 3, 2 y 1.
drop function if exists public.cert_precios_referencia(text);
drop view if exists attest.v_precio_referencia_vigente;
drop table if exists attest.precio_referencia;
insert into _h select 'despues', ((select md5(string_agg(x, '|' order by x)) from (
  select 'f:'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||md5(pg_get_functiondef(p.oid)) x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'compliance', 'attest') and p.prokind = 'f'
     and (n.nspname in ('compliance', 'attest') or p.proname like 'cert\_%')
  union all select 't:'||table_schema||'.'||table_name from information_schema.tables where table_schema in ('compliance', 'attest')
  union all select 'p:'||schemaname||'.'||tablename||'.'||policyname||md5(coalesce(qual,'')||coalesce(with_check,'')) from pg_policies where schemaname in ('compliance', 'attest')
  union all select 'n:form_defs:'||count(*) from compliance.cert_form_defs
  union all select 'c:'||md5(c::text) from attest.certifications c where code = 'fairtrade'
) s));
do $f$ declare a text; c text; d text; r text; begin
  select h into a from _h where cuando = 'antes'; select h into c from _h where cuando = 'con_migracion'; select h into d from _h where cuando = 'despues';
  select count(*) filter (where t !~ 'FALLA') || ' de ' || count(*) || ' OK'
         || coalesce(' · FALLAS: ' || string_agg(t, ' || ' order by t) filter (where t ~ 'FALLA'), '')
    into r from _res;
  raise exception 'RESULTADO % ### REVERSA: antes=% con_migracion=% despues=% → %', r, right(a, 12), right(c, 12), right(d, 12),
    case when a = d and a <> c then 'IGUAL (OK)' else 'DISTINTA (FALLA)' end;
end $f$;
