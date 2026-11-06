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
