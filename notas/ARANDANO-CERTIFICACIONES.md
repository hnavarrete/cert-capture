# Arándano en Certificaciones: neutralidad de cultivo en RFA y evaluación para exportar a EE. UU.

**Versión 1 · Actualizado el martes 10 de noviembre de 2026, 18:30** (hora de Ecuador, leída del reloj de la máquina)

> **Uso interno.** Esta carpeta `docs/` es la que publica `cert.visiongeografica.com` (GitHub Pages). Antes de
> fusionar esta rama y hacer *push*, mover este archivo a una carpeta que no se publique.

**Contexto.** Una asociación de productores de arándano de la Sierra ecuatoriana (prospecto) evalúa la app:
unos 30 productores y 400 ha entre 2.600 y 3.000 m; el 95 % en maceta o funda con sustrato, bajo invernadero o
macrotúnel; más del 90 % se exporta a EE. UU. El nombre del prospecto queda en el expediente interno, no aquí.

**Marcas.** [V] verificado en la fuente citada el 10-nov-2026 · [S] fuente secundaria (prensa, certificadora,
consultora) · [NV] no verificado: estimación o dato que no se pudo confirmar en la fuente oficial.

---

## Parte A · Auditoría de neutralidad de cultivo en Rainforest Alliance (RFA)

### A.1 El conteo real de «cacao»

Medido sobre `src/schemas.bundle.json` en `master` (commit `468e871`), sin distinguir mayúsculas:

| Alcance | «cacao» |
|---|---|
| **Los 10 formularios RFA** (`rfa_01` … `rfa_10`) | **10** |
| Los 10 RFA + los 4 compartidos que el manifiesto RFA les suma | 16 |
| **Todo el bundle** (70 formularios + manifiestos + rutas + referencias) | **241** |

**Las 241 son del bundle entero, no de RFA.** Desglose: formularios 212 (Fairtrade 145, Marbete Agrocalidad 14,
RFA 10, EUDR 9, compartidos 9, registros de campo 9, USDA Organic 8, GUIA Agrocalidad 6, perfil general 2),
manifiestos 10, rutas 8 y referencias (tabla de precios Fairtrade) 11.

Las 10 de RFA están en solo tres formularios: `rfa_01` (1), `rfa_02` (3) y `rfa_10` (6). Los otros siete no la
mencionan. Las 6 de los compartidos son citas a la «Guía de BPA para Cacao» de Agrocalidad (Res. Técnica
0183/2012) en `fuente_normativa` y en textos de ayuda.

Después de los dos commits de esta rama el conteo en RFA queda en **12**: salen 2 (los dos textos de clase a) y
entran 4, porque las dos listas de cultivo nuevas incluyen la opción «Cacao» (valor `CACAO`, etiqueta «Cacao»).

### A.2 Clasificación de las 10 apariciones en los formularios RFA

Clases: **(a)** solo redacción · **(b)** requisito propio del cacao que no aplica al arándano en maceta ·
**(c)** el requisito aplica, pero necesita redacción para el arándano.

| # | Formulario | Pregunta (ruta) | Dónde | Clase |
|---|---|---|---|---|
| 1 | `rfa_01_gestion_finca` | `identificacion.cultivo_principal` | `help` | **a** |
| 2 | `rfa_02_trazabilidad` | `producto_certificado.tipo_producto` | `placeholder` | **a** |
| 3 | `rfa_02_trazabilidad` | `producto_certificado.admite_mass_balance` | `help` | **c** |
| 4 | `rfa_02_trazabilidad` | sección `mass_balance` | `descripcion` | **b** (ya condicionada) |
| 5 | `rfa_10_ingresos_familiares` | sección `diferencial` | `descripcion` | **b** |
| 6–10 | `rfa_10_ingresos_familiares` | `diferencial.prima_minima_cacao_ref` | `key`, `label`, opción `no_cacao` (valor y etiqueta), `help` | **b** |

**Totales: clase a = 2 · clase b = 7 · clase c = 1.**

Notas:

- **#4** ya se comporta bien: la sección `mass_balance` tiene `show_if: producto_certificado.admite_mass_balance = true`.
  Si el productor de arándano responde «No», la sección no aparece.
- **#6–10** son cinco apariciones de **un solo campo**. Es opcional (`required: false`) y ya tiene la salida «No
  aplica (cultivo distinto de cacao)». Funciona hoy, pero le muestra al productor de arándano una pregunta que no es
  suya. La clave `prima_minima_cacao_ref` y el valor `no_cacao` **no se renombran**: son identificadores de datos ya
  guardados.
- Las 6 de los compartidos, si se cuentan en el paquete, son de **clase c**: la referencia nacional citada es la guía
  de BPA del cacao. Para el arándano corresponde la guía de BPA que Agrocalidad aplique a ese cultivo, y esa guía no
  se pudo identificar [NV] (ver B.3).

### A.3 Lo que no dice «cacao» pero sí depende del cultivo

Buscado en los 10 formularios RFA (sombra, fermentación, secado, grano, racimo, tallo, suelo, etc.):

- **No hay preguntas de fermentación ni de secado.** La búsqueda no encontró ninguna.
- **Árboles de sombra** (`rfa_05`, sección `encuesta_indicadores_arboles`): es el indicador oficial de RA y aplica a
  todo cultivo. Si se responde «No» a `tiene_arboles_sombra`, las preguntas que siguen se ocultan (`show_if`).
  No hay que cambiarlo.
- **`RA_6_2_3`, cobertura de vegetación natural** (mínimo 10 %, o 15 % en cultivos de sombra): **aplica al arándano y
  es un riesgo real** para fincas intensivas bajo cubierta. Es clase c: la ayuda debería aclarar que se mide sobre la
  finca, no dentro del invernadero.
- **Suelo, capítulo 4.4** (`rfa_06`: `RA_4_4_1` evaluación de suelo, `RA_4_4_5` suelo no expuesto, `RA_4_6_5_erosion`):
  aplican, pero en maceta con sustrato hay que leerlos sobre el sustrato y sobre el suelo entre camas. Son de clase c.
- **Volumen en tallos** (`rfa_02`: `volumen_estimado_tallos` y `volumen_cosechado_tallos`): son para banano y flores.
  Al arándano no le aplican; el productor usa los campos en kg.

### A.4 Requisitos de RA 2020 que faltan en los formularios y le importan al arándano

Se comparó el índice del documento oficial de requisitos para fincas (SA-S-SD-1, versión 1.1) con los códigos
`RA_x_y_z` de los 10 formularios. Los formularios cubren 1.1–1.4, 2.1–2.3, 3.1–3.3, 4.3–4.6, 5.1–5.7 y 6.1–6.9.
**Faltan secciones enteras:**

| Sección RA 2020 | ¿Aplica al arándano? |
|---|---|
| **1.5 Mecanismo de quejas** | Sí, a todo cultivo |
| **1.6 Igualdad de género** | Sí, a todo cultivo |
| 1.7 Jóvenes agricultores y trabajadores | Sí; el documento la marca como autoseleccionada |
| **4.1 Siembra y rotación** (variedades, sistema de cultivo) | Sí; en el arándano pesan las variedades con regalía y la planta certificada |
| 4.2 Poda y renovación de **cultivos arbóreos** | La poda es central en el arándano, pero la sección habla de árboles. Se debe confirmar con la certificadora [NV] |
| **4.7 Cosecha y poscosecha** (incluye **4.7.2, límites máximos de residuos** del país de destino) | **Sí, y es crítica para exportar a EE. UU.** |
| 5.8 Comunidades (derechos de uso de la tierra) | Sí, a todo cultivo |

Fuente del índice: [RA 2020 Farm Requirements v1.1, copia de Preferred by Nature](https://preferredbynature.org/sites/default/files/2020-Sustainable-Agriculture-Standard_Farm-Requirements_Rainforest-Alliance.pdf) [S]. Se consultó el 10-nov-2026.
Los formularios citan anexos v1.3 y v1.4. Que la numeración no cambió en la versión vigente queda [NV].
Tampoco se confirmó en una fuente oficial que el arándano esté dentro del alcance de cultivos de RA [NV]. El manual
técnico del arándano que usa VG nombra RA entre los sellos posibles (`FICHA_ARANDANO.md` §13).

### A.5 Lista de cambios precisa

| Formulario | Pregunta | Texto actual → propuesta | Estado |
|---|---|---|---|
| `rfa_01_gestion_finca` | `identificacion.cultivo_principal` (`help`) | «Cacao, banano, café u otro cultivo del alcance del certificado.» → «Cultivo incluido en el alcance del certificado.» | **Hecho** (`83e120f`) |
| `rfa_02_trazabilidad` | `producto_certificado.tipo_producto` (`placeholder`) | «Cacao en grano seco» → «p. ej. fruta fresca, grano seco» | **Hecho** (`83e120f`) |
| `rfa_01_gestion_finca` | `identificacion.cultivo_principal` (`opciones`) | Lista vacía (select inutilizable) → 10 opciones: BANANO, CACAO, CAFE, PALMA_AFRICANA, MACADAMIA, ARANDANO, PITAHAYA, AGUACATE, FLORES, OTRO | **Hecho** (`d2dfe0e`) |
| `rfa_02_trazabilidad` | `producto_certificado.cultivo` (`opciones`) | Lo mismo | **Hecho** (`d2dfe0e`) |
| `rfa_02_trazabilidad` | `producto_certificado.admite_mass_balance` (`help`) | «Solo ciertos cultivos (p. ej. cacao) admiten mass balance…» → «Solo algunos productos admiten balance de masa (p. ej. cacao). La fruta fresca se vende normalmente con separación física; si es así, responda No.» | Propuesto. Confirmar antes en el anexo de trazabilidad vigente si la fruta fresca admite balance de masa [NV] |
| `rfa_02_trazabilidad` | sección `mass_balance` | Sin cambio: ya se oculta con `admite_mass_balance = No` | — |
| `rfa_10_ingresos_familiares` | sección `diferencial` (`descripcion`) | Separar la frase de la prima mínima del cacao en un campo `nota` aparte, «Solo cacao: …», y **ocultarlo para cultivos ≠ cacao** | Propuesto; requiere el diseño de A.6 |
| `rfa_10_ingresos_familiares` | `diferencial.prima_minima_cacao_ref` | **Ocultar para cultivos ≠ cacao** (`show_if` sobre el cultivo). Clave y valores sin cambio | Propuesto; requiere A.6 |
| `rfa_05_conservacion_natural` | `conservacion_vegetacion.RA_6_2_3` (`help`) | Agregar: «En cultivos bajo cubierta, la vegetación natural se mide sobre el área total de la finca, no dentro del invernadero.» | Propuesto (clase c). La regla de medición está [NV] |
| `rfa_06_suelos_nutrientes` | `RA_4_4_1`, `RA_4_4_5`, `RA_4_6_5_erosion` (`help`) | Agregar: «En cultivo en maceta o funda: evaluar el sustrato (pH, CE, drenaje) y el suelo entre camas.» | Propuesto (clase c) |
| `rfa_02_trazabilidad` | `volumen_estimado_tallos`, `volumen_cosechado_tallos` | **Ocultar si el cultivo no es BANANO ni FLORES** | Propuesto; requiere A.6 |
| `shared_manejo_integrado_plagas`, `shared_manejo_agua`, `shared_conservacion_biodiversidad` | `fuente_normativa` y ayudas que citan «BPA Cacao, Res. 0183/2012» | Citar «guía de BPA de Agrocalidad del cultivo (cacao: Res. Técnica 0183/2012)» | Propuesto; falta identificar la guía que aplica al arándano [NV] |
| `manifiestos.RFA.cultivos` | `["BANANO","CACAO","PALMA_AFRICANA","MACADAMIA","CAFE"]` | Agregar `ARANDANO` | Propuesto. Hoy el código de la app no lee este campo |
| Nuevas secciones | 1.5, 1.6, 4.1, 4.7 (y 1.7, 4.2, 5.8) | Transcribir del documento oficial vigente | Propuesto. Ver A.4 |

### A.6 ¿Tiene la app cómo condicionar preguntas por cultivo?

**Lo que existe**, leído del código:

- `show_if` por sección y por campo (`src/eudr-react/CertForm.jsx`, función `visible`), con `eq`, `neq`, `in`,
  `not_in`, `gt`, `lt`, `truthy`, `and` y `or`. **Solo se evalúa contra las respuestas del MISMO formulario**
  (`liveData`). No hay contexto de finca ni de cultivo.
- **No hay variables de plantilla** (nada del tipo `{{cultivo}}`) en los textos.
- El patrón que ya se usa para el contenido propio de un cultivo es **un formulario aparte por cultivo**: Fairtrade
  tiene `fairtrade_producto_cacao`, `_cafe`, `_banano` y `_flores`.
- **Pitahaya y aguacate no tienen ningún tratamiento propio.** La pitahaya aparece solo como dato de demostración en
  `Grupo.jsx` (GlobalG.A.P. opción 2). El aguacate no aparece en ninguna parte.
- **Fallo encontrado y corregido:** `rfa_01.cultivo_principal` y `rfa_02.producto_certificado.cultivo` eran
  `picklist_catalogo` obligatorios **sin opciones**, así que la app pintaba un select vacío. Nadie podía declarar su
  cultivo. Se corrigió en `d2dfe0e`. Hay otros cinco `picklist_catalogo` sin opciones en el bundle (`rfa_07`, `usda_*`,
  `shared_manejo_integrado_plagas`, `marbete_insumos`) que no se tocaron.

**Diseño mínimo propuesto (no implementado):**

1. `App.jsx` pasa a `CertForm` un `contexto = { cultivo }`, tomado del cultivo de la finca o, si falta, de la
   respuesta guardada en `rfa_01 identificacion.cultivo_principal`.
2. `CertForm` lo mezcla en `liveData` como `__ctx.cultivo`. La función `visible` no cambia: basta un
   `show_if: { campo: '__ctx.cultivo', op: 'eq', valor: 'CACAO' }`.
3. **Sin cultivo conocido se muestra todo**, como hoy. Así nada desaparece por error.
4. `progresoDe` **hoy cuenta también los campos ocultos**. Para no castigar al productor de arándano, debe saltarse lo
   que `visible` oculta. Sin este paso, ocultar un campo baja el porcentaje de avance.
5. Las descripciones de sección no se pueden condicionar. La frase de la prima del cacao pasa a un campo `nota` con su
   propio `show_if`.

Esfuerzo: **S** (dos archivos de código y unos 4 `show_if` en el bundle). Hay que llevarlo también a la fuente.

**Ojo con la fuente.** El bundle se genera desde `encuestador-eudr/frontend/src/form-schemas`.
`scripts/update-bundle.mjs` solo **agrega** formularios nuevos y no pisa los existentes, así que los cambios de esta
rama se conservan. Pero la fuente sigue con el texto viejo y sin opciones: si alguien regenera el bundle desde cero, los
cambios se pierden. Hay que llevarlos a la fuente; esa es otra sesión y otro repositorio.

---

## Parte B · Evaluación para exportar arándano a EE. UU.

### B.1 PrimusGFS

| Pregunta | Respuesta | Marca y fuente (consultadas el 10-nov-2026) |
|---|---|---|
| Versión vigente | **v3.2**, obligatoria para auditorías desde el 1-mar-2022 | [V] [azzule.com/primusgfs](https://azzule.com/primusgfs/) |
| Versión 4.0 | Reglamento general publicado (PGFS-ND-030, 31-jul-2025, Rev. 0). Azzule anunció la versión final y su fecha obligatoria «para 2026» | [V] [Reglamento v4.0, copia en primusauditingops.com](https://primusauditingops.com/wp-content/uploads/2025/08/PGFS-ND-030-R0-PrimusGFS-v4.0-General-Regulations-1.pdf) · [Resumen de cambios v4.0 (Azzule)](https://pages.azzule.com/rs/136-JVI-505/images/PrimusGFS%20v4.0%20Summary%20of%20Changes.pdf?version=0) · [Avance v4, 4-mar-2025](https://azzule.com/primusgfs-version-4-preview-is-coming-soon/) |
| ¿Ya es obligatoria la v4.0? | **No se pudo confirmar.** `primusgfs.com` responde 403 con un control antibots. QIMA (mar-2026) dice que no antes de 2027 | [NV] · [S] [QIMA](https://www.qima.com/blog/primusgfs/primusgfs-version-4-whats-changing-and-how-to-prepare) |
| GFSI | GFSI lista **PrimusGFS v3.2** como reconocido contra los requisitos **v2020**, en los alcances BI, BII, BIII, CII, CIII, CIV y G. La v4.0 no aparece todavía entre los reconocidos contra v2024 | [V] [mygfsi.com, programas reconocidos](https://mygfsi.com/how-to-implement/recognition/certification-programme-owners/) |

**Módulos** (v4.0, §9.2 del reglamento [V]; en v3.2 son los mismos 1 a 7 [V azzule.com]):

| Módulo | Para la asociación |
|---|---|
| 1 · Sistema de gestión de inocuidad (FSMS) | **Obligatorio siempre** |
| 2 · Finca (antes «Ranch») | Macrotúnel y campo. Si el macrotúnel cuenta como Finca o como Interior lo decide la certificadora [NV] |
| 3 · Agricultura bajo techo (antes «Greenhouse») | **Invernadero.** La v4.0 suma secciones de agricultura en ambiente controlado (CEA) |
| 4 · Cuadrilla de cosecha | Si hay cuadrillas propias o contratadas |
| 5 · Instalación (empacadora, frío, almacén) | **Empacadora** |
| 6 · HACCP | **Obligatorio en toda instalación** |
| 7 · Controles preventivos (FSMA PCHF) | Voluntario; aplica a instalaciones que exportan a EE. UU. |
| 8 · Granos y leguminosas | No aplica |
| 9 · Manejo integrado de plagas | Opcional |

**Combinación típica del productor con empaque: 1 + 3 (o 2) + 4 + 5 + 6, y 7 si el comprador lo pide.**
Es una inferencia a partir del reglamento: se confirma con la certificadora.

**Documentos y licencia.** Azzule dice que los documentos de v3.2 se consultan y descargan en
`primusgfs.com/pgfs-v3-2/` [V azzule.com]; no se pudo abrir esa página (403). Los PDF de v4.0 (reglamento y
«Questions & Expectations» por módulo) circulan en línea sin registro. Todos llevan **«© 2025 Primus Group, Inc. All
rights reserved»** [V, en el PDF del reglamento].

Los [Términos de uso de Azzule](https://azzule.com/terms/) [V] prohíben copiar, reproducir y hacer obras derivadas
de sus «Materials». También prohíben usarlos «para construir un producto o servicio similar o competidor». Esos
términos hablan de los miembros, y no está claro si alcanzan a los documentos públicos.

**Conclusión para VG:** no se puede transcribir el checklist en la app sin permiso escrito. Lo que se puede construir
sin licencia es una autoevaluación con **redacción propia**, organizada por módulo y por tema, que remita al número de
pregunta. **Antes de construir hay que pedirle licencia a Azzule.** Esto no es una opinión legal.

**Costo.** No hay tarifa publicada: se cotiza según el tipo de sitio, su tamaño y su complejidad
([SCS](https://www.scsglobalservices.com/services/primusgfs-certification) [S]). La duración de referencia es de
½ a 1 día por finca y de 1 a 1½ días por instalación
([NSF](https://www.nsf.org/food-beverage/food-agriculture-aquaculture-fisheries/agriculture-crops/primusgfs) [S]).
PrimusLabs cobra USD 40 por cada auditoría subida a su sistema
([primuslabs.com](https://primuslabs.com/modules/services/auditRelationship.aspx) [S]).
**Orden de magnitud estimado: de unos pocos miles de USD por operación al año, con viáticos del auditor. [NV]:
no hay cifra publicada; pedir cotizaciones.**

**¿Lo exigen los compradores de EE. UU.?** Lo que exigen es una **certificación reconocida por GFSI**, no
PrimusGFS en particular. Walmart pide GFSI a sus proveedores de producto fresco importado y, en berries congeladas, a
toda la cadena. Costco usa auditorías GFSI con su propio anexo. Ambas cosas vienen de
[Kiwa-ASI](https://www.asifood.com/kiwa-asi-blog-2026/walmart-food-supplier-requirements) y de
[Greenhouse Grower](https://www.greenhousegrower.com/management/what-kind-of-food-safety-audit-do-you-need-heres-what-to-know/) [S].
Las páginas públicas de Walmart dieron 404 al consultarlas, así que queda [NV] en la fuente primaria.
**PrimusGFS y GLOBALG.A.P. IFA GFS cumplen por igual el requisito GFSI en finca (alcance BI).** Que los importadores
de arándano de EE. UU. prefieran PrimusGFS es [NV]: hay que preguntárselo a los compradores de la asociación.

**FSMA (FDA).**

- La **Regla de Inocuidad de Productos Agrícolas** cubre el producto fresco. El arándano **no** está en la lista de
  productos que rara vez se consumen crudos, que son los exentos.
  [FDA, Produce Safety Rule](https://www.fda.gov/food/food-safety-modernization-act-fsma/fsma-final-rule-produce-safety) [V].
  La página no dice de forma expresa cómo alcanza a los productores extranjeros [NV].
- La **Regla de Trazabilidad (FSMA 204)** no nombra el arándano entero en su lista. Sí incluye «Fruits (fresh-cut)».
  [FDA, Food Traceability List](https://www.fda.gov/food/food-safety-modernization-act-fsma/food-traceability-list) [V].
  La FDA no la hará cumplir antes del **20-jul-2028**.
  [FDA, regla de trazabilidad](https://www.fda.gov/food/food-safety-modernization-act-fsma/fsma-final-rule-requirements-additional-traceability-records-certain-foods) [V].

### B.2 GLOBALG.A.P. IFA v6, Fruta y Verdura

**Ediciones** ([GFSI](https://mygfsi.com/how-to-implement/recognition/certification-programme-owners/) [V]):

- **IFA v6 GFS (Plants)** está reconocida por GFSI en los alcances BI y BIII. Es la edición que pide un comprador
  de EE. UU.
- **Smart** no tiene reconocimiento GFSI.
- **PHA** (Produce Handling Assurance), v1.2, sí está reconocida (BI, BIII). Es la vía de GLOBALG.A.P. para una
  empacadora que maneja la fruta de varios productores.

Documento oficial: [IFA GFS PCs FV v6.0-GFS_Aug24](https://documents.globalgap.org/documents/240902_IFA_GFS_PCs_FV_v6_0_Aug24_en.pdf)
(publicado el 2-sep-2024; reemplaza la 5.4-1-GFS desde el 1-ene-2025) [V].

**Lo que aplica en especial a las berries en sustrato** [V, mismo documento]:

| Código | Contenido | Nivel |
|---|---|---|
| FV-GFS 28.03.01 | Participar en el reciclaje del sustrato (registros de fechas y cantidades) | Recomendación |
| FV-GFS 28.03.02 | Registrar los químicos usados para esterilizar sustrato que se reutiliza; preferir vapor u otras alternativas no químicas | Minor |
| FV-GFS 28.03.03 | El sustrato natural no viene de áreas de conservación; considerar menos turba | Minor |
| FV-GFS 29 | Fertilizantes y bioestimulantes, incluida la fertirrigación y la hidroponía | varios |
| FV-GFS 30 | Agua: análisis de riesgo, calidad, **agua recirculada (30.05.05)** y bandejas de drenaje | varios |
| FV-GFS 26 · 32 · 33 | Material de propagación · productos fitosanitarios · manejo poscosecha y empaque | varios |

**Cobertura de los 4 formularios GGAP de cert-capture**: se compararon los códigos con el PDF oficial mediante una
extracción automática del texto. Conviene confirmar los números contándolos a mano.

| Formulario | Título | Cobertura |
|---|---|---|
| `globalgap_fv_gfs` | IFA Fruta y Verdura (P&C v6 GFS) | **191 de 191** puntos de control del documento Aug24 (ninguno falta), incluidos los 28.03.0x de sustrato |
| `globalgap_fv_smart` | IFA Fruta y Verdura (Smart) | **97 de ≈190** del documento [IFA Smart PCs FV v6.0 Sep22](https://documents.globalgap.org/documents/220929_IFA_Smart_PCs_FV_v6_0_Sep22_en.pdf). Faltan del todo los capítulos 1, 2, 4, 6–9, 14, 17, 18, 24, 26, 28, 29 y 31, y otros quedan incompletos |
| `globalgap_qms` | QMS, certificación grupal (opción 2) | 136 puntos de control (Smart QMS v6.0). Encaja con una asociación de 30 productores |
| `globalgap_coc` | Cadena de Custodia v6.1 | Para quien comercializa el producto certificado; a la finca no le aplica |

**Brechas para el arándano:**

1. **Smart está a medias.** Si la asociación entra por Smart, falta casi la mitad, incluidos sustrato (28), fertilizantes
   (29) y manejo de plagas (31). Para EE. UU. conviene ir directo a GFS, que está completa.
2. No hay ayuda para el arándano: sustrato de fibra de coco, drenaje (volumen, CE, pH), fertirriego y límites de
   residuos para EE. UU. El auditor pide esas evidencias.
3. **No hay formulario PHA.** Hace falta si la empacadora es compartida y no pertenece a cada productor.
4. Tampoco está el complemento social **GRASP**. El manual del arándano lo menciona entre lo que piden los compradores
   (`FICHA_ARANDANO.md` §13); su vigencia en v6 queda [NV].
5. **Licencia de GLOBALG.A.P.** Sus documentos dicen: «Copying and distribution permitted only in unaltered form» [V,
   pie del PDF]. Los formularios de la app transcriben el criterio literalmente, pero le agregan una etiqueta en
   español y una lista de «qué revisa el auditor» derivada de él. Hay que confirmar con GLOBALG.A.P. si eso está
   permitido en un producto de software. Esto afecta a lo que ya está publicado, no solo al arándano.

### B.3 Un escalón previo a GLOBALG.A.P. para la asociación

| Opción | Qué es | ¿Sirve en Ecuador? |
|---|---|---|
| **BerryGAP (Aneberries, México)** | Aneberries lo presenta como «el protocolo de inocuidad propio de la industria»: una guía de BPA para la producción, la cosecha, el empaque en campo y el transporte de berries. **«No es una certificación»**, sino el primer paso hacia una certificación global. [V] [aneberries.mx/inocuidad](https://aneberries.mx/inocuidad/). El nombre «BerryGAP» y la cifra de 400 productores vienen de la prensa ([Portal Frutícola](https://www.portalfruticola.com/?p=614717), [The Food Tech](https://thefoodtech.com/archivo/el-mercado-de-las-berries-en-mexico-entrevista-con-juan-jose-flores-presidente-de-aneberries/)) [S]. El documento de la norma no es público [NV] | **No directamente.** Es un programa interno de una asociación mexicana para sus socios. Lo que se puede copiar es **la idea**: un protocolo propio de la asociación ecuatoriana |
| **GLOBALG.A.P. Primary Farm Assurance** (antes localg.a.p.) | Subconjunto de IFA v6 Smart, en tres niveles (entrada, intermedio, avanzado). Hoy cubre solo frutas y hortalizas. Un organismo aprobado evalúa cada año y emite una **carta de conformidad** (no un certificado). Pasa con 100 % de los Major y ≥ 95 % de los Minor. Admite grupos. Normas y listas de verificación (XLSX) gratuitas, también en español. **Sin reconocimiento GFSI**: sirve para mercados locales o regionales. [V] [globalgap.org, PFA](https://globalgap.org/what-we-offer/solutions/primary-farm-assurance/) · [Reglamento PFA v6.0 (11-sep-2024)](https://documents.globalgap.org/documents/240911_PFA_GR_v6_Sep24_en.pdf) | **Sí, como escalera de capacitación.** No basta para un comprador de EE. UU. Que haya un organismo aprobado para PFA en Ecuador queda [NV] |
| **Certificado BPA de Agrocalidad (ARCFZ)** | Certificado nacional de Buenas Prácticas Agropecuarias en fase primaria. **Sin costo.** Vigencia de 3 años, o 1 año si se obtiene por equivalencia (la propia página se contradice). **Reconoce la equivalencia con GLOBALG.A.P.** Exige estar registrado en el Sistema GUIA. [V] [gob.ec, trámite BPA](https://www.gob.ec/arcfz/tramites/solicitud-certificado-buenas-practicas-agricolas) (actualizado el 5-ago-2025) | **Sí: es el equivalente ecuatoriano más directo.** No se encontró una guía BPA propia del arándano [NV]. La [guía general de BPA para productos agrícolas del MAG](https://trazabilidad.agricultura.gob.ec/wp-content/uploads/2025/03/GU%C3%8DA-DE-BUENAS-PR%C3%81CTICAS-AGROPECUARIAS-PARA-PRODUCTOS-AGR%C3%8DCOLAS.pdf) dio 404 al descargarla [NV] |

**Lectura:** el escalón se arma con dos piezas, sin copiar BerryGAP. La primera son los niveles PFA, que son públicos,
están en español y son un subconjunto de IFA. La segunda es el certificado BPA de Agrocalidad, gratuito y equivalente a
GLOBALG.A.P. La app ya tiene un formulario del Sistema GUIA (`guia_agrocalidad_registro_operador`, hoy con cultivo
CACAO).

### B.4 Recomendación: qué construir primero en cert-capture

| Orden | Qué | Esfuerzo | Por qué |
|---|---|---|---|
| 1 | **Perfil arándano sobre GLOBALG.A.P. IFA v6 GFS + QMS opción 2**: ayudas y evidencias propias del arándano (sustrato, drenaje, fertirriego, límites de residuos para EE. UU., planta certificada) sobre los 191 puntos que ya están; grupo de 30 productores en `Grupo.jsx` | **M** | El formulario está completo y es GFSI: cumple lo que pide el comprador de EE. UU. La opción 2 encaja con la asociación, y la equivalencia con el BPA de Agrocalidad sale sola |
| 2 | **Escalón previo**: marcar en los formularios GFS y Smart qué puntos pertenecen a cada nivel PFA, más un tablero «nivel alcanzado». Incluye el trámite BPA de Agrocalidad | **S–M** | Puerta de entrada barata para los productores que todavía no pagan GLOBALG.A.P. Reutiliza puntos que ya están en la app; no crea formularios nuevos |
| 3 | **Empacadora**: PHA de GLOBALG.A.P. o PrimusGFS Módulos 1 + 5 + 6 (+ 7), según lo que pidan los importadores | **L** | Solo si un comprador lo exige. PrimusGFS requiere antes una licencia de Azzule (B.1) |
| 4 | **RFA neutral al cultivo**: el diseño mínimo de A.6 y las secciones 1.5, 1.6, 4.1 y 4.7 | **S** (`show_if`) + **M** (secciones) | Solo si algún comprador pide el sello RA. Para el arándano que va a EE. UU., RA es secundario frente a la inocuidad GFSI |

Antes del paso 1 hay que **completar o retirar el formulario Smart**: hoy promete una cobertura que no tiene.

---

## Fuentes consultadas el 10-nov-2026

- Azzule, PrimusGFS: https://azzule.com/primusgfs/ · avance v4: https://azzule.com/primusgfs-version-4-preview-is-coming-soon/ · términos: https://azzule.com/terms/
- PrimusGFS v4.0, reglamento general (PGFS-ND-030, Rev. 0, 31-jul-2025): https://primusauditingops.com/wp-content/uploads/2025/08/PGFS-ND-030-R0-PrimusGFS-v4.0-General-Regulations-1.pdf
- PrimusGFS v4.0, resumen de cambios: https://pages.azzule.com/rs/136-JVI-505/images/PrimusGFS%20v4.0%20Summary%20of%20Changes.pdf?version=0
- primusgfs.com: **no accesible** (403, control antibots). No se intentó sortear.
- GFSI, programas reconocidos: https://mygfsi.com/how-to-implement/recognition/certification-programme-owners/
- GLOBALG.A.P. IFA GFS FV v6.0 (Aug24): https://documents.globalgap.org/documents/240902_IFA_GFS_PCs_FV_v6_0_Aug24_en.pdf
- GLOBALG.A.P. IFA Smart FV v6.0 (Sep22): https://documents.globalgap.org/documents/220929_IFA_Smart_PCs_FV_v6_0_Sep22_en.pdf
- GLOBALG.A.P. PFA: https://globalgap.org/what-we-offer/solutions/primary-farm-assurance/ · reglamento: https://documents.globalgap.org/documents/240911_PFA_GR_v6_Sep24_en.pdf
- Aneberries, inocuidad: https://aneberries.mx/inocuidad/
- FDA: https://www.fda.gov/food/food-safety-modernization-act-fsma/fsma-final-rule-produce-safety · https://www.fda.gov/food/food-safety-modernization-act-fsma/food-traceability-list · https://www.fda.gov/food/food-safety-modernization-act-fsma/fsma-final-rule-requirements-additional-traceability-records-certain-foods
- ARCFZ/Agrocalidad, certificado BPA: https://www.gob.ec/arcfz/tramites/solicitud-certificado-buenas-practicas-agricolas
- RA 2020 Farm Requirements v1.1 (copia de Preferred by Nature): https://preferredbynature.org/sites/default/files/2020-Sustainable-Agriculture-Standard_Farm-Requirements_Rainforest-Alliance.pdf
- Secundarias: QIMA, SCS, NSF, PrimusLabs, Kiwa-ASI, Greenhouse Grower, Portal Frutícola y The Food Tech (enlazadas arriba).
