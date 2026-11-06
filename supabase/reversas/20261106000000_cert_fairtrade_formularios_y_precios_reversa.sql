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
