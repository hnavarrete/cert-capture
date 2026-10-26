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

# 5-oct-2026: la grabación destapó que lo guardado NO se retomaba (el formulario se abría vacío). Arreglado en
# CertForm + engine (getLatestState); este flujo muestra justamente eso: salir, volver y encontrar lo guardado.
flujo(id='productor-retomar', orden=35, **P,
      titulo='Salir y retomar donde quedó',
      resumen='Lo guardado vuelve a aparecer al abrir el formulario, con sus evidencias. Puede cargar por partes, en varios días.',
      gancho='¿Lo llena por partes?', preparar=contexto() + abrir_tramo('GLOBAL G.A.P.', FV_SMART),
      pasos=[
          {'texto': 'Responda lo que tenga a mano y adjunte su evidencia.',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.02', 'Cumple']},
                        {'subir': [caja_archivo('sec_3.fv_smart_03_02__evidencia'), 'muestras/procedimiento-capacitacion.pdf']},
                        {'ver': 'procedimiento-capacitacion.pdf'}], 'ms': 3000},
          {'texto': 'Toque «Guardar (offline)»: queda guardado en el dispositivo.',
           'corto': 'Toque «Guardar (offline)»: queda en el dispositivo.',
           'acciones': [{'clic': 'Guardar (offline)'}, {'ver': 'Guardado en este dispositivo'}], 'ms': 3000},
          {'texto': 'Puede salir de la app. Otro día, vuelva a abrir el mismo formulario.',
           'corto': 'Salga cuando quiera y vuelva a abrir el formulario.',
           'acciones': [{'ir': DEMO}, {'pausa': 600}] + abrir_tramo('GLOBAL G.A.P.', FV_SMART) + ARRIBA,
           'foco': 'arriba', 'ms': 3000},
          {'texto': 'Arriba le avisa que está retomando lo guardado, con la fecha.',
           'corto': 'Arriba le avisa que retoma lo guardado.',
           'acciones': centrar('Retomando lo guardado'), 'ms': 3200},
          {'texto': 'Sus respuestas y sus evidencias siguen ahí, marcadas como guardadas.',
           'corto': 'Respuestas y evidencias siguen ahí, guardadas.',
           'acciones': centrar('procedimiento-capacitacion.pdf'), 'ms': 3200},
          {'texto': 'Siga donde quedó: cada guardado es una versión nueva y las anteriores no se tocan.',
           'corto': 'Cada guardado es una versión nueva; las anteriores no se tocan.',
           'acciones': [{'elegir': ['Respuesta FV-Smart 03.03', 'No aplica']}, {'clic': 'Guardar (offline)'}],
           'ms': 3200},
      ],
      cierre='Retome donde quedó',
      nota='En el mismo equipo se retoma siempre, aun sin señal. Con su cuenta y su finca elegida, también desde otro '
           'teléfono o computadora: al abrir el formulario, la app trae lo que ya está respaldado en el servidor, con sus '
           'evidencias. Lo que quedó solo en el otro equipo, sin respaldar, no se puede traer: revise antes la barra de respaldo.')

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
      nota='En la demostración nada se sube al servidor. Con una cuenta real, al volver la señal la app sube lo pendiente sola, y en la barra de respaldo y en Mi bóveda queda el botón «Respaldar ahora».')

# 6-oct-2026: el respaldo, a la vista. Una clienta cargó semanas y nada llegó al servidor sin que nadie lo notara.
# Se graba sobre la demostración: la barra queda en amarillo («Modo demo»), que es justo el caso de la clienta.
flujo(id='productor-respaldo', orden=43, **P,
      titulo='Ver si lo mío está respaldado',
      resumen='La barra de respaldo, siempre a la vista, dice cuánto está en el servidor, cuánto solo en este equipo y qué hacer si algo falla.',
      gancho='¿Lo suyo está a salvo?', preparar=contexto(),
      pasos=[
          {'texto': 'Debajo del menú está la barra de respaldo: se ve siempre, sin abrir nada.',
           'corto': 'Debajo del menú, la barra de respaldo: siempre a la vista.',
           'acciones': [{'ver': 'lo que guarde queda solo en este equipo'}], 'foco': 'arriba', 'ms': 3200},
          {'texto': 'Guarde algo y mire la cuenta: «respaldadas» ya están en el servidor; «pendientes», solo en este equipo.',
           'corto': '«Respaldadas»: en el servidor. «Pendientes»: solo en este equipo.',
           'acciones': [tramo_btn('Cadena de suministro'), {'pausa': 500}] + centrar('Commodity EUDR')
                       + [{'elegir': ['Commodity EUDR', 'Café']}, {'clic': 'Guardar (offline)'}, {'pausa': 600}] + ARRIBA
                       + [{'ver': '1 pendiente'}],
           'foco': 'arriba', 'ms': 3600},
          {'texto': 'Si algo falta o falla, la barra dice la causa y qué hacer: iniciar sesión, elegir la finca, esperar la señal o avisar a Visión Geográfica.',
           'corto': 'Si algo falta o falla, dice la causa y qué hacer.',
           'acciones': [{'ver': 'Inicie sesión para respaldar'}], 'foco': 'arriba', 'ms': 3600},
          {'texto': 'Mi bóveda muestra cada versión: respaldada, en este dispositivo o con error.',
           'corto': 'Mi bóveda: cada versión, respaldada o no.',
           'acciones': [{'clic': 'Mi bóveda'}, {'pausa': 500}, {'ver': 'aún en tu dispositivo'}], 'ms': 3200},
          {'texto': 'Si queda algo pendiente, toque «Respaldar ahora».',
           'acciones': [{'ver': 'Respaldar ahora'}], 'ms': 3000},
      ],
      cierre='Sepa siempre qué está a salvo',
      nota='En la demostración nada se sube al servidor: la barra se queda en amarillo con «Modo demo». Con una cuenta con '
           'acceso a la finca, la barra se pone en verde («Todo respaldado en el servidor») cuando no queda nada pendiente, y '
           'en el formulario aparece «Registro encadenado: íntegro (N versiones)»: un registro encadenado propio, '
           'verificable contra sí mismo.')

flujo(id='productor-sincronizar', orden=44, solo_texto=True, actor='productor', url=DEMO, probar=PUBLICA + '/',
      titulo='Respaldar en el servidor con su cuenta y retomar desde otro equipo',
      resumen='Con una cuenta con acceso a la finca, lo capturado se sube al servidor con sus evidencias, y se retoma desde cualquier equipo.',
      pasos=[
          {'texto': 'Entre con su cuenta de VG y elija su finca en «Contexto del levantamiento».'},
          {'texto': 'Al guardar con señal, la app sube la respuesta y sus archivos sola; no hace falta un botón.'},
          {'texto': 'La barra de respaldo, debajo del menú, cuenta las versiones respaldadas y las pendientes. En verde: «Todo respaldado en el servidor».'},
          {'texto': 'Si algo falla, la barra lo dice en lenguaje llano: «Elija su finca para respaldar», «Sin conexión: se respaldará al volver» o «Su cuenta no tiene permiso de escritura en esta finca: avise a Visión Geográfica».'},
          {'texto': 'Toque «Respaldar ahora» para intentarlo en el momento. Lo que falla no se borra: se vuelve a intentar sola.'},
          {'texto': 'En otro teléfono o computadora, entre con la misma cuenta, elija la misma finca y abra el formulario: aparece lo respaldado, con sus evidencias, y el aviso «traído del servidor».'},
          {'texto': 'Arriba del formulario, «Registro encadenado: íntegro (N versiones)» confirma que las versiones del servidor cuadran entre sí: es un registro encadenado propio, verificable contra sí mismo.'},
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
          {'texto': 'Es un borrador con marca de agua; el informe sin marca es una función premium.',
           'corto': 'Borrador con marca de agua; sin marca, función premium.',
           'foco': 'centro', 'ms': 3400},
          {'texto': 'Toque «Cerrar» para volver al formulario.', 'acciones': [{'clic': 'Cerrar'}], 'ms': 2400},
      ],
      cierre='Revise antes de la auditoría')

# ───────────────────────── grupo (GlobalG.A.P. opción 2) ─────────────────────────
# src/Grupo.jsx (23-oct-2026). En el modo demostración trabaja con una asociación sintética en memoria (apiDemo): no
# escribe en la base. Cédulas y nombres ficticios.
G = dict(actor='grupo', actor_txt='Directiva del grupo', url=DEMO, probar=PROBAR, musica_estilo='eudr')
SOCIO_C = '.qms-socio:has-text("Productora demo C")'

flujo(id='grupo-registrar-socio', orden=80, **G,
      titulo='Registrar un socio del grupo (GlobalG.A.P. opción 2)',
      resumen='El registro interno de miembros que pide el QMS: cédula, productos con su área, sitios y certificador. Un socio nuevo entra como aspirante.',
      gancho='¿Lleva el registro de socios en Excel?',
      pasos=[
          {'texto': 'Arriba, toque «Mi grupo».', 'acciones': [{'clic': 'Mi grupo'}], 'ms': 2600},
          {'texto': 'Ve cuántos socios están activos, aspirantes, suspendidos y excluidos, y cuántas hectáreas suman.',
           'corto': 'Socios por estado y hectáreas activas.', 'acciones': [{'ver': 'ha de socios activos'}], 'ms': 3400},
          {'texto': 'Toque «Registrar socio».', 'acciones': [{'clic': 'Registrar socio'}], 'ms': 2400},
          {'texto': 'Escriba la cédula o el RUC y el nombre del socio.', 'corto': 'Cédula o RUC y nombre.',
           'acciones': [{'llenar': ['Cédula o RUC', '1599999920']}, {'llenar': ['Nombre del socio', 'Productora demo H']}], 'ms': 3200},
          {'texto': 'Anote cada producto con su área en hectáreas.', 'corto': 'Cada producto, con su área.',
           'acciones': [{'llenar': ['Cultivo', 'pitahaya amarilla']}, {'llenar': ['Hectáreas', '1.7']}], 'ms': 3200},
          {'texto': 'Anote el sitio y marque si está certificado.', 'corto': 'El sitio, y si está certificado.',
           'acciones': [{'llenar': ['Nombre del sitio', 'Finca demo H']}, {'llenar': ['Hectáreas del sitio', '1.7']}], 'ms': 3200},
          {'texto': 'Toque «Registrar como aspirante». Se activa después de su auditoría interna.',
           'corto': 'Entra como aspirante.', 'acciones': [{'clic': 'Registrar como aspirante'}, {'ver': 'registrado como aspirante'}], 'ms': 3600},
      ],
      nota='El registro se puede descargar para el auditor con «Descargar registro».',
      cierre='El registro del grupo, siempre al día')

flujo(id='grupo-sancionar-socio', orden=82, **G,
      titulo='Suspender o excluir a un socio',
      resumen='Un socio no se borra: se suspende o se excluye con su motivo, y el cambio queda en su historial con la fecha y quién lo hizo.',
      gancho='¿Qué pasa si un socio incumple?',
      pasos=[
          {'texto': 'Abra «Mi grupo».', 'acciones': [{'clic': 'Mi grupo'}], 'ms': 2400},
          {'texto': 'En el socio, toque «Suspender» o «Excluir».', 'corto': 'Toque «Suspender» o «Excluir».',
           'acciones': [{'clic_css': SOCIO_C + ' button:has-text("Excluir")'}], 'ms': 2800},
          {'texto': 'Escriba el motivo. Sin motivo no se puede confirmar.', 'corto': 'El motivo es obligatorio.',
           'acciones': [{'llenar': ['Motivo', 'Producto no autorizado en la bodega']}], 'ms': 3200},
          {'texto': 'Toque «Confirmar».', 'acciones': [{'clic': 'Confirmar'}, {'ver': 'Productora demo C: excluido'}], 'ms': 2800},
          {'texto': 'En «Historial» queda cada cambio con su fecha, su motivo y quién lo hizo. No se puede borrar.',
           'corto': 'El historial no se borra.',
           'acciones': [{'clic_css': SOCIO_C + ' button:has-text("Historial")'}, {'ver': 'Motivo: Producto no autorizado'}], 'ms': 3800},
      ],
      nota='Un socio excluido se puede readmitir como aspirante; el historial conserva todo.',
      cierre='Cada sanción, con su motivo')

flujo(id='grupo-autorizar-auditor', orden=84, **G,
      titulo='Autorizar al auditor del organismo certificador',
      resumen='El auditor entra en solo lectura a su grupo, hasta la fecha que usted ponga (un año como máximo). Se revoca en cualquier momento.',
      gancho='¿Viene la auditoría externa?',
      pasos=[
          {'texto': 'Abra «Mi grupo».', 'acciones': [{'clic': 'Mi grupo'}], 'ms': 2400},
          {'texto': 'Toque la pestaña «Auditores».', 'acciones': [{'pestana': 'Auditores'}], 'ms': 2600},
          {'texto': 'Escriba el correo del auditor y su organismo certificador.', 'corto': 'Correo y organismo del auditor.',
           'acciones': [{'llenar': ['Correo del auditor', 'auditor@certificador.demo']}, {'llenar': ['Organismo certificador', 'Organismo demo']}], 'ms': 3400},
          {'texto': 'Elija hasta qué fecha puede entrar: un año como máximo.', 'corto': 'Hasta qué fecha: un año como máximo.',
           'acciones': [{'ver': 'Vence el'}], 'ms': 3000},
          {'texto': 'Toque «Autorizar auditor».', 'acciones': [{'clic': 'Autorizar auditor'}, {'ver': 'Auditor autorizado'}], 'ms': 3000},
          {'texto': 'Para quitarle el acceso antes, toque «Revocar».', 'corto': '«Revocar» le quita el acceso.',
           'acciones': [{'ver': 'Revocar'}], 'ms': 3000},
      ],
      nota='Visión Geográfica activa la cuenta del auditor con el rol de auditor. El auditor ve el registro y el historial, pero no edita.',
      cierre='La auditoría, en solo lectura')

# ── auditoría interna de finca (src/AuditoriaInterna.jsx, 25-oct-2026; QMS 05.02). La demo aplica las mismas reglas del
# servidor y, sin señal, el envío falla como fallaría de verdad: el informe queda en el equipo hasta que vuelve la señal.
# «Sin señal» reversible (a diferencia de SIN_SENAL, que no vuelve): window.__vgSinSenal manda.
SENAL_OFF = ("Object.defineProperty(Navigator.prototype,'onLine',{get:()=>!window.__vgSinSenal,configurable:true});"
             "window.__vgSinSenal=true;window.dispatchEvent(new Event('offline'))")
SENAL_ON = "window.__vgSinSenal=false;window.dispatchEvent(new Event('online'))"

def firmar_js(id_lienzo, semilla):
    """Un trazo de firma con eventos de puntero reales sobre el lienzo (el dedo, en el video)."""
    return ("(() => { const c = document.getElementById(%s); c.scrollIntoView({block: 'center'}); const r = c.getBoundingClientRect();"
            " const ev = (t, x, y) => c.dispatchEvent(new PointerEvent(t, {bubbles: true, pointerId: 7, clientX: r.left + x, clientY: r.top + y}));"
            " ev('pointerdown', 18, 80); for (let x = 18; x <= r.width - 18; x += 7) ev('pointermove', x, 70 + Math.sin(x / %d) * 26 * Math.sin(x / 70));"
            " ev('pointerup', r.width - 18, 70); })()") % (json.dumps(id_lienzo), semilla)

def poner_js(selector, valor):   # fecha u otro campo controlado por React: valor nativo + evento input
    return ("(() => { const e = document.querySelector(%s); const p = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;"
            " Object.getOwnPropertyDescriptor(p, 'value').set.call(e, %s); e.dispatchEvent(new Event('input', {bubbles: true})); })()") % (json.dumps(selector), json.dumps(valor))

# El resto de los 97 puntos, de una vez (el video muestra 2 puntos a mano; el subtítulo dice que se sigue así con todos).
RESTO_CUMPLE = ("(async () => { const s = (ms) => new Promise((r) => setTimeout(r, ms));"
                " const set = (e, v) => { Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(e, v); e.dispatchEvent(new Event('input', {bubbles: true})); };"
                " for (const a of document.querySelectorAll('.ai-punto')) { if (!a.querySelector('.ai-res-b.sel')) { a.querySelector('.ai-res-b.cumple').click(); await s(4); } }"
                " await s(80); for (const t of document.querySelectorAll('.ai-punto textarea')) { if (!t.value) { set(t, 'Verificado en la finca'); await s(4); } }"
                " window.scrollTo(0, 0); document.querySelector('.ai-puntos').scrollTop = 0; })()")
PRIMER = '.ai-puntos section:first-of-type article:nth-of-type(1)'
SEGUNDO = '.ai-puntos section:first-of-type article:nth-of-type(2)'

flujo(id='grupo-planificar-auditoria', orden=87, **G,
      titulo='Planificar la auditoría interna de cada socio',
      resumen='GlobalG.A.P. pide una auditoría interna por socio y por año. Se planifica con fecha y auditor interno asignado, y se ve quién la tiene al día.',
      gancho='¿Sabe a qué socio le toca la auditoría interna?',
      pasos=[
          {'texto': 'Abra «Mi grupo» y toque la pestaña «Auditorías internas».', 'corto': '«Mi grupo» → «Auditorías internas».',
           'acciones': [{'clic': 'Mi grupo'}, {'pausa': 500}, {'pestana': 'Auditorías internas'}], 'ms': 3000},
          {'texto': 'Ve cuántos socios tienen la auditoría al día, cuántos no tienen ni plan y cuántas esperan decisión.',
           'corto': 'Al día, sin plan y por decidir.', 'acciones': [{'ver': 'sin auditoría ni plan'}], 'ms': 3600},
          {'texto': 'Abajo están los socios que no tienen auditoría vigente ni planificada.', 'corto': 'Los socios sin auditoría ni plan.',
           'acciones': centrar('Nunca auditado'), 'ms': 3000},
          {'texto': 'Toque «Planificar» en el socio, elija la fecha y escriba el correo del auditor interno.',
           'corto': 'La fecha y el correo del auditor interno.',
           'acciones': [{'clic_css': '.qms-socio:has-text("Productor demo D") button:has-text("Planificar")'}, {'pausa': 600},
                        {'ver': 'Fecha'}, {'llenar': ['Correo del auditor interno', 'tecnico@asociacion.demo']}], 'ms': 3800},
          {'texto': 'Toque «Planificar»: la auditoría le aparece a esa cuenta en «Mis auditorías».',
           'corto': 'Le aparece en «Mis auditorías».', 'acciones': [{'clic_exacto': 'Planificar'}, {'ver': 'Auditoría planificada'}], 'ms': 3400},
          {'texto': 'Si no se hará, se cancela con su motivo. Nada se borra.', 'corto': 'Se cancela con motivo; nada se borra.',
           'acciones': centrar('tecnico@asociacion.demo'), 'ms': 3200},
      ],
      nota='El auditor interno no audita su propio trabajo diario (QMS 05.02 d). Un aspirante se audita y se aprueba antes de activarlo (05.02 e).',
      cierre='Cada socio, auditado una vez al año')

flujo(id='auditor-interno-auditoria-sin-senal', actor='auditor_interno', actor_txt='Auditor interno del grupo', orden=88,
      url=DEMO, probar=PROBAR, musica_estilo='eudr',
      titulo='Hacer la auditoría interna en la finca, sin señal',
      resumen='Se descarga con señal, se hace en la finca sin señal punto por punto, firman el socio y el auditor, y el informe se envía solo al volver la señal.',
      gancho='¿En la finca no hay señal?',
      pasos=[
          {'texto': 'Antes de salir, con señal, toque «Mis auditorías»: lo asignado queda guardado en el equipo.',
           'corto': 'Con señal: «Mis auditorías» la guarda en el equipo.',
           'acciones': [{'clic': 'Mis auditorías'}, {'ver': 'guardada'}], 'ms': 3000},
          {'texto': 'En la finca, sin señal, toque «Empezar» y «Empezar la auditoría»: queda la hora de inicio.',
           'corto': 'Sin señal: «Empezar la auditoría» anota la hora.',
           'acciones': [{'js': SENAL_OFF}, {'clic_css': '.qms-socio button:has-text("Empezar")'}, {'pausa': 700},
                        {'clic_css': '#ai-empezar'}, {'pausa': 300}, {'ver': 'desde las'}], 'ms': 3200},
          {'texto': 'En cada punto toque «Cumple», «No cumple» o «No aplica». Si no cumple: qué encontró y el plazo para corregir.',
           'corto': 'Si no cumple: qué encontró y el plazo.',
           'acciones': [{'clic_css': PRIMER + ' .ai-res-b.no_cumple'}, {'llenar_ph': ['Qué se encontró', 'Sin registro']},
                        {'js': poner_js(PRIMER + ' input[type=date]', '2026-11-30')}], 'ms': 3400},
          {'texto': 'Los puntos Major llevan comentario siempre: qué se verificó.', 'corto': 'Los Major: qué se verificó.',
           'acciones': [{'clic_css': SEGUNDO + ' .ai-res-b.cumple'}, {'llenar_ph': ['Qué se verificó', 'Con título']}], 'ms': 2800},
          {'texto': 'Se sigue así con los 97 puntos. Cada toque queda guardado en el equipo.',
           'corto': 'Así con los 97 puntos; cada toque se guarda.',
           'acciones': [{'js': RESTO_CUMPLE}, {'pausa': 1000}, {'ver': '97 de 97'}], 'ms': 2800},
          {'texto': 'Toque «Cerrar y firmar»: ve el cálculo. Se exige Major 100 % y Minor 95 %.',
           'corto': 'El cálculo: Major 100 %, Minor 95 %.', 'acciones': [{'clic_css': '#ai-firmar'}, {'ver': 'cálculo preliminar'}], 'ms': 3000},
          {'texto': 'Firma el socio con el dedo, y después el auditor interno.', 'corto': 'Firman el socio y el auditor.',
           'acciones': [{'js': firmar_js('ai-fir-socio', 15)}, {'pausa': 400}, {'js': poner_js('#ai-fir-insp-n', 'Técnico del grupo')},
                        {'js': firmar_js('ai-fir-insp', 11)}, {'pausa': 300}], 'ms': 3000},
          {'texto': 'Toque «Terminar y guardar»: sin señal, queda firmada en el equipo.', 'corto': 'Sin señal: queda firmada en el equipo.',
           'acciones': [{'clic_css': '#ai-terminar'}, {'ver': 'Firmada, sin enviar'}], 'ms': 3000},
          {'texto': 'Al volver la señal, el informe se envía solo.', 'acciones': [{'js': SENAL_ON}, {'pausa': 700}, {'ver': 'Informe enviado'}], 'ms': 2800},
      ],
      nota='Después de enviado, el informe ya no se edita (QMS 05.02 f). Si el servidor no lo acepta, la app dice por qué y deja corregirlo y volver a firmar.',
      cierre='La auditoría, aunque no haya señal')

flujo(id='grupo-decidir-auditoria', orden=89, **G,
      titulo='Leer el informe de auditoría interna y decidir',
      resumen='Calidad del grupo lee el informe con el cálculo, los incumplimientos y las firmas, y decide si el socio cumple. Quien hizo la auditoría no la aprueba.',
      gancho='¿Quién aprueba la auditoría interna?',
      pasos=[
          {'texto': 'Abra «Mi grupo» y toque «Auditorías internas».', 'corto': '«Mi grupo» → «Auditorías internas».',
           'acciones': [{'clic': 'Mi grupo'}, {'pausa': 500}, {'pestana': 'Auditorías internas'}], 'ms': 2800},
          {'texto': 'En la auditoría «Por decidir», toque «Ver informe y decidir».', 'corto': 'Toque «Ver informe y decidir».',
           'acciones': [{'clic_css': '.qms-socio:has-text("Productora demo C") button:has-text("Ver informe")'}], 'ms': 2800},
          {'texto': 'El informe trae el socio, sus sitios y productos, la hora de inicio y fin, y el auditor interno.',
           'corto': 'Socio, sitios, productos, horas y auditor.', 'acciones': [{'ver': 'Inicio y fin'}], 'ms': 3400},
          {'texto': 'Ve el cálculo del cumplimiento y cada incumplimiento con su plazo.', 'corto': 'El cálculo y los plazos.',
           'acciones': centrar('Incumplimientos y plazo'), 'ms': 3400},
          {'texto': 'Abajo, las firmas del socio y del auditor interno.', 'acciones': centrar('Firmas (ii, iv)'), 'ms': 3000},
          {'texto': 'Elija «Conforme» o «No conforme» y escriba su nombre: queda en el informe.', 'corto': 'Decida y escriba su nombre.',
           'acciones': [{'llenar': ['Su nombre', 'Responsable de calidad']}], 'ms': 3400},
          {'texto': 'Toque «Guardar la decisión»: la fecha queda en el registro del socio.', 'corto': 'La fecha queda en el registro.',
           'acciones': [{'clic': 'Guardar la decisión'}, {'ver': 'Decisión guardada'}], 'ms': 3400},
      ],
      nota='«Conforme» solo se puede elegir si el cálculo cumple (Major 100 % y Minor 95 %). Quien hizo la auditoría no la aprueba (QMS 12.5 a). El informe se puede imprimir con «Imprimir».',
      cierre='Cada auditoría, revisada y firmada')

# ── incumplimientos y sanciones (src/Incumplimientos.jsx, 26-oct-2026; QMS 05.03). Demo con las mismas reglas del servidor.
NC_C = '.qms-socio:has-text("Productora demo C"):has-text("Abierta")'

flujo(id='grupo-incumplimiento-seguimiento', orden=90, **G,
      titulo='Dar seguimiento a un incumplimiento hasta cerrarlo',
      resumen='Cada «no cumple» de una auditoría interna llega solo. Se anota la acción correctiva, el responsable y el plazo, y se cierra con la evidencia.',
      gancho='¿Quién corrige lo que encontró la auditoría?',
      pasos=[
          {'texto': 'Abra «Mi grupo» y toque la pestaña «Incumplimientos».', 'corto': '«Mi grupo» → «Incumplimientos».',
           'acciones': [{'clic': 'Mi grupo'}, {'pausa': 500}, {'pestana': 'Incumplimientos'}], 'ms': 3000},
          {'texto': 'Cada «no cumple» de una auditoría interna aparece aquí solo, con su plazo.', 'corto': 'Cada «no cumple» llega solo, con su plazo.',
           'acciones': centrar('Auditoría interna · FV-Smart 03.03'), 'ms': 3400},
          {'texto': 'Toque «Acción y responsable»: qué se hará y quién responde.', 'corto': 'Qué se hará y quién responde.',
           'acciones': [{'clic_css': NC_C + ' button:has-text("Acción y responsable")'}, {'pausa': 500},
                        {'llenar': ['Acción correctiva', 'Llevar el registro diario']}, {'llenar': ['Responsable (05.03 c)', 'Técnico del grupo']}], 'ms': 3800},
          {'texto': 'Toque «Guardar».', 'acciones': [{'clic_exacto': 'Guardar'}, {'ver': 'Cambios guardados'}], 'ms': 2600},
          {'texto': 'Cuando esté corregido, toque «Cerrar» y escriba la evidencia y su nombre.', 'corto': 'Corregido: la evidencia y su nombre.',
           'acciones': [{'clic_css': '.qms-socio:has-text("Llevar el registro diario") button:has-text("Cerrar")'}, {'pausa': 500},
                        {'llenar': ['Evidencia', 'Registro de 15 días revisado']}, {'llenar': ['Su nombre', 'Calidad del grupo']}], 'ms': 3800},
          {'texto': 'Toque «Cerrar el incumplimiento»: queda con su fecha y ya no cambia.', 'corto': 'Cerrado, ya no cambia.',
           'acciones': [{'clic': 'Cerrar el incumplimiento'}, {'ver': 'Incumplimiento cerrado'}], 'ms': 3000},
      ],
      nota='También se registran a mano los incumplimientos del organismo certificador, de un reclamo o del QMS, con «Registrar incumplimiento» (QMS 05.03 a).',
      cierre='Cada incumplimiento, hasta cerrarlo')

flujo(id='grupo-sancionar', orden=91, **G,
      titulo='Sancionar a un socio y avisar al certificador',
      resumen='Advertencia, suspensión o cancelación, con motivo y nombre. La suspensión se levanta cuando su incumplimiento está cerrado.',
      gancho='¿Cómo se sanciona a un socio?',
      pasos=[
          {'texto': 'Abra «Mi grupo» y toque «Incumplimientos».', 'corto': '«Mi grupo» → «Incumplimientos».',
           'acciones': [{'clic': 'Mi grupo'}, {'pausa': 500}, {'pestana': 'Incumplimientos'}], 'ms': 2800},
          {'texto': 'En el incumplimiento, toque «Sancionar».', 'acciones': [{'clic_css': NC_C + ' button:has-text("Sancionar")'}], 'ms': 2600},
          {'texto': 'Elija advertencia, suspensión o cancelación. La suspensión es del producto entero.', 'corto': 'Advertencia, suspensión o cancelación.',
           'acciones': [{'clic_css': '.ai-radios label:has-text("Suspensión") input'}, {'pausa': 300}, {'ver': 'producto entero'}], 'ms': 3400},
          {'texto': 'Revise el motivo y escriba su nombre.', 'acciones': [{'ver': 'Motivo'}, {'llenar': ['Su nombre', 'Calidad del grupo']}], 'ms': 3000},
          {'texto': 'Toque «Registrar la sanción»: el socio pasa a suspendido.', 'corto': 'El socio pasa a suspendido.',
           'acciones': [{'clic': 'Registrar la sanción'}, {'ver': 'Sanción registrada'}], 'ms': 3000},
          {'texto': 'Anote el día en que avisó al organismo certificador.', 'corto': 'El día del aviso al certificador.',
           'acciones': centrar('Falta anotar el aviso') + [{'clic_css': '.qms-socio:has-text("Falta anotar el aviso") button:has-text("Anotar el aviso")'},
                        {'pausa': 500}, {'clic_css': '.qms-mini button.primary'}, {'ver': 'Aviso anotado'}], 'ms': 3600},
          {'texto': 'La suspensión se levanta con «Levantar», cuando su incumplimiento esté cerrado.', 'corto': '«Levantar», con el incumplimiento cerrado.',
           'acciones': centrar('Suspensión'), 'ms': 3200},
      ],
      nota='Las sanciones no se editan ni se borran (QMS 05.03 g). La cancelación pasa al socio a «excluido».',
      cierre='Cada sanción, con su registro')

# ── reclamos, retiro y balance de masas (src/ReclamosRetiro.jsx, 26-oct-2026; QMS 04, 07, 06 b).
ABRIR_RECLAMOS = [{'clic': 'Mi grupo'}, {'pausa': 500}, {'pestana': 'Reclamos y retiro'}]

flujo(id='grupo-reclamo', orden=92, **G,
      titulo='Registrar, investigar y cerrar un reclamo',
      resumen='Cada reclamo contra el grupo o un socio se registra, se investiga y se cierra con su conclusión. Los de inocuidad, trabajadores o ambiente exigen avisar al certificador.',
      gancho='¿Le llegó un reclamo de un cliente?',
      pasos=[
          {'texto': 'Abra «Mi grupo» y toque la pestaña «Reclamos y retiro».', 'corto': '«Mi grupo» → «Reclamos y retiro».', 'acciones': ABRIR_RECLAMOS, 'ms': 3000},
          {'texto': 'Toque «Registrar reclamo»: la fecha, de quién viene, el tema y contra quién.', 'corto': 'Fecha, origen, tema y contra quién.',
           'acciones': [{'clic': 'Registrar reclamo'}, {'pausa': 400}, {'elegir': ['Tema', 'Inocuidad']}, {'ver': 'Este tema exige avisar'}], 'ms': 3600},
          {'texto': 'Si es de inocuidad, trabajadores o ambiente, hay que avisar al organismo certificador.', 'corto': 'Inocuidad: avisar al certificador.',
           'acciones': [{'llenar': ['Qué dice el reclamo', 'Residuo sobre el límite en un embarque']}, {'clic_exacto': 'Registrar'}, {'ver': 'Reclamo registrado'}], 'ms': 3600},
          {'texto': 'En «Investigación», anote qué se revisó y qué se encontró.', 'corto': 'Qué se revisó y qué se encontró.',
           'acciones': [{'clic_css': '.qms-socio:has-text("Residuo sobre el límite") button:has-text("Investigación")'}, {'pausa': 400},
                        {'llenar': ['Investigación (qué se revisó', 'Registro de aplicaciones revisado']}, {'clic_exacto': 'Guardar'}], 'ms': 3600},
          {'texto': 'Anote el día del aviso al certificador.', 'acciones': [{'clic_css': '.qms-socio:has-text("Residuo sobre el límite") button:has-text("Anotar el aviso")'},
           {'pausa': 400}, {'clic_css': '.qms-mini button.primary'}, {'ver': 'Aviso anotado'}], 'ms': 3000},
          {'texto': 'Toque «Cerrar», escriba la conclusión y su nombre.', 'corto': 'La conclusión y su nombre.',
           'acciones': [{'clic_css': '.qms-socio:has-text("Residuo sobre el límite") button:has-text("Cerrar")'}, {'pausa': 400},
                        {'llenar': ['Conclusión', 'Origen identificado y corregido']}, {'llenar': ['Su nombre', 'Calidad del grupo']},
                        {'clic': 'Cerrar el reclamo'}, {'ver': 'Reclamo cerrado'}], 'ms': 3800},
      ],
      nota='Si el reclamo exige corregir algo, «Abrir incumplimiento» lo lleva a «Incumplimientos», ligado al reclamo (QMS 05.03 a).',
      cierre='Cada reclamo, con su conclusión')

flujo(id='grupo-simulacro-retiro', orden=93, **G,
      titulo='Hacer el simulacro anual de retiro de producto',
      resumen='GlobalG.A.P. pide probar el retiro una vez al año. Se registra el evento, los lotes, a quién se avisó y cuánto se localizó.',
      gancho='¿Podría retirar un lote en un día?',
      pasos=[
          {'texto': 'Abra «Mi grupo» → «Reclamos y retiro». Arriba se ve si el simulacro del año está al día.', 'corto': 'Se ve si el simulacro está al día.',
           'acciones': ABRIR_RECLAMOS + [{'ver': 'simulacro de retiro anual'}], 'ms': 3400},
          {'texto': 'Toque «Iniciar simulacro»: el evento, los lotes de VG Custody y quién decide.', 'corto': 'El evento, los lotes y quién decide.',
           'acciones': [{'clic': 'Iniciar simulacro'}, {'pausa': 400}, {'llenar': ['Evento que lo origina', 'Simulacro: residuo sobre el límite']},
                        {'llenar': ['Lotes afectados', 'L-041, L-042']}, {'llenar': ['Quién decide', 'Calidad del grupo']}], 'ms': 4000},
          {'texto': 'Toque «Iniciar»: queda la hora de inicio.', 'acciones': [{'clic_exacto': 'Iniciar'}, {'ver': 'Simulacro iniciado'}], 'ms': 2800},
          {'texto': 'En «Conciliación», anote cuánto se afectó y cuánto se localizó, y a qué clientes se avisó.', 'corto': 'Afectado, localizado y clientes avisados.',
           'acciones': [{'clic_css': '.qms-socio:has-text("Simulacro: residuo") button:has-text("Conciliación")'}, {'pausa': 400},
                        {'llenar': ['Cantidad afectada', '500']}, {'llenar': ['Cantidad localizada', '490']}, {'llenar': ['Clientes avisados', 'Exportadora']},
                        {'llenar': ['Resultado', '98 % en 2 horas']}, {'ver': 'Localizado'}], 'ms': 4200},
          {'texto': 'Toque «Guardar» y luego «Cerrar» con su nombre: queda la hora de fin.', 'corto': 'Guardar y cerrar: queda la hora de fin.',
           'acciones': [{'clic_exacto': 'Guardar'}, {'pausa': 600}, {'clic_css': '.qms-socio:has-text("Simulacro: residuo") button:has-text("Cerrar")'},
                        {'pausa': 400}, {'llenar': ['Su nombre', 'Calidad del grupo']}, {'clic': 'Cerrar el retiro'}, {'ver': 'Retiro cerrado'}], 'ms': 3800},
      ],
      nota='Un retiro real se registra igual con «Registrar retiro real», y se cierra con el aviso al organismo certificador (QMS 07 b). Uno real en los últimos 12 meses cuenta como el ejercicio del año (07 d).',
      cierre='El retiro, probado cada año')

flujo(id='grupo-balance-masas', orden=94, **G,
      titulo='Registrar el balance de masas anual',
      resumen='Uno al año por producto registrado, con lo certificado y lo no certificado por separado. Las cifras se toman del balance de VG Custody.',
      gancho='¿Cuadra lo certificado que entró y salió?',
      pasos=[
          {'texto': 'Abra «Mi grupo» → «Reclamos y retiro» y baje a «Balance de masas».', 'corto': 'Baje a «Balance de masas».',
           'acciones': ABRIR_RECLAMOS + centrar('Balance de masas (QMS 06 b)'), 'ms': 3400},
          {'texto': 'Cada producto dice si su balance del año está al día. Toque «Registrar balance».', 'corto': 'Toque «Registrar balance».',
           'acciones': [{'clic_css': '.qms-socio:has-text("pitahaya roja") button:has-text("Registrar balance")'}, {'pausa': 400}], 'ms': 3200},
          {'texto': 'Pase las cifras del balance de VG Custody: lo que entró, salió y queda.', 'corto': 'Entró, salió y queda, de VG Custody.',
           'acciones': [{'llenar': ['Entró certificado', '5000']}, {'llenar': ['Salió certificado', '4800']}, {'llenar': ['Queda certificado', '200']}], 'ms': 4000},
          {'texto': 'La diferencia se calcula sola: si no cuadra, hay que explicarlo.', 'corto': 'La diferencia se calcula sola.',
           'acciones': [{'ver': 'Diferencia en lo certificado'}], 'ms': 3000},
          {'texto': 'Escriba la conclusión y su nombre, y toque «Registrar el balance».', 'corto': 'Conclusión, nombre y registrar.',
           'acciones': [{'llenar': ['Conclusión', 'Cuadra']}, {'llenar': ['Su nombre', 'Calidad del grupo']}, {'clic': 'Registrar el balance'}, {'ver': 'Balance registrado'}], 'ms': 3600},
      ],
      nota='Registrado, el balance ya no se edita: si algo cambió, se registra otro (QMS 06 b, k).',
      cierre='Lo certificado, siempre cuadrado')

flujo(id='grupo-evidencias-ifa', orden=95, **G,
      titulo='Revisar las evidencias de la IFA de cada finca',
      resumen='Lo que cada finca respondió de la IFA de GlobalG.A.P., punto por punto y con sus documentos, en solo lectura. El auditor externo autorizado ve lo mismo.',
      gancho='¿Qué respondió cada finca?',
      pasos=[
          {'texto': 'Abra «Mi grupo» y toque la pestaña «Evidencias IFA».', 'corto': '«Mi grupo» → «Evidencias IFA».',
           'acciones': [{'clic': 'Mi grupo'}, {'pausa': 500}, {'pestana': 'Evidencias IFA'}], 'ms': 3000},
          {'texto': 'Cada finca muestra su última respuesta: cuántos puntos cumplen, no cumplen o no aplican, y sus documentos.',
           'corto': 'Cumple, no cumple, no aplica y documentos.', 'acciones': [{'ver': 'Finca demo 3'}], 'ms': 3800},
          {'texto': 'Toque «Ver punto por punto».', 'acciones': [{'clic_css': '.qms-socio:has-text("Finca demo 3") button:has-text("Ver punto por punto")'}], 'ms': 2800},
          {'texto': 'Filtre «No cumple» para ver solo lo que hay que corregir.', 'corto': 'Solo lo que no cumple.',
           'acciones': [{'clic_css': '.ev-detalle .chips button:has-text("No cumple")'}, {'pausa': 300}, {'ver': 'FV-Smart 03.02'}], 'ms': 3200},
          {'texto': 'Con «Con documento», abra cada evidencia que se subió.', 'corto': 'Abra cada documento subido.',
           'acciones': [{'clic_css': '.ev-detalle .chips button:has-text("Con documento")'}, {'pausa': 300}, {'ver': 'Registro de capacitaciones'}, {'pausa': 600}], 'ms': 4200},
      ],
      nota='Nadie edita una respuesta guardada: cada cambio queda como una versión nueva, sellada. Solo se muestran las respuestas de GlobalG.A.P.; las de otras normas del grupo no.',
      cierre='Las evidencias, a la vista del auditor')

flujo(id='auditor-revisar-grupo', actor='auditor', actor_txt='Auditor externo', orden=86, solo_texto=True,
      titulo='Revisar un grupo como auditor externo',
      resumen='Con el permiso que le dio la directiva, el auditor ve el registro de socios y su historial, sin modificar nada.',
      url=DEMO, probar=PUBLICA + '/',
      pasos=[
          {'texto': 'Entre con el correo que la directiva autorizó. La aplicación abre directamente el grupo, en solo lectura.'},
          {'texto': 'Arriba se ve hasta qué fecha tiene acceso.'},
          {'texto': 'Revise el registro de socios: estado, productos, áreas, certificador y fecha de la última auditoría interna.'},
          {'texto': 'Toque «Historial» en un socio para ver sus cambios de estado con fecha, motivo y quién los hizo.'},
          {'texto': 'Use «Descargar registro» para llevarse el registro interno de miembros.'},
          {'texto': 'En la pestaña «Auditorías internas» ve el cronograma y abre cada informe, con su cálculo, sus incumplimientos, las firmas y quién lo aprobó.'},
          {'texto': 'En «Incumplimientos» ve cada uno con su acción correctiva, su responsable, su plazo y su cierre, y las sanciones con el aviso al certificador.'},
          {'texto': 'En «Reclamos y retiro» ve los reclamos con su investigación, los simulacros y retiros con su conciliación, y el balance de masas de cada producto.'},
          {'texto': 'En «Evidencias IFA» ve lo que cada finca respondió de la IFA, punto por punto, y abre sus documentos. Solo ve lo de GlobalG.A.P.'},
      ],
      nota='Este flujo necesita una cuenta real de auditor autorizada por un grupo: el video está en preparación.')

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
