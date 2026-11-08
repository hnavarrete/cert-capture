"""Graba los videos del centro de ayuda de VG Certificaciones™ con el kit de VG (vg-agriops/docs/ayuda-video/kit_video.py).

  1. reescribe los flujos (generar_flujos.py) y construye la app (npm run build);
  2. la sirve en local con `vite preview` en 127.0.0.1:4173 y graba sobre la DEMOSTRACIÓN (?demo=1, datos ficticios);
  3. corre el kit sin modificarlo: video de la app en 828 × 1876 (subtítulo en su franja, debajo de la pantalla) y la
     versión para redes en 1080 × 1920 con su hoja de cuadros, desde el mismo flujo. La cabecera común del ayuda.json
     sale de producto.json (línea única de los centros de ayuda, #17, 31-oct-2026).

Uso:  python ayuda-flujos/grabar.py [ayuda-flujos/flujos/NN-id.json]     (después: python scripts/publicar_ayuda.py)
"""
import os, runpy, subprocess, sys, time, urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(AQUI)
KIT = os.environ.get('VG_KIT_AYUDA', r'C:\Users\Usuario\proyectos\vg-agriops\docs\ayuda-video\kit_video.py')
MUSICA_LIBRE = os.environ.get('VG_MUSICA_LIBRE', r'E:\VG-MARKETING\piezas\canal\musica_libre')


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    objetivo = args[0] if args else os.path.join(AQUI, 'flujos')
    if not args:
        subprocess.run([sys.executable, os.path.join(AQUI, 'generar_flujos.py')], check=True)
    if '--sin-construir' not in sys.argv:
        subprocess.run('npm run build', shell=True, cwd=APP, check=True)
    srv = subprocess.Popen('npx vite preview --host 127.0.0.1 --port 4173 --strictPort', shell=True, cwd=APP,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    codigo = 0
    try:
        for _ in range(60):
            try:
                urllib.request.urlopen('http://127.0.0.1:4173/', timeout=2); break
            except Exception:
                time.sleep(0.5)
        argv = [KIT, os.path.abspath(objetivo), '--salida', os.path.join(AQUI, 'salida'), '--redes',
                '--redes-salida', os.path.join(AQUI, 'salida-redes'), '--rotulo', 'VG Certificaciones · Ayuda en video',
                '--pie', 'cert.visiongeografica.com', '--cabecera', os.path.join(AQUI, 'producto.json')]
        if os.path.isdir(MUSICA_LIBRE):
            argv += ['--musica-libre', MUSICA_LIBRE]
        sys.argv = argv
        sys.path.insert(0, os.path.dirname(KIT))
        try:
            runpy.run_path(KIT, run_name='__main__')
        except SystemExit as e:
            codigo = e.code or 0
    finally:
        subprocess.run(f'taskkill /PID {srv.pid} /T /F', shell=True, capture_output=True)
    sys.exit(codigo)


if __name__ == '__main__':
    main()
