"""Publica los videos de ayuda de VG Certificaciones FUERA del paquete web (R-VIDEO: «los videos no van dentro del
paquete web ni de la APK: se sirven aparte»). Patrón copiado de vg-custody/app/scripts/publicar_ayuda.py.

- Toma lo que grabó el kit en ayuda-flujos/salida/ (mp4, jpg y ayuda.json) y la versión para redes (R-VIDEO,
  1080×1920) en ayuda-flujos/salida-redes/ (<id>-redes.mp4; la hoja de cuadros es para revisar y no se sube).
- Sube SOLO los mp4 y jpg al proyecto de Cloudflare Pages `vg-cert-videos` (sitio aparte, con su _headers);
  los de redes, bajo redes/.
- Escribe public/ayuda/ayuda.json para la app con las direcciones ABSOLUTAS de cada video y portada.
  El índice sí vive en el producto: R-AYUDA cuenta la ayuda como hecha cuando el producto sirve /ayuda/ayuda.json.
El token de Cloudflare sale de la bóveda a una variable de entorno; nunca se imprime (R19).
Uso: python scripts/publicar_ayuda.py   (después: npm run build y copiar dist/ a docs/, que es lo que sirve GitHub Pages)
"""
import json, os, re, shutil, subprocess, sys, tempfile

AQUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA_KIT = os.path.join(AQUI, 'ayuda-flujos', 'salida')
SALIDA_REDES = os.path.join(AQUI, 'ayuda-flujos', 'salida-redes')
PROYECTO = 'vg-cert-videos'
BASE = f'https://{PROYECTO}.pages.dev'
ORIGEN_APP = 'https://cert.visiongeografica.com'
PROBAR_LOCAL = 'http://localhost:4173'   # los flujos se graban contra vite preview; en el índice va el dominio público
BOVEDA = os.path.join(r'G:\Mi unidad\PROYECTOS PERSONALES\VG CREDENCIALES', 'cloudflare', 'cloudflare-tokens.txt')


def valor(clave):
    for l in open(BOVEDA, encoding='utf-8'):
        m = re.match(rf'^\s*{clave}\s*=\s*(\S+)', l)
        if m:
            return m[1].strip('"\'')
    raise SystemExit(f'no está {clave} en la bóveda')


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')   # wrangler imprime emojis; la consola cp1252 tumbaba el guion
    indice = json.load(open(os.path.join(SALIDA_KIT, 'ayuda.json'), encoding='utf-8'))
    tmp = tempfile.mkdtemp(prefix='cert-videos-')
    for f in os.listdir(SALIDA_KIT):
        if f.endswith(('.mp4', '.jpg')):
            shutil.copy2(os.path.join(SALIDA_KIT, f), tmp)
    redes = sorted(f for f in os.listdir(SALIDA_REDES) if f.endswith('-redes.mp4')) if os.path.isdir(SALIDA_REDES) else []
    if redes:
        os.makedirs(os.path.join(tmp, 'redes'))
        for f in redes:
            shutil.copy2(os.path.join(SALIDA_REDES, f), os.path.join(tmp, 'redes'))
    open(os.path.join(tmp, '_headers'), 'w', encoding='utf-8').write(
        '/*\n  Strict-Transport-Security: max-age=31536000\n  X-Content-Type-Options: nosniff\n'
        '  Referrer-Policy: strict-origin-when-cross-origin\n  X-Frame-Options: SAMEORIGIN\n'
        '  Cache-Control: public, max-age=86400\n'
        f'  Access-Control-Allow-Origin: {ORIGEN_APP}\n')
    open(os.path.join(tmp, 'index.html'), 'w', encoding='utf-8').write(
        '<!doctype html><meta charset="utf-8"><title>VG Certificaciones · videos de ayuda</title>'
        f'<p>Videos de ayuda de VG Certificaciones. El centro de ayuda está en <a href="{ORIGEN_APP}/ayuda/">cert.visiongeografica.com/ayuda</a>.</p>')
    env = dict(os.environ, CLOUDFLARE_API_TOKEN=valor('CF_TOKEN_EDIT_CLOUDFLARE_WORKERS'), CLOUDFLARE_ACCOUNT_ID=valor('ACCOUNT_ID'))
    lista = subprocess.run('npx --yes wrangler@3 pages project list', shell=True, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if PROYECTO not in (lista.stdout or ''):
        subprocess.run(f'npx --yes wrangler@3 pages project create {PROYECTO} --production-branch main', shell=True, env=env, check=True)
    r = subprocess.run(f'npx --yes wrangler@3 pages deploy "{tmp}" --project-name {PROYECTO} --branch main --commit-dirty=true',
                       shell=True, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    print('\n'.join(l for l in ((r.stdout or '') + (r.stderr or '')).splitlines() if 'Success' in l or 'rror' in l or 'pages.dev' in l))
    if r.returncode:
        raise SystemExit(r.returncode)
    for f in indice['flujos']:
        if f.get('video'):
            f['video'] = f'{BASE}/{os.path.basename(f["video"])}'
        if f.get('portada'):
            f['portada'] = f'{BASE}/{os.path.basename(f["portada"])}'
        if f'{f["id"]}-redes.mp4' in redes:
            f['video_redes'] = f'{BASE}/redes/{f["id"]}-redes.mp4'
        if (f.get('probar') or '').startswith(PROBAR_LOCAL):
            f['probar'] = ORIGEN_APP + f['probar'][len(PROBAR_LOCAL):]
    destino = os.path.join(AQUI, 'public', 'ayuda')
    os.makedirs(destino, exist_ok=True)
    for f in os.listdir(destino):   # en el paquete web queda SOLO el índice
        if f != 'ayuda.json':
            os.remove(os.path.join(destino, f))
    json.dump(indice, open(os.path.join(destino, 'ayuda.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    shutil.rmtree(tmp, ignore_errors=True)
    print('índice:', len(indice['flujos']), 'flujos ·', sum(1 for f in indice['flujos'] if f.get('video')), 'con video ·', len(redes), 'para redes, en', BASE)


if __name__ == '__main__':
    main()
