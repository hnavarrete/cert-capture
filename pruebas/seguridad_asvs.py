"""Pruebas de los arreglos de seguridad del lado de la app (auditoría ASVS L1, 13-oct-2026).

Mismo arnés que respaldo_servidor.py: SIN cuentas reales y SIN escribir en producción. Toda llamada a Supabase se
INTERCEPTA y se contesta aquí; la sesión es un token de prueba que no sirve fuera de este navegador.

Casos: (h) segundo factor: con factor verificado y sesión aal1 no se muestra la app ni sale ninguna llamada con
sesión; código malo → error; código bueno → entra · (i) evidencia: subida con x-upsert false y sha256 correcta en
la referencia; «ya existe» (409) cuenta como subida · (j) un archivo que no es PDF/imagen aunque se llame .pdf no
se adjunta · (k) «Salir» sin pendientes borra vg_*, lo respaldado y la sesión; con pendientes pide confirmar y no
borra lo pendiente · (l) perfil: {ok:false} del servidor se muestra y no avanza; se manda p_cargo.

Uso:  npx vite build  y luego  python pruebas/seguridad_asvs.py   (levanta y cierra su propio vite preview)
"""
import hashlib, json, subprocess, sys, time, urllib.request
from playwright.sync_api import sync_playwright
import respaldo_servidor as rs
from respaldo_servidor import Servidor, caso, abrir, abrir_formulario, guardar_con_evidencia, esperar_barra, b64u

FACTOR = 'f0000000-0000-4000-8000-00000000000f'


def sesion(aal='aal1', factores=True):
    exp = int(time.time()) + 7 * 24 * 3600
    usuario = {'id': '00000000-0000-4000-8000-000000000001', 'aud': 'authenticated', 'role': 'authenticated',
               'email': 'prueba@ejemplo.test', 'app_metadata': {'provider': 'email'}, 'user_metadata': {},
               'created_at': '2026-10-06T00:00:00Z',
               'factors': [{'id': FACTOR, 'factor_type': 'totp', 'status': 'verified', 'friendly_name': 'app',
                            'created_at': '2026-10-01T00:00:00Z', 'updated_at': '2026-10-01T00:00:00Z'}] if factores else []}
    token = b64u({'alg': 'HS256', 'typ': 'JWT'}) + '.' + b64u({'sub': usuario['id'], 'role': 'authenticated', 'aal': aal,
                                                                'aud': 'authenticated', 'exp': exp, 'email': usuario['email']}) + '.prueba'
    return {'access_token': token, 'token_type': 'bearer', 'expires_in': 7 * 24 * 3600, 'expires_at': exp,
            'refresh_token': 'prueba-refresh', 'user': usuario}


class ServidorSeg(Servidor):
    """El servidor de respaldo_servidor.py más MFA, cierre de sesión, perfil y la cabecera x-upsert."""

    def __init__(self, *a, perfil=None, subida=None, codigo='123456', con_factor=False, **k):
        super().__init__(*a, **k)
        self.perfil = perfil            # None = ya tiene perfil; si no, función (cuerpo, n) -> respuesta de upsert_my_profile
        self.subida = subida            # None = 200; si no, (status, cuerpo)
        self.codigo, self.con_factor = codigo, con_factor
        self.upserts_perfil, self.cabeceras_subida, self.cuerpos_subida = [], [], []

    def atender(self, route):
        req = route.request
        ruta = req.url[len(rs.SUPA):]
        js = lambda cuerpo, status=200: route.fulfill(status=status, content_type='application/json', body=json.dumps(cuerpo))
        if ruta.startswith('/auth/v1/user'):
            self.llamadas.append(f'{req.method} /auth/v1/user')
            return js(sesion(factores=self.con_factor)['user'])
        if ruta.startswith(f'/auth/v1/factors/{FACTOR}/challenge'):
            self.llamadas.append('POST challenge')
            return js({'id': 'reto-1', 'type': 'totp', 'expires_at': int(time.time()) + 300})
        if ruta.startswith(f'/auth/v1/factors/{FACTOR}/verify'):
            self.llamadas.append('POST verify')
            cuerpo = json.loads(req.post_data or '{}')
            if cuerpo.get('code') != self.codigo:
                return js({'code': 'mfa_verification_failed', 'message': 'Invalid TOTP code entered'}, 422)
            return js(sesion(aal='aal2', factores=self.con_factor))
        if ruta.startswith('/auth/v1/logout'):
            self.llamadas.append('POST logout')
            return route.fulfill(status=204, body='')
        if ruta.startswith('/rest/v1/rpc/get_my_profile') and self.perfil:
            self.llamadas.append('POST /rest/v1/rpc/get_my_profile')
            return js({'ok': True, 'has_profile': False})
        if ruta.startswith('/rest/v1/rpc/ensure_producer_self'):
            self.llamadas.append('POST /rest/v1/rpc/ensure_producer_self')
            return js({'ok': True})
        if ruta.startswith('/rest/v1/rpc/upsert_my_profile'):
            self.llamadas.append('POST /rest/v1/rpc/upsert_my_profile')
            cuerpo = json.loads(req.post_data or '{}')
            self.upserts_perfil.append(cuerpo)
            return js(self.perfil(cuerpo, len(self.upserts_perfil)))
        if ruta.startswith('/storage/v1/object/cert-evidencias/') and req.method == 'POST':
            self.cabeceras_subida.append(req.headers.get('x-upsert'))
            self.cuerpos_subida.append(req.post_data_buffer or b'')
            if self.subida:
                self.subidas.append(ruta.split('?')[0])
                return js(self.subida[1], self.subida[0])
        return super().atender(route)


def abrir_con(pw, servidor, ses):
    """Como rs.abrir, pero con la sesión que se le pase."""
    original = rs.sesion_de_prueba
    rs.sesion_de_prueba = lambda: ses
    try:
        return abrir(pw, servidor)
    finally:
        rs.sesion_de_prueba = original


def contar_idb(p, almacen='cert_responses', filtro=None):
    return p.evaluate("""([almacen, filtro]) => new Promise(res => {
      const r = indexedDB.open('vg-cert-capture')
      r.onsuccess = () => { const tx = r.result.transaction(almacen); const q = tx.objectStore(almacen).getAll()
        q.onsuccess = () => res(q.result.filter(x => !filtro || x.sync_status === filtro).length) }
      r.onerror = () => res(-1)
    })""", [almacen, filtro])


def claves_vg(p):
    return p.evaluate("Object.keys(localStorage).filter(k => k.startsWith('vg_'))")


def prueba_h(pw):
    s = ServidorSeg(con_factor=True)
    nav, p = abrir_con(pw, s, sesion('aal1'))
    try:
        p.get_by_text('Verificación en dos pasos').wait_for(timeout=15000)
        con_sesion = [x for x in s.llamadas if '/rest/v1/' in x or '/storage/' in x]
        app_visible = p.locator('header.topbar').count()
        caso('(h1) aal1 con factor: desafío, sin app ni llamadas con sesión', not con_sesion and not app_visible,
             f'llamadas REST/Storage={con_sesion} · barra de la app visible={bool(app_visible)}')
        p.get_by_label('Código de 6 dígitos').fill('000000')
        p.get_by_role('button', name='Verificar').click()
        p.get_by_text('El código no es válido o ya caducó.').wait_for(timeout=10000)
        caso('(h2) código equivocado: error y sin app', p.locator('header.topbar').count() == 0, 'mensaje de código no válido visible')
        p.get_by_label('Código de 6 dígitos').fill('123456')
        p.get_by_role('button', name='Verificar').click()
        p.locator('header.topbar').wait_for(timeout=15000)
        caso('(h3) código bueno: entra a la app', 'POST /rest/v1/rpc/my_products' in s.llamadas,
             f'verify={s.llamadas.count("POST verify")} · my_products llamado={"POST /rest/v1/rpc/my_products" in s.llamadas}')
        rs.captura(p, 'h-segundo-factor.png')
    finally:
        nav.close()
    # sin factor: entra directo, como siempre
    s2 = ServidorSeg()
    nav, p = abrir_con(pw, s2, sesion('aal1', factores=False))
    try:
        p.locator('header.topbar').wait_for(timeout=15000)
        caso('(h4) cuenta sin segundo factor: entra igual que antes', p.get_by_text('Verificación en dos pasos').count() == 0, 'app visible sin desafío')
    finally:
        nav.close()


def prueba_i(pw):
    s = ServidorSeg()
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, '1 respaldada')
        pl = s.payloads[-1] if s.payloads else {}
        ref = (pl.get('fotos') or [{}])[0]
        esperado = hashlib.sha256(open(rs.MUESTRA_PDF, 'rb').read()).hexdigest()
        caso('(i1) subida sin reemplazo y con huella', s.cabeceras_subida == ['false'] and ref.get('sha256') == esperado
             and ref.get('mime') == 'application/pdf',
             f'x-upsert={s.cabeceras_subida} · sha256 coincide={ref.get("sha256") == esperado} · mime={ref.get("mime")}')
    finally:
        nav.close()
    s2 = ServidorSeg(subida=(409, {'statusCode': '409', 'error': 'Duplicate', 'message': 'The resource already exists'}))
    nav, p = abrir(pw, s2)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, '1 respaldada')
        caso('(i2) «ya existe» cuenta como subida', len(s2.payloads) == 1, f'intentos de subida={len(s2.subidas)} · respuestas enviadas={len(s2.payloads)}')
    finally:
        nav.close()


def prueba_j(pw):
    s = ServidorSeg()
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        caja = '.vg-foto-box:has(input[data-field="sec_3.fv_smart_03_02__evidencia"])'
        p.set_input_files(f'{caja} input[type=file]', files=[{'name': 'acta.pdf', 'mimeType': 'application/pdf', 'buffer': b'MZ\x90\x00 no soy un pdf'}])
        p.locator(f'{caja} .vg-error', has_text='no se adjuntó').wait_for(timeout=10000)
        valor = p.locator(f'{caja} input[type=hidden]').input_value()
        caso('(j) archivo disfrazado de PDF: rechazado', valor == '', f'mensaje visible · campo de evidencia vacío={valor == ""}')
        rs.captura(p, 'j-archivo-rechazado.png')
    finally:
        nav.close()


def prueba_k(pw):
    s = ServidorSeg()
    nav, p = abrir(pw, s)
    try:
        abrir_formulario(p)
        p.get_by_label('Productor (producer_id)').fill('PRD-001')
        guardar_con_evidencia(p)
        esperar_barra(p, '1 respaldada')
        antes = (contar_idb(p), claves_vg(p))
        p.get_by_role('button', name='Salir').click()
        p.get_by_text('Explorar en modo demo').wait_for(timeout=15000)
        despues = (contar_idb(p), contar_idb(p, 'cert_photos'), claves_vg(p), p.evaluate(f"localStorage.getItem('{rs.CLAVE_SESION}')"))
        caso('(k1) salir sin pendientes: borra lo respaldado, vg_* y la sesión',
             despues[0] == 0 and despues[1] == 0 and not despues[2] and despues[3] is None and 'POST logout' in s.llamadas,
             f'antes: registros={antes[0]} claves={antes[1]} · después: registros={despues[0]} evidencias={despues[1]} claves={despues[2]} sesión={despues[3] is not None}')
    finally:
        nav.close()
    s2 = ServidorSeg(upsert=lambda pl, n: 'cortar')
    nav, p = abrir(pw, s2)
    try:
        abrir_formulario(p)
        guardar_con_evidencia(p)
        esperar_barra(p, '1 pendiente')
        p.get_by_role('button', name='Salir').click()
        p.get_by_text('sin respaldar').first.wait_for(timeout=20000)
        rs.captura(p, 'k-salir-con-pendientes.png')
        p.get_by_role('button', name='Salir de todas formas').click()
        p.get_by_text('Explorar en modo demo').wait_for(timeout=15000)
        pend = contar_idb(p, filtro='failed') + contar_idb(p, filtro='pending')
        caso('(k2) salir con pendientes: pide confirmar y lo pendiente se queda', pend == 1 and not claves_vg(p),
             f'versiones pendientes que siguen en el equipo={pend} · claves vg_*={claves_vg(p)}')
    finally:
        nav.close()


def prueba_l(pw):
    s = ServidorSeg(perfil=lambda c, n: {'ok': False, 'error': 'campos_obligatorios'} if n == 1 else {'ok': True})
    nav, p = abrir(pw, s)
    try:
        p.get_by_text('Tu perfil de productor').wait_for(timeout=15000)
        p.get_by_placeholder('Número de identificación').fill('0000000000')
        p.get_by_placeholder('Tus nombres').fill('Prueba')
        p.get_by_placeholder('Tus apellidos').fill('Demo')
        p.get_by_label('Cargo').fill('Técnico de campo')
        p.locator('label.check input[type=checkbox]').check()
        # La casilla de autorización cambia de alto (24 px) al perder el foco, y el botón se mueve entre el mousedown y el
        # mouseup: el clic de Playwright cae en el formulario. Se quita el foco de la casilla antes de pulsar el botón.
        p.locator('label.check input[type=checkbox]').evaluate('e => e.blur()')
        p.wait_for_timeout(200)
        p.get_by_role('button', name='Guardar mi perfil').click()
        p.get_by_text('Faltan datos obligatorios').wait_for(timeout=10000)
        sigue = p.get_by_text('Tu perfil de productor').count() == 1
        caso('(l1) {ok:false} del servidor: se muestra y no avanza', sigue and s.upserts_perfil[0].get('p_cargo') == 'Técnico de campo',
             f'formulario sigue={sigue} · p_cargo enviado={s.upserts_perfil[0].get("p_cargo")!r}')
        p.get_by_role('button', name='Guardar mi perfil').click()
        p.locator('header.topbar').wait_for(timeout=15000)
        caso('(l2) {ok:true}: entra a la app', True, f'llamadas a upsert_my_profile={len(s.upserts_perfil)}')
    finally:
        nav.close()


def main():
    preview = subprocess.Popen(f'npx vite preview --port {rs.PUERTO} --strictPort', cwd=rs.AQUI, shell=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(60):
            try:
                urllib.request.urlopen(rs.APP, timeout=1); break
            except Exception:
                time.sleep(0.5)
        with sync_playwright() as pw:
            for prueba in (prueba_h, prueba_i, prueba_j, prueba_k, prueba_l):
                try:
                    prueba(pw)
                except Exception as e:
                    caso(prueba.__name__, False, f'excepción: {str(e)[:300]}')
    finally:
        subprocess.run(f'taskkill /T /F /PID {preview.pid}', shell=True, capture_output=True)
    fallas = [r for r in rs.RESULTADOS if not r[1]]
    print(f'\n{len(rs.RESULTADOS) - len(fallas)} de {len(rs.RESULTADOS)} correctas')
    sys.exit(1 if fallas else 0)


if __name__ == '__main__':
    main()
