# Genera los flujos del centro de ayuda en video de VG Certificaciones (R-AYUDA, R-VIDEO).
# Un flujo = un .json = un video + su paso a paso escrito (kit: vg-agriops/docs/ayuda-video/kit_video.py).
#
# Inventario LEÍDO DEL CÓDIGO (src/App.jsx, src/eudr-react/CertForm.jsx, RoadmapCert.jsx, Boveda.jsx, engine.js),
# no de la documentación. Se graba sobre el MODO DEMOSTRACIÓN (?demo=1): sin sesión, el transporte no llama a
# Supabase (engine.js: «sin sesión» → no sube nada), así que la grabación no escribe en producción. Los datos son
# ficticios (finca-demo, PRD-DEMO-01, documentos de ejemplo en flujos/muestras/).
# Lo que solo existe con una cuenta real va como paso a paso escrito, marcado «video en preparación».
#
# Uso: python ayuda-flujos/generar_flujos.py   (escribe ayuda-flujos/flujos/*.json)
import json, os

AQUI = os.path.dirname(os.path.abspath(__file__))
DESTINO = os.path.join(AQUI, 'flujos')
LOCAL = 'http://localhost:4173'                     # vite preview del build que se va a publicar
PUBLICA = 'https://cert.visiongeografica.com'
DEMO = LOCAL + '/?demo=1'
PROBAR = PUBLICA + '/?demo=1'
CIERRE_SUB = 'cert.visiongeografica.com/ayuda'

# simula «sin señal» igual que el modo avión: el motor lee navigator.onLine y escucha el evento offline
SIN_SENAL = ("Object.defineProperty(Navigator.prototype,'onLine',{get:()=>false,configurable:true});"
             "window.dispatchEvent(new Event('offline'))")

def centrar(texto, ver=None):   # ver: otro texto para la cámara si «texto» también está en una <option> oculta
    """Lleva al CENTRO de la pantalla el elemento cuyo texto propio contiene `texto`, y lo marca como foco de la cámara.
    Sin esto, lo que queda al pie de la pantalla cae debajo del subtítulo en la versión para redes (R-VIDEO).
    El relleno inferior solo agrega espacio en blanco al final de la página para que se pueda centrar lo último."""
    js = ("(() => { document.body.style.paddingBottom = '420px'; const t = %s;"
          " const e = [...document.querySelectorAll('body *')].find(x => x.offsetParent &&"
          " [...x.childNodes].some(n => n.nodeType === 3 && n.textContent.includes(t)));"
          " if (e) e.scrollIntoView({ block: 'center' }); })()") % json.dumps(texto)
    return [{'js': js}, {'pausa': 350}, {'ver': ver or texto}]

ARRIBA = [{'js': 'window.scrollTo(0, 0)'}, {'pausa': 350}]

def caja_archivo(campo):   # el <input type=file> oculto de un campo de evidencia
    return f'.vg-foto-box:has(input[data-field="{campo}"]) input[type=file]'

def contexto():   # finca, productor y lote ficticios, detrás de la carátula
    return [{'llenar_ph': ['ej. demo-cert', 'finca-demo']}, {'llenar_ph': ['PRD-001', 'PRD-DEMO-01']},
            {'llenar_ph': ['GY-001', 'LOTE-01']}]

def tramo_btn(titulo):   # el botón del tramo en la hoja de ruta (get_by_text caería en la <option> oculta del selector)
    return {'clic_css': f'button:has-text("{titulo}")'}

def abrir_tramo(norma, tramo):
    return [{'clic': norma}, {'pausa': 400}, tramo_btn(tramo), {'pausa': 600}]

FV_SMART = 'GLOBAL G.A.P. - IFA Fruta y Verdura (edicion Smart)'

F = []
def flujo(**k):
    k.setdefault('musica_estilo', 'eudr'); k.setdefault('limpiar', True)
    k.setdefault('cierre_sub', CIERRE_SUB); k.setdefault('nota', '')
    F.append(k)

# ───────────────────────── cuenta ─────────────────────────
flujo(id='cuenta-entrar', actor='cuenta', actor_txt='Su cuenta', orden=10,
      titulo='Entrar a Certificaciones',
      resumen='Con Google, con correo y contraseña, o con un enlace que llega al correo.',
      url=LOCAL + '/', probar=PUBLICA + '/', gancho='¿Primera vez en Certificaciones?', preparar=[],
      pasos=[
          {'texto': 'Abra cert.visiongeografica.com en el teléfono o en la computadora.', 'foco': 'arriba', 'ms': 2800},
          {'texto': 'Entre con su cuenta de Google en un toque.', 'acciones': [{'ver': 'Continuar con Google'}], 'ms': 2800},
          {'texto': 'O escriba su correo y contraseña y toque «Entrar».', 'acciones': [{'ver': 'Correo electrónico'}], 'ms': 3000},
          {'texto': 'Sin contraseña: pida un enlace de acceso y ábralo desde su correo.',
           'acciones': [{'ver': 'Enviar enlace de acceso al correo'}], 'ms': 3000},
          {'texto': 'Abajo están el modo demostración y esta ayuda en video.',
           'acciones': [{'ver': 'Ayuda en video'}], 'ms': 3000},
      ],
      cierre='Bienvenido a VG Certificaciones',
      nota='Si su cuenta tiene segundo factor, después de la contraseña se pide el código de 6 dígitos (vea «Entrar con segundo factor»).')

flujo(id='cuenta-demo', actor='cuenta', actor_txt='Su cuenta', orden=12,
      titulo='Probar la app en modo demostración',
      resumen='Explore todo sin cuenta: lo que capture se queda en su dispositivo y no se envía al servidor.',
      url=LOCAL + '/', probar=PROBAR, gancho='¿Quiere probar antes de empezar?', preparar=[],
      pasos=[
          {'texto': 'En la pantalla de ingreso, debajo de «Entrar», está «Explorar en modo demo».',
           'corto': 'Debajo de «Entrar» está «Explorar en modo demo».',
           'acciones': [{'ver': 'Explorar en modo demo'}], 'ms': 2600},
          {'texto': 'Tóquelo: el aviso amarillo confirma que está en modo demostración.',
           'corto': 'Tóquelo: el aviso amarillo confirma el modo demostración.',
           'acciones': [{'clic': 'Explorar en modo demo'}], 'foco': 'arriba', 'ms': 3200},
          {'texto': 'Lo que capture queda solo en este dispositivo: no se envía al servidor.',
           'foco': 'arriba', 'ms': 3200},
          {'texto': 'Elija una norma y recorra sus formularios sin miedo a equivocarse.',
           'acciones': centrar('Rainforest Alliance 2020'), 'ms': 3000},
      ],
      cierre='Pruébelo sin cuenta',
      nota='Para guardar de verdad en el servidor hay que entrar con una cuenta de VG que tenga acceso a la finca.')

flujo(id='cuenta-segundo-factor', actor='cuenta', orden=14, solo_texto=True,
      titulo='Entrar con segundo factor y avisos de contraseña',
      resumen='Si su cuenta tiene verificación en dos pasos, se pide un código de 6 dígitos.',
      url=LOCAL + '/', probar=PUBLICA + '/',
      pasos=[
          {'texto': 'Escriba su correo y contraseña y toque «Entrar».'},
          {'texto': 'Si su cuenta tiene segundo factor, la app pide el código de 6 dígitos de su aplicación de autenticación.'},
          {'texto': 'Escriba el código antes de que cambie. Si sale «El código no es válido o ya caducó», espere el siguiente y vuelva a escribirlo.'},
          {'texto': 'Si la app avisa «Conviene cambiar su contraseña», es porque esa contraseña apareció en filtraciones públicas: usted entra igual, pero conviene cambiarla.'},
      ],
      nota='Este flujo necesita una cuenta real con segundo factor: el video está en preparación.')

flujo(id='cuenta-sin-acceso', actor='cuenta', orden=16, solo_texto=True,
      titulo='Mi cuenta no tiene acceso a Certificaciones',
      resumen='Qué hacer si la app dice que su cuenta todavía no tiene acceso, o que no pudo cargar sus permisos.',
      url=LOCAL + '/', probar=PUBLICA + '/',
      pasos=[
          {'texto': 'Si ve «Su cuenta ya es parte del ecosistema VG, pero todavía no tiene acceso», toque «Solicitar acceso por WhatsApp».'},
          {'texto': 'El mensaje sale escrito con su correo: envíelo y el administrador activa el acceso.'},
          {'texto': 'Si entró con otra cuenta por error, toque «Cambiar de cuenta».'},
          {'texto': 'Si ve «No pudimos cargar tus permisos», su sesión sí está activa: toque «Reintentar». Suele ser una falla pasajera de la conexión.'},
      ],
      nota='Este flujo solo aparece con una cuenta real sin acceso: el video está en preparación.')

flujo(id='cuenta-perfil', actor='cuenta', orden=18, solo_texto=True,
      titulo='Completar su perfil de productor',
      resumen='La primera vez se pide su identificación: evita duplicados y hace que sus registros sean suyos.',
      url=LOCAL + '/', probar=PUBLICA + '/',
      pasos=[
          {'texto': 'Elija el tipo de identificación: cédula, RUC o pasaporte, y escriba el número.'},
          {'texto': 'Escriba su nombre y apellido; el teléfono es opcional.'},
          {'texto': 'Marque la autorización para guardar sus datos y toque «Guardar mi perfil».'},
          {'texto': 'Si no tiene señal, el perfil queda guardado en el dispositivo y se registra al volver la conexión.'},
          {'texto': 'Si prefiere hacerlo después, toque «Completar luego»: la app no lo bloquea.'},
      ],
      nota='Esta pantalla aparece solo con una cuenta real que aún no tiene perfil: el video está en preparación.')

flujo(id='cuenta-vg-suite', actor='cuenta', orden=19, solo_texto=True,
      titulo='Abrir Certificaciones desde VG Suite',
      resumen='Dentro de la app VG Suite, Certificaciones usa la misma sesión: no se vuelve a ingresar.',
      url=LOCAL + '/', probar=PUBLICA + '/',
      pasos=[
          {'texto': 'En VG Suite, abra «Certificaciones» desde el menú.'},
          {'texto': 'La sesión es la misma de VG Suite: no hace falta volver a entrar, y por eso no aparece el botón «Salir».'},
          {'texto': 'Si ve «Sesión no disponible», toque «Reintentar» o vuelva a abrir Certificaciones desde el menú de VG Suite.'},
      ],
      nota='Este flujo ocurre dentro de la app de teléfono VG Suite: el video está en preparación.')

# ───────────────────────── productor / responsable de la finca ─────────────────────────
P = dict(actor='productor', actor_txt='Productor · finca', url=DEMO, probar=PROBAR)

flujo(id='productor-contexto', orden=20, **P,
      titulo='Indicar la finca, el productor y el lote',
      resumen='Antes de capturar, se indica de qué finca y de qué lote es la información.',
      gancho='¿De qué finca es esta captura?', preparar=[],
      pasos=[
          {'texto': 'En «Contexto del levantamiento», escriba la finca.',
           'acciones': [{'llenar_ph': ['ej. demo-cert', 'finca-demo']}], 'ms': 1800},
          {'texto': 'Escriba el código del productor.',
           'acciones': [{'llenar_ph': ['PRD-001', 'PRD-DEMO-01']}], 'ms': 1800},
          {'texto': 'Y el código de la finca o del lote.',
           'acciones': [{'llenar_ph': ['GY-001', 'LOTE-01']}], 'ms': 2200},
          {'texto': 'Todo lo que capture desde ahora queda asociado a ese contexto.',
           'acciones': [{'ver': 'El polígono se conecta'}], 'ms': 3000},
      ],
      cierre='Contexto listo',
      nota='Con una cuenta real, la finca se elige de la lista «tus fincas»: son las mismas del visor y del ERP.')

flujo(id='productor-hoja-ruta', orden=22, **P,
      titulo='Elegir la norma y ver su hoja de ruta',
      resumen='Cada norma trae su hoja de ruta: pilares, tramos, preguntas y tiempo estimado.',
      gancho='¿Por dónde empezar la auditoría?', preparar=contexto(),
      pasos=[
          {'texto': 'En «Certificación», toque la norma que va a preparar.',
           'acciones': centrar('EU Deforestation Regulation') + [{'clic': 'EU Deforestation Regulation'}], 'ms': 2600},
          {'texto': 'La hoja de ruta muestra los tramos, las preguntas y el tiempo estimado.',
           'acciones': [{'ver': 'Hoja de ruta'}], 'ms': 3200},
          {'texto': 'Los tramos se agrupan en cuatro pilares: legal, ambiental, social y gestión.',
           'acciones': [{'ver': 'Social y laboral'}], 'ms': 3200},
          {'texto': 'Cada tramo indica su tiempo y su estado: sin empezar, en progreso o listo.',
           'acciones': [{'ver': 'sin empezar'}], 'ms': 3000},
          {'texto': 'Abajo, el tiempo estimado que falta para completar la norma.',
           'acciones': centrar('Tiempo restante'), 'ms': 3200},
      ],
      cierre='Su hoja de ruta, a la vista')

flujo(id='productor-nucleo', orden=24, **P,
      titulo='Núcleo compartido: capturar una vez para varias normas',
      resumen='Los tramos del núcleo se llenan una sola vez y cuentan para todas las normas que los usan.',
      gancho='¿Llenar lo mismo para cada norma?', preparar=contexto(),
      pasos=[
          {'texto': 'Los tramos marcados «núcleo» alimentan varias normas a la vez.',
           'acciones': [{'ver': 'Trabajadores y trabajo decente'}], 'ms': 3200},
          {'texto': 'Ábralo y responda una vez.',
           'acciones': [tramo_btn('Trabajadores y trabajo decente'), {'pausa': 500}] + centrar('Tipo de vinculación')
                       + [{'elegir': ['Tipo de vinculación', 'Fijo']}], 'ms': 2600},
          {'texto': 'Guárdelo: queda en el dispositivo aunque no haya señal.',
           'acciones': [{'clic': 'Guardar (offline)'}], 'ms': 2400},
          {'texto': 'Ahora elija otra norma, por ejemplo Rainforest Alliance.',
           'acciones': [{'clic': 'Rainforest Alliance'}], 'ms': 2200},
          {'texto': '«Ventaja inicial»: lo que ya capturó del núcleo cuenta aquí sin volver a llenarlo.',
           'corto': '«Ventaja inicial»: lo del núcleo cuenta aquí sin volver a llenarlo.',
           'acciones': centrar('Ventaja inicial'), 'ms': 3600},
      ],
      cierre='Capture una vez, úselo en varias normas')

flujo(id='productor-llenar', orden=30, **P,
      titulo='Llenar un formulario por secciones',
      resumen='Cada tramo es un formulario dividido en secciones que se abren y se cierran.',
      gancho='¿Cómo se llena un formulario?', preparar=contexto(),
      pasos=[
          {'texto': 'En la hoja de ruta, busque el tramo que va a llenar.',
           'acciones': centrar('Cadena de suministro', ver='13 min · 33 preguntas'), 'ms': 2600},
          {'texto': 'Tóquelo. Arriba ve el avance; cada sección cuenta sus respuestas.',
           'corto': 'Tóquelo: arriba, el avance; cada sección cuenta sus respuestas.',
           'acciones': [tramo_btn('Cadena de suministro'), {'pausa': 500}] + centrar('% completo'), 'ms': 3400},
          {'texto': 'Responda las preguntas de la sección abierta.',
           'acciones': centrar('Commodity EUDR') + [{'elegir': ['Commodity EUDR', 'Cacao']}, {'llenar': ['Código HS', '1801']}], 'ms': 2600},
          {'texto': 'Toque el título de otra sección para abrirla.',
           'acciones': [{'clic': '1. Productor (origen)'}], 'ms': 2600},
          {'texto': 'Al terminar, toque «Guardar (offline)». Se guarda aunque no haya señal.',
           'corto': 'Toque «Guardar (offline)»: se guarda aunque no haya señal.',
           'acciones': [{'clic': 'Guardar (offline)'}], 'ms': 3000},
          {'texto': 'Para volver a la hoja de ruta, toque otra vez la norma.',
           'acciones': [{'clic': 'EU Deforestation Regulation'}], 'ms': 3000},
      ],
      cierre='Formulario guardado')

flujo(id='productor-punto-control', orden=32, **P,
      titulo='Responder un punto de control',
      resumen='Cada punto de control de la norma se responde Cumple, No cumple o No aplica.',
      gancho='¿Qué le va a revisar el auditor?', preparar=contexto() + abrir_tramo('GLOBAL G.A.P.', FV_SMART),
      pasos=[
          {'texto': 'Cada punto trae su código, su texto y su nivel: mayor o menor.',
           'acciones': centrar('FV-Smart 03.01'), 'ms': 3200},
          {'texto': 'Toque «Ver texto oficial de la norma» para leer el requisito original.',
           'corto': '«Ver texto oficial de la norma»: el requisito original.',
           'acciones': [{'clic_texto': 'Ver texto oficial de la norma'}], 'ms': 3000},
          {'texto': '«Qué revisa el auditor» le dice qué se va a verificar.',
           'acciones': [{'clic_texto': 'Qué revisa el auditor'}], 'ms': 3000},
          {'texto': 'Responda: Cumple, No cumple o No aplica.',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.01', 'Cumple']}], 'ms': 2600},
          {'texto': '«No aplica» es para un punto fuera de su alcance; cuenta como conforme.',
           'corto': '«No aplica»: punto fuera de su alcance; cuenta como conforme.',
           'acciones': centrar('FV-Smart 03.03') + [{'elegir': ['Respuesta FV-Smart 03.03', 'No aplica']}], 'ms': 3000},
      ],
      cierre='Punto de control respondido')

flujo(id='productor-adjuntar-documento', orden=34, **P,
      titulo='Adjuntar un documento como evidencia',
      resumen='Los puntos que piden evidencia aceptan PDF o imágenes, varios archivos por punto.',
      gancho='¿Le piden evidencias?', preparar=contexto() + abrir_tramo('GLOBAL G.A.P.', FV_SMART),
      pasos=[
          {'texto': 'Los puntos que piden evidencia traen el botón «Adjuntar documento o foto».',
           'corto': 'Los puntos con evidencia traen «Adjuntar documento o foto».',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.02', 'Cumple']}, {'ver': 'Adjuntar documento o foto'}], 'ms': 3000},
          {'texto': 'Tóquelo y elija el archivo: PDF o imagen, hasta 15 MB.',
           'acciones': [{'subir': [caja_archivo('sec_3.fv_smart_03_02__evidencia'), 'muestras/procedimiento-capacitacion.pdf']},
                        {'ver': 'procedimiento-capacitacion.pdf'}], 'ms': 3000},
          {'texto': '¿Viene en varias partes? Toque «Adjuntar otro archivo».',
           'acciones': [{'subir': [caja_archivo('sec_3.fv_smart_03_02__evidencia'), 'muestras/registro-capacitacion.pdf']},
                        {'ver': 'registro-capacitacion.pdf'}], 'ms': 3000},
          {'texto': 'Si se equivocó, quítelo con la × antes de guardar.',
           'acciones': [{'clic_aria': 'Quitar registro-capacitacion.pdf'}], 'ms': 2800},
          {'texto': 'Toque «Guardar (offline)»: la evidencia queda junto a su respuesta.',
           'acciones': [{'clic': 'Guardar (offline)'}], 'ms': 3000},
      ],
      cierre='Evidencia adjunta')

flujo(id='productor-foto', orden=36, **P,
      titulo='Tomar o cargar una foto de evidencia',
      resumen='Los campos de foto abren la cámara del teléfono, o dejan cargar una foto ya tomada.',
      gancho='¿Una foto vale como evidencia?', preparar=contexto() + abrir_tramo('Rainforest Alliance', 'Fertilidad y conservación del suelo'),
      pasos=[
          {'texto': 'Abra la sección que pide la foto.',
           'acciones': [{'clic': 'Cobertura del suelo y uso de fertilizantes'}], 'ms': 2400},
          {'texto': 'Toque «Tomar / cargar»: en el teléfono se abre la cámara.',
           'acciones': centrar('Tomar / cargar: Foto de la cobertura'), 'ms': 2800},
          {'texto': 'La foto aparece en miniatura junto a su nombre.',
           'acciones': [{'subir': [caja_archivo('cobertura_fertilizacion.foto_cobertura'), 'muestras/foto-cobertura-suelo.jpg']},
                        {'pausa': 400}] + centrar('foto-cobertura-suelo.jpg'), 'ms': 3200},
          {'texto': 'Puede agregar otra foto, o quitar una con la ×.',
           'acciones': centrar('Agregar otra foto'), 'ms': 2800},
          {'texto': 'Guarde: la foto queda en el dispositivo y se sube con su respuesta.',
           'acciones': [{'clic': 'Guardar (offline)'}], 'ms': 3000},
      ],
      cierre='Foto guardada como evidencia')

flujo(id='productor-poligono', orden=38, **P,
      titulo='Conectar el polígono de la finca',
      resumen='El polígono del predio se toma del visor: no hace falta volver a caminar el lindero.',
      gancho='¿Ya tiene el polígono de su finca?', preparar=contexto() + abrir_tramo('EU Deforestation Regulation', 'Polígono GPS del predio'),
      pasos=[
          {'texto': 'Abra la sección «Geometría del predio».',
           'acciones': [{'clic': 'Geometría del predio'}], 'ms': 2400},
          {'texto': 'Elija el tipo: polígono, obligatorio si el predio supera 4 ha.',
           'acciones': [{'elegir': ['Tipo de geometría', 'Polígono']}], 'ms': 2800},
          {'texto': 'Toque «Conectar polígono del visor».',
           'acciones': centrar('Polígono del predio (caminar perímetro)') + [{'clic': 'Conectar polígono del visor'}], 'ms': 2600},
          {'texto': 'El polígono queda listo y no se vuelve a capturar.',
           'acciones': centrar('Polígono dibujado en campo'), 'ms': 3200},
      ],
      cierre='Polígono conectado',
      nota='En la demostración se usa un polígono de ejemplo. Dentro de VG Suite, el botón abre el mapa del visor con el polígono real de la finca.')

flujo(id='productor-avance', orden=40, **P,
      titulo='Ver el avance y cuándo está listo para la auditoría',
      resumen='La barra de avance distingue lo respondido de lo conforme: un «No cumple» no cuenta como listo.',
      gancho='¿Ya está listo para la auditoría?', preparar=contexto() + abrir_tramo('GLOBAL G.A.P.', FV_SMART),
      pasos=[
          {'texto': 'Arriba del formulario ve el porcentaje completo y las preguntas respondidas.',
           'corto': 'Arriba: el porcentaje completo y las preguntas respondidas.',
           'acciones': [{'ver': '% completo'}], 'ms': 2800},
          {'texto': 'Al responder, el avance sube.',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.01', 'Cumple']}, {'ver': '% completo'}], 'ms': 2600},
          {'texto': 'Un «No cumple» en una obligación mayor aparece marcado.',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.02', 'No cumple']}, {'ver': 'en No cumple'}], 'ms': 3200},
          {'texto': 'Hay que resolverlo antes de la auditoría: respondido no es lo mismo que conforme.',
           'corto': 'Resuélvalo antes de la auditoría: respondido no es conforme.',
           'acciones': [{'ver': 'resuélvelos antes de la auditoría'}], 'ms': 3200},
          {'texto': 'Con la corrección hecha, cámbielo a «Cumple» y el aviso desaparece.',
           'corto': 'Corregido, cámbielo a «Cumple» y el aviso desaparece.',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.02', 'Cumple']}, {'ver': '% completo'}], 'ms': 3200},
      ],
      cierre='Su avance, sin sorpresas',
      nota='La marca «Listo para la auditoría» aparece cuando todas las obligaciones mayores cumplen y al menos el 95 % de las menores. Un formulario vacío nunca aparece como listo.')

flujo(id='productor-sin-senal', orden=42, **P,
      titulo='Capturar sin señal y revisar Mi bóveda',
      resumen='Todo se guarda primero en el dispositivo. Mi bóveda muestra qué falta subir al servidor.',
      gancho='¿Sin señal en la finca?', preparar=contexto(),
      pasos=[
          {'texto': 'Sin señal, el indicador de arriba dice «sin conexión».',
           'acciones': [{'js': SIN_SENAL}, {'pausa': 300}], 'foco': 'arriba', 'ms': 2800},
          {'texto': 'Siga capturando con normalidad.',
           'acciones': [tramo_btn('Cadena de suministro'), {'pausa': 500}] + centrar('Commodity EUDR')
                       + [{'elegir': ['Commodity EUDR', 'Café']}], 'ms': 2600},
          {'texto': 'Al guardar, el registro queda pendiente: arriba suma «1 pend».',
           'acciones': [{'clic': 'Guardar (offline)'}, {'pausa': 600}] + ARRIBA, 'foco': 'arriba', 'ms': 3000},
          {'texto': 'Toque «Mi bóveda» para ver qué está respaldado y qué no.',
           'acciones': [{'clic': 'Mi bóveda'}], 'ms': 2800},
          {'texto': 'Lo pendiente no se pierde: se sube solo al volver la señal.',
           'acciones': [{'ver': 'aún en tu dispositivo'}], 'ms': 3400},
      ],
      cierre='Sin señal, sin perder nada',
      nota='En la demostración nada se sube al servidor. Con una cuenta real, al volver la señal la app sube lo pendiente sola, y en Mi bóveda queda el botón «Sincronizar ahora».')

flujo(id='productor-sincronizar', orden=44, solo_texto=True, actor='productor', url=DEMO, probar=PUBLICA + '/',
      titulo='Respaldar en el servidor con su cuenta',
      resumen='Con una cuenta con acceso a la finca, lo capturado se sube al servidor junto con sus evidencias.',
      pasos=[
          {'texto': 'Entre con su cuenta de VG y elija su finca en «Contexto del levantamiento».'},
          {'texto': 'Al guardar con señal, la app sube la respuesta y sus archivos sola; no hace falta un botón.'},
          {'texto': 'El indicador de arriba cuenta lo pendiente (pend), lo que falló (fall) y lo subido (sync).'},
          {'texto': 'En «Mi bóveda», cada registro dice «respaldado», «en este dispositivo» o «error al subir».'},
          {'texto': 'Si algo quedó pendiente o con error, toque «Sincronizar ahora». Lo que falla no se borra: se vuelve a intentar.'},
      ],
      nota='Este flujo necesita una cuenta real con acceso a una finca: el video está en preparación.')

flujo(id='productor-mi-progreso', orden=50, **P,
      titulo='Ver Mi progreso en todas las normas',
      resumen='Un tablero con el avance de cada norma y de cada formulario, sin necesidad de señal.',
      gancho='¿Cuánto le falta en cada norma?',
      preparar=contexto() + [tramo_btn('Cadena de suministro'), {'pausa': 400}, {'elegir': ['Commodity EUDR', 'Cacao']},
                             {'llenar': ['Código HS', '1801']}, {'clic': 'Guardar (offline)'}, {'pausa': 600},
                             {'clic': 'EU Deforestation Regulation'}, {'js': 'window.scrollTo(0,0)'}],
      pasos=[
          {'texto': 'Arriba, toque «Mi progreso».', 'acciones': [{'clic': 'Mi progreso'}], 'ms': 2400},
          {'texto': 'Ve cuántos formularios empezó y cuántos están listos para entregar.',
           'corto': 'Formularios empezados y listos para entregar.',
           'acciones': [{'ver': 'formularios iniciados'}], 'ms': 3200},
          {'texto': 'Cada norma muestra su porcentaje. Tóquela para ver sus formularios.',
           'acciones': [{'clic_css': '.tcert-head'}], 'ms': 3000},
          {'texto': 'Toque un formulario para abrirlo directamente.',
           'acciones': [{'clic_css': '.tform:has-text("Cadena de suministro")'}, {'pausa': 500}] + centrar('% completo'), 'ms': 3200},
      ],
      cierre='Su avance, de un vistazo')

flujo(id='productor-vista-previa', orden=60, **P,
      titulo='Vista previa del informe para el auditor',
      resumen='Muestra cómo quedaría el informe de un formulario, como borrador con marca de agua.',
      gancho='¿Cómo lo verá el auditor?',
      preparar=contexto() + abrir_tramo('GLOBAL G.A.P.', FV_SMART) + [{'elegir': ['Respuesta FV-Smart 03.01', 'Cumple']}],
      pasos=[
          {'texto': 'Debajo del formulario, toque «Vista previa para el certificador».',
           'corto': 'Toque «Vista previa para el certificador».',
           'acciones': centrar('Vista previa para el certificador') + [{'clic': 'Vista previa para el certificador'}], 'ms': 2800},
          {'texto': 'Ve el informe con sus respuestas, tal como lo leería el auditor.',
           'foco': 'centro', 'ms': 3400},
          {'texto': 'Es un borrador con marca de agua; el informe sin marca requiere un plan de pago.',
           'corto': 'Borrador con marca de agua; sin marca, con un plan de pago.',
           'foco': 'centro', 'ms': 3400},
          {'texto': 'Toque «Cerrar» para volver al formulario.', 'acciones': [{'clic': 'Cerrar'}], 'ms': 2400},
      ],
      cierre='Revise antes de la auditoría')

# ───────────────────────── solo lectura ─────────────────────────
flujo(id='lector-solo-lectura', actor='lector', actor_txt='Solo lectura', orden=70, solo_texto=True,
      titulo='Revisar sin editar (rol de solo lectura)',
      resumen='Con el rol «Solo lectura» se revisan los formularios y la vista previa, sin modificar nada.',
      url=DEMO, probar=PUBLICA + '/',
      pasos=[
          {'texto': 'Entre con la cuenta que le compartieron. Arriba aparece su rol: «Solo lectura».'},
          {'texto': 'Elija la finca, la norma y el formulario igual que los demás usuarios.'},
          {'texto': 'El formulario muestra «Modo solo lectura»: puede leer respuestas, texto oficial y qué revisa el auditor, pero no editar ni guardar.'},
          {'texto': 'Use «Vista previa para el certificador» para ver el informe del formulario.'},
          {'texto': 'Para cambiar algo, pídaselo al responsable de la finca: su rol no guarda capturas.'},
      ],
      nota='Este flujo necesita una cuenta real con rol de solo lectura: el video está en preparación.')

if __name__ == '__main__':
    os.makedirs(DESTINO, exist_ok=True)
    for f in F:
        nombre = f"{f['orden']:02d}-{f['id']}.json"
        json.dump(f, open(os.path.join(DESTINO, nombre), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(len(F), 'flujos ·', sum(1 for f in F if not f.get('solo_texto')), 'con video')
