"""Pruebas del respaldo en el servidor, de retomar desde otro equipo y del registro encadenado (6-oct-2026).

SIN cuentas reales y SIN escribir en producción: toda llamada a Supabase se INTERCEPTA (page.route) y se contesta
aquí, con la forma exacta del contrato de la base (migración 20261006003000). La sesión se simula en el navegador
con un token de prueba que no sirve fuera de esta prueba. Si la app intentara llegar a la red real, la petición se
corta y la prueba lo cuenta como fallo.

Casos: (a) respaldo correcto · (b) error <null> y sin finca · (c) sin red · (d) otro equipo: el equipo vacío se
llena con 2 versiones del servidor, con evidencias por URL firmada · (e) registro encadenado íntegro y roto ·
(f) sellada: se respalda como versión nueva · (g) modo demo: ni una llamada.

Uso:  npx vite build  y luego  python pruebas/respaldo_servidor.py   (levanta y cierra su propio vite preview)
Capturas en pruebas/capturas/ (fuera del paquete web).
"""
import base64, json, os, re, subprocess, sys, time, urllib.request
from playwright.sync_api import sync_playwright

AQUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUERTO = 4179
APP = f'http://localhost:{PUERTO}/'
SUPA = 'https://fcahhxxzhsfdqqhhdrcl.supabase.co'
CLAVE_SESION = 'sb-fcahhxxzhsfdqqhhdrcl-auth-token'
CAPTURAS = os.path.join(AQUI, 'pruebas', 'capturas')
MUESTRA_PDF = os.path.join(AQUI, 'ayuda-flujos', 'flujos', 'muestras', 'procedimiento-capacitacion.pdf')
FINCA = 'finca-prueba'
FORM = 'globalgap_fv_smart'
FV_SMART = 'GLOBAL G.A.P. - IFA Fruta y Verdura (edicion Smart)'
PNG_1PX = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')

sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def b64u(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip('=')


def sesion_de_prueba():
    """Sesión SIMULADA: un JWT de prueba sin firma válida. Solo existe en este navegador de prueba."""
    exp = int(time.time()) + 7 * 24 * 3600
    usuario = {'id': '00000000-0000-4000-8000-000000000001', 'aud': 'authenticated', 'role': 'authenticated',
               'email': 'prueba@ejemplo.test', 'app_metadata': {'provider': 'email'}, 'user_metadata': {},
               'created_at': '2026-10-06T00:00:00Z'}
    token = b64u({'alg': 'HS256', 'typ': 'JWT'}) + '.' + b64u({'sub': usuario['id'], 'role': 'authenticated',
                                                                'aud': 'authenticated', 'exp': exp, 'email': usuario['email']}) + '.prueba'
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': 7 * 24 * 3600, 'expires_at': exp,
            'refresh_token': 'prueba-refresh', 'user': usuario}


class Servidor:
    """Contesta las llamadas a Supabase. `upsert` es una función (payload, n) -> (status, cuerpo) o 'cortar'."""

    def __init__(self, upsert=None, mis=None, cadena=None):
        self.upsert = upsert or (lambda p, n: (200, '"11111111-1111-4111-8111-%012d"' % n))
        self.mis = mis if mis is not None else []
        self.cadena = cadena or {'ok': True, 'broken_at': None, 'total': 0}
        self.llamadas, self.payloads, self.subidas, self.firmadas, self.inesperadas = [], [], [], [], []

    def atender(self, route):
        req = route.request
        url = req.url
        ruta = url[len(SUPA):]
        self.llamadas.append(f'{req.method} {ruta.split("?")[0]}')
        js = lambda cuerpo, status=200: route.fulfill(status=status, content_type='application/json', body=cuerpo if isinstance(cuerpo, str) else json.dumps(cuerpo))
        if ruta.startswith('/rest/v1/rpc/'):
            nombre = ruta[len('/rest/v1/rpc/'):].split('?')[0]
            cuerpo = json.loads(req.post_data or '{}')
            if nombre == 'my_products':
                return js([{'product': 'eudr', 'client_slugs': [FINCA], 'role': 'tecnico', 'module_flags': []}])
            if nombre == 'get_my_profile':
                return js([{'has_profile': True}])
            if nombre == 'cert_upsert_response':
                p = cuerpo.get('p') or {}
                self.payloads.append(p)
                r = self.upsert(p, len(self.payloads))
                if r == 'cortar':
                    return route.abort('internetdisconnected')
                return js(r[1], r[0])
            if nombre == 'cert_mis_respuestas':
                return js(self.mis)
            if nombre == 'cert_verificar_cadena':
                return js([self.cadena])
        if ruta.startswith('/storage/v1/object/sign/'):
            if req.method == 'POST':
                camino = ruta[len('/storage/v1/object/sign/'):].split('?')[0]
                self.firmadas.append(camino)
                return js({'signedURL': f'/object/sign/{camino}?token=prueba-firmada'})
            camino = ruta.split('?')[0]
            if camino.endswith('.png'):
                return route.fulfill(status=200, content_type='image/png', body=PNG_1PX)
            return route.fulfill(status=200, content_type='application/pdf', body=b'%PDF-1.4\n%%EOF\n')
        if ruta.startswith('/storage/v1/object/cert-evidencias/'):
            self.subidas.append(ruta.split('?')[0])
            return js({'Key': ruta[len('/storage/v1/object/'):], 'Id': '22222222-2222-4222-8222-222222222222'})
        if ruta.startswith('/auth/v1/user'):
            return js(sesion_de_prueba()['user'])
        self.inesperadas.append(f'{req.method} {ruta}')
        return route.fulfill(status=404, content_type='application/json', body='{"message":"no contemplado en la prueba"}')


RESULTADOS = []


def caso(nombre, ok, visto):
    RESULTADOS.append((nombre, ok, visto))
    print(('OK   ' if ok else 'FALLA') + f' {nombre}: {visto}', flush=True)


def abrir(pw, servidor, *, sesion=True, slug=FINCA, demo=False, redes=True, ancho=414, alto=860):
    nav = pw.chromium.launch()
    ctx = nav.new_context(viewport={'width': ancho, 'height': alto}, locale='es-EC', service_workers='block')
    pagina = ctx.new_page()
    pagina.on('pageerror', lambda e: print('   [error de página]', str(e)[:200]))
    # todo lo que vaya a Supabase lo contesta la prueba; nada sale a la red real
    ctx.route(f'{SUPA}/**', servidor.atender)
    ctx.route('https://www.visiongeografica.com/**', lambda r: r.fulfill(status=200, content_type='text/css', body=''))
    sesion_js = json.dumps(sesion_de_prueba()) if sesion else 'null'
    pagina.add_init_script(f"""(() => {{
      if (sessionStorage.getItem('__prep')) return; sessionStorage.setItem('__prep', '1');
      localStorage.clear();
      const s = {sesion_js}; if (s) localStorage.setItem('{CLAVE_SESION}', JSON.stringify(s));
      localStorage.setItem('vg_slug', {json.dumps(slug)});
    }})()""")
    pagina.goto(APP + ('?demo=1' if demo else ''))
    return nav, pagina


def abrir_formulario(pagina):
    pagina.get_by_role('button', name='GLOBAL G.A.P.', exact=False).first.click()
    pagina.locator(f'button:has-text("{FV_SMART}")').first.click()
    pagina.wait_for_selector('.vg-certform-head', timeout=15000)


def guardar_con_evidencia(pagina):
    pagina.get_by_label('Respuesta FV-Smart 03.02').select_option('cumple')
    pagina.set_input_files('.vg-foto-box:has(input[data-field="sec_3.fv_smart_03_02__evidencia"]) input[type=file]', MUESTRA_PDF)
    pagina.get_by_role('button', name='Guardar (offline)').click()


def barra(pagina):
    el = pagina.locator('.respaldo')
    return el.get_attribute('data-respaldo'), el.inner_text().replace('\n', ' · ')


def esperar_barra(pagina, texto, ms=15000):
    pagina.locator('.respaldo', has_text=texto).wait_for(timeout=ms)


def captura(pagina, nombre):
    os.makedirs(CAPTURAS, exist_ok=True)
    pagina.evaluate('window.scrollTo(0, 0)')
    pagina.screenshot(path=os.path.join(CAPTURAS, nombre))


def prueba_a(pw):
    s = Servidor()
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, '1 respaldada')
        nivel, txt = barra(p)
        pl = s.payloads[-1] if s.payloads else {}
        hash_ok = bool(re.fullmatch(r'[0-9a-f]{64}', pl.get('audit_hash') or ''))
        tiene_prev = 'prev_hash' in pl
        foto_ok = bool(pl.get('fotos')) and pl['fotos'][0].get('path', '').startswith(FINCA + '/')
        captura(p, 'a-respaldo-correcto.png')
        caso('(a) respaldo correcto', nivel == 'ok' and '1 respaldada' in txt and hash_ok and tiene_prev and foto_ok
             and pl.get('client_slug') == FINCA and len(s.subidas) == 1 and not s.inesperadas,
             f'barra «{txt}» [{nivel}] · payload client_slug={pl.get("client_slug")} audit_hash={"64 hex" if hash_ok else pl.get("audit_hash")} '
             f'prev_hash presente={tiene_prev} · evidencia subida={len(s.subidas)} con ruta {pl.get("fotos", [{}])[0].get("path", "")[:40]}…')
    finally:
        nav.close()


def prueba_b(pw):
    err = {'code': '42501', 'details': None, 'hint': None, 'message': 'sin grant eudr de escritura para el client_slug <null>'}
    s = Servidor(upsert=lambda pl, n: (403, err))
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, 'Elija su finca para respaldar')
        nivel, txt = barra(p)
        captura(p, 'b-sin-finca-null.png')
        caso('(b) error <null> del servidor', nivel == 'warn' and '1 pendiente' in txt and len(s.payloads) >= 1,
             f'barra «{txt}» [{nivel}] · llamadas a cert_upsert_response={len(s.payloads)}')
    finally:
        nav.close()
    # sin finca elegida: ni se intenta (ni bucket ni RPC)
    s2 = Servidor()
    nav, p = abrir(pw, s2, slug='')
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, 'Elija su finca para respaldar')
        nivel, txt = barra(p)
        boton = p.locator('.respaldo .respaldo-btn', has_text='Elegir finca').count()
        caso('(b2) sin finca elegida', nivel == 'warn' and not s2.payloads and not s2.subidas and boton == 1,
             f'barra «{txt}» [{nivel}] · intentos de subida={len(s2.payloads) + len(s2.subidas)}')
    finally:
        nav.close()


def prueba_c(pw):
    s = Servidor(upsert=lambda pl, n: 'cortar')
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, 'Sin conexión: se respaldará al volver')
        nivel, txt = barra(p)
        captura(p, 'c-sin-red.png')
        caso('(c) sin red (la petición no llega)', 'Sin conexión' in txt and '1 pendiente' in txt and 'Respaldar ahora' in txt,
             f'barra «{txt}» [{nivel}]')
        # y modo avión: el navegador dice que no hay red
        p.evaluate("Object.defineProperty(Navigator.prototype,'onLine',{get:()=>false,configurable:true});window.dispatchEvent(new Event('offline'))")
        p.wait_for_timeout(300)
        nivel, txt = barra(p)
        caso('(c2) modo avión', 'Sin conexión: se respaldará al volver' in txt, f'barra «{txt}» [{nivel}]')
    finally:
        nav.close()


def versiones_del_servidor():
    v1, v2 = 'aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000002'
    pdf = {'field': 'sec_3.fv_smart_03_02__evidencia', 'path': f'{FINCA}/{v1}/sec_3.fv_smart_03_02__evidencia_p1.pdf',
           'photo_id': 'p1-procedimiento', 'bucket': 'cert-evidencias', 'name': 'procedimiento-capacitacion.pdf', 'mime': 'application/pdf'}
    png = {'field': 'sec_11.fv_smart_11_01__evidencia', 'path': f'{FINCA}/{v2}/sec_11.fv_smart_11_01__evidencia_p2.png',
           'photo_id': 'p2-foto', 'bucket': 'cert-evidencias', 'name': 'foto-bodega.png', 'mime': 'image/png'}
    comun = {'client_slug': FINCA, 'form_key': FORM, 'certificacion': 'GLOBAL_GAP', 'producer_id': None, 'finca_id': None,
             'lote_id': None, 'poligono_id': None, 'estado': 'completado', 'audit_timestamp_seal': 'f' * 64}
    return [
        dict(comun, id='bbbbbbbb-0000-4000-8000-000000000001', local_id=v1, audit_chain_seq=1, content_hash='c' * 64,
             audit_hash='a' * 64, prev_hash=None, timestamp_creacion='2026-10-04T15:00:00Z', created_at='2026-10-04T15:00:05Z',
             data={'sec_3.fv_smart_03_01.estado': 'cumple', 'sec_3.fv_smart_03_02.estado': 'cumple',
                   'sec_3.fv_smart_03_02__evidencia': 'procedimiento-capacitacion.pdf'}, fotos=[pdf]),
        dict(comun, id='bbbbbbbb-0000-4000-8000-000000000002', local_id=v2, audit_chain_seq=2, content_hash='d' * 64,
             audit_hash='b' * 64, prev_hash='a' * 64, timestamp_creacion='2026-10-05T16:30:00Z', created_at='2026-10-05T16:30:04Z',
             data={'__version_de': v1, 'sec_3.fv_smart_03_01.estado': 'cumple', 'sec_3.fv_smart_03_02.estado': 'cumple',
                   'sec_3.fv_smart_03_02__evidencia': 'procedimiento-capacitacion.pdf', 'sec_3.fv_smart_03_03.estado': 'na',
                   'sec_11.fv_smart_11_01.estado': 'cumple', 'sec_11.fv_smart_11_01__evidencia': 'foto-bodega.png'},
             fotos=[pdf, png]),
    ]


def prueba_d_e(pw):
    s = Servidor(mis=versiones_del_servidor(), cadena={'ok': True, 'broken_at': None, 'total': 2})
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        p.locator('.vg-retomado').wait_for(timeout=15000)
        retomado = p.locator('.vg-retomado').inner_text()
        v0301 = p.get_by_label('Respuesta FV-Smart 03.01').input_value()
        v0303 = p.get_by_label('Respuesta FV-Smart 03.03').input_value()
        p.locator('.vg-foto-item.guardado', has_text='procedimiento-capacitacion.pdf').wait_for(timeout=10000)
        ver = p.locator('.vg-foto-item.guardado', has_text='procedimiento-capacitacion.pdf').locator('a.vg-foto-ver')
        ver.wait_for(timeout=10000)
        href = ver.get_attribute('href') or ''
        p.locator('h3.vg-seccion-head', has_text='FV-Smart 11').click()
        img = p.locator('.vg-foto-item.guardado', has_text='foto-bodega.png').locator('img.vg-foto-prev')
        img.wait_for(timeout=10000)
        img_ok = p.evaluate('(e) => e.complete && e.naturalWidth > 0', img.element_handle())
        p.locator('h3.vg-seccion-head', has_text='FV-Smart 11').click()
        p.locator('.cadena').wait_for(timeout=10000)
        cadena = p.locator('.cadena').inner_text().replace('\n', ' · ')
        nivel, txt = barra(p)
        p.locator('.vg-retomado').scroll_into_view_if_needed()
        os.makedirs(CAPTURAS, exist_ok=True)
        p.screenshot(path=os.path.join(CAPTURAS, 'd-otro-equipo.png'))
        caso('(d) otro equipo: 2 versiones del servidor', v0301 == 'cumple' and v0303 == 'na' and 'del servidor' in retomado
             and 'token=prueba-firmada' in href and img_ok and not s.payloads and '2 respaldadas' in txt,
             f'03.01={v0301} · 03.03={v0303} · aviso «{retomado.strip()[:110]}…» · PDF con URL firmada={("token=" in href)} · '
             f'imagen cargada por URL firmada={img_ok} · firmadas={len(s.firmadas)} · reenvíos al servidor={len(s.payloads)} · barra «{txt}»')
        caso('(e1) registro encadenado íntegro', 'íntegro (2 versiones)' in cadena and 'verificable contra sí mismo' in cadena,
             f'«{cadena}»')
    finally:
        nav.close()
    s2 = Servidor(mis=versiones_del_servidor(), cadena={'ok': False, 'broken_at': 'bbbbbbbb-0000-4000-8000-000000000002', 'total': 2})
    nav, p = abrir(pw, s2)
    try:
        abrir_formulario(p)
        p.locator('.cadena').wait_for(timeout=15000)
        cadena = p.locator('.cadena').inner_text().replace('\n', ' · ')
        p.locator('.cadena').scroll_into_view_if_needed()
        p.screenshot(path=os.path.join(CAPTURAS, 'e-cadena-rota.png'))
        caso('(e2) registro encadenado roto', p.locator('.cadena.roto').count() == 1 and 'no cuadra' in cadena and 'bbbbbbbb' in cadena,
             f'«{cadena}»')
        visible = p.locator('body').inner_text().lower()
        prohibidas = [w for w in (r'inalterable', r'a prueba de fraude', r'certificad[oa]s?') if re.search(w, visible)]
        caso('(e3) sin frases prohibidas en la pantalla', not prohibidas, f'encontradas: {prohibidas or "ninguna"}')
    finally:
        nav.close()


def prueba_f(pw):
    sellada = {'code': '42501', 'details': None, 'hint': None, 'message': 'respuesta sellada (x): no se modifica; se guarda como una versión nueva'}
    s = Servidor(upsert=lambda pl, n: (403, sellada) if n == 1 else (200, '"33333333-3333-4333-8333-333333333333"'))
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, '1 respaldada')
        nivel, txt = barra(p)
        ids = [x.get('local_id') for x in s.payloads]
        hashes = [x.get('audit_hash') for x in s.payloads]
        caso('(f) sellada → versión nueva, no se reintenta el mismo local_id',
             len(ids) == 2 and ids[0] != ids[1] and all(UUID.match(i or '') for i in ids) and hashes[0] != hashes[1] and nivel == 'ok',
             f'local_id 1.º={ids[0][:8] if ids else "-"}… 2.º={ids[1][:8] if len(ids) > 1 else "-"}… · hash recalculado={len(set(hashes)) == 2} · barra «{txt}»')
    finally:
        nav.close()


def prueba_g(pw):
    s = Servidor()
    nav, p = abrir(pw, s, sesion=False, demo=True)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        p.wait_for_timeout(1500)
        esperar_barra(p, 'Modo demo')
        nivel, txt = barra(p)
        p.get_by_role('button', name='Mi progreso').click()
        p.wait_for_timeout(800)
        captura(p, 'g-demo.png')
        caso('(g) modo demo: sin llamadas', not s.llamadas and nivel == 'warn' and '1 pendiente' in txt,
             f'llamadas a Supabase={len(s.llamadas)} · barra «{txt}» [{nivel}]')
    finally:
        nav.close()


def main():
    preview = subprocess.Popen(f'npx vite preview --port {PUERTO} --strictPort', cwd=AQUI, shell=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            try:
                urllib.request.urlopen(APP, timeout=1); break
            except Exception:
                time.sleep(0.5)
        with sync_playwright() as pw:
            for prueba in (prueba_a, prueba_b, prueba_c, prueba_d_e, prueba_f, prueba_g):
                try:
                    prueba(pw)
                except Exception as e:
                    caso(prueba.__name__, False, f'excepción: {str(e)[:300]}')
    finally:
        subprocess.run(f'taskkill /T /F /PID {preview.pid}', shell=True, capture_output=True)
    fallas = [r for r in RESULTADOS if not r[1]]
    print(f'\n{len(RESULTADOS) - len(fallas)} de {len(RESULTADOS)} correctas')
    sys.exit(1 if fallas else 0)


if __name__ == '__main__':
    main()
