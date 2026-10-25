# Rearma public/fonts/material-symbols-cert.woff2: el subconjunto de Material Symbols Outlined con SOLO los íconos que
# usa la app, servido por la propia app para que funcione sin red (R3 offline). Correrlo cada vez que se use un ícono
# nuevo: si no, el ícono sale escrito como texto («FACT_CHECK»).
# Toma toda palabra entre comillas de src/ que sea un nombre oficial de Material Symbols: incluye de más (palabras
# comunes que coinciden con un ícono), nunca de menos, y pesa poco.
#   python scripts/subconjunto_iconos.py
import re, pathlib, urllib.request

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CODEPOINTS = ('https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/'
              'MaterialSymbolsOutlined%5BFILL%2CGRAD%2Copsz%2Cwght%5D.codepoints')
UA = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36'}

def bajar(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()

oficiales = {l.split()[0] for l in bajar(CODEPOINTS).decode().splitlines() if l.strip()}
usados = set()
for f in list((RAIZ / 'src').rglob('*.js*')) + list((RAIZ / 'src').rglob('*.html')):
    if f.name.endswith('.json'):
        continue
    usados |= set(re.findall(r"""['"`]([a-z][a-z0-9_]{1,40})['"`]""", f.read_text(encoding='utf-8')))
iconos = sorted(usados & oficiales)
css = bajar('https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0'
            '&icon_names=' + ','.join(iconos) + '&display=block').decode()
url = re.search(r'url\((https://[^)]+)\)', css).group(1)
dest = RAIZ / 'public' / 'fonts' / 'material-symbols-cert.woff2'
datos = bajar(url)
assert datos[:4] == b'wOF2', 'la respuesta no es un woff2'
dest.write_bytes(datos)
print(f'{len(iconos)} íconos · {len(datos)} bytes → {dest.relative_to(RAIZ)}')
