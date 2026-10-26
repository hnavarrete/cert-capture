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
