// Centro de ayuda de VG · plantilla común (R-AYUDA). La misma página en todos los productos.
// Es el ayuda.js de Campo Digital (#06) generalizado: todo lo propio del producto sale de ayuda.json.
// Va en archivo aparte para que la CSP no necesite 'unsafe-inline' en los guiones.
//
// ayuda.json (formato común; los campos marcados con * son obligatorios):
//   producto*      "Campo Digital™"                       → título, marca y pie
//   actores*       [["jefe", "Jefe de hacienda"], …]       → orden y nombre de cada grupo y chip
//   enlaces        [{"texto": "Entrar", "href": "/", "icono": "login", "principal": true}, …]
//   entrada        texto de la tarjeta de arriba · buscar_ejemplo: el placeholder del buscador
//   base           prefijo de video y portada cuando son relativos ("" si son absolutos)
//   version, actualizado, generado_por
//   flujos*: [{id*, actor*, orden*, titulo*, resumen*, pasos*[], probar, segundos, nota,
//              video, portada, video_redes, origen, solo_web}]   (video y portada en null si aún no hay video)
//   solo_web (en un flujo, opcional): true si enseña a pagar. Dentro de la APK no existe: ni en la lista, ni en el
//   buscador, ni en los chips, ni por su enlace #id, y sin aviso de «está en la web» (R-COBRO: la app solo habilita).
//   La APK abre los productos con ?vg_app=apk; la página guarda esa marca en sessionStorage, como cada producto.
(() => {
  const $ = (s) => document.querySelector(s);
  const el = (tag, props = {}, ...hijos) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'texto') e.textContent = v; else if (v !== undefined && v !== null) e.setAttribute(k, v);
    }
    for (const h of hijos) if (h) e.append(h);
    return e;
  };
  const sinTilde = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

  // Solo se cargan videos e imágenes de https://*.visiongeografica.com o del mismo sitio, y solo se enlaza a
  // http(s): un ayuda.json alterado no puede meter un javascript: ni un video de un tercero.
  const resolver = (u, base) => {
    if (typeof u !== 'string' || !u) return null;
    try { return new URL(u, new URL(base || '', location.href)); } catch { return null; }
  };
  const medioPermitido = (u, base) => {
    const x = resolver(u, base);
    return x && (x.origin === location.origin
      || (x.protocol === 'https:' && (x.hostname === 'visiongeografica.com' || x.hostname.endsWith('.visiongeografica.com'))))
      ? x.href : null;
  };
  const enlacePermitido = (u) => {
    const x = resolver(u, '');
    return x && (x.protocol === 'https:' || x.protocol === 'http:') ? x.href : null;
  };

  let datos = null, actores = [], filtro = '', actor = '';

  function tarjeta(f, base) {
    const d = el('details', { class: 'flujo', id: f.id });
    const video = medioPermitido(f.video, base), portada = medioPermitido(f.portada, base);
    const mini = portada
      ? el('img', { class: 'mini', src: portada, alt: '', loading: 'lazy', width: 54, height: 96 })
      : el('div', { class: 'mini texto ms', 'aria-hidden': 'true', texto: 'description' });
    const n = (f.pasos || []).length;
    const dur = (video && f.segundos ? `${f.segundos} s · ` : '') + `${n} paso${n === 1 ? '' : 's'}`;
    d.append(el('summary', {}, mini,
      el('div', { class: 'cab-t' }, el('b', { texto: f.titulo }), el('span', { texto: f.resumen })),
      el('span', { class: 'dur', texto: dur })));

    const cuerpo = el('div', { class: 'cuerpo' });
    if (video) {
      const v = el('video', { class: 'video-flujo', controls: '', playsinline: '', preload: 'none', poster: portada });
      v.append(el('source', { src: video, type: 'video/mp4' }));
      cuerpo.append(v);
    }
    const lado = el('div');
    const ol = el('ol', { class: 'pasos' });
    for (const p of f.pasos || []) ol.append(el('li', { texto: p }));
    lado.append(ol);
    if (!video) lado.append(el('p', { class: 'sin-video', texto: 'Video en preparación: por ahora, el paso a paso escrito.' }));
    if (f.nota) lado.append(el('p', { class: 'nota', texto: f.nota }));
    const acc = el('div', { class: 'acciones' });
    const probar = enlacePermitido(f.probar);
    if (probar) acc.append(el('a', { class: 'btn btn-lima', href: probar, rel: 'noopener', texto: 'Probarlo en la demo' }));
    acc.append(el('a', { class: 'btn', href: '#' + f.id, texto: 'Enlace a este flujo' }));
    lado.append(acc);
    cuerpo.append(lado);
    d.append(cuerpo);
    d.addEventListener('toggle', () => {
      if (d.open && location.hash !== '#' + f.id) history.replaceState(null, '', '#' + f.id);
      if (!d.open) d.querySelector('video')?.pause();
    });
    return d;
  }

  function pintar() {
    const cont = $('#contenido');
    cont.replaceChildren();
    const q = sinTilde(filtro);
    const visibles = datos.flujos.filter((f) => (!actor || f.actor === actor)
      && (!q || sinTilde([f.titulo, f.resumen, ...(f.pasos || [])].join(' ')).includes(q)));
    if (!visibles.length) { cont.append(el('p', { class: 'vacio', texto: 'Nada coincide con la búsqueda.' })); return; }
    for (const [clave, nombre] of actores) {
      const deEste = visibles.filter((f) => f.actor === clave);
      if (!deEste.length) continue;
      const lista = el('div', { class: 'lista' });
      for (const f of deEste) lista.append(tarjeta(f, datos.base || ''));
      cont.append(el('section', { class: 'grupo', 'aria-label': nombre }, el('h2', { texto: nombre }), lista));
    }
    abrirDesdeEnlace();
  }

  // El logo con ™ tiene versión para fondo claro y para fondo oscuro. Sin más, <picture> sigue el tema del teléfono;
  // si la página fuerza un tema con data-theme, el logo sigue al de la página (#02, 31-oct).
  const temaLogo = () => {
    const tema = document.documentElement.dataset.theme, img = $('#logo img'), src = $('#logo source');
    if (tema !== 'dark' && tema !== 'light') return;
    src?.remove();
    img.src = `vg-logo-tm-${tema === 'dark' ? 'oscuro' : 'claro'}.png`;
  };
  temaLogo();
  new MutationObserver(temaLogo).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

  // La cabecera es fija y en el teléfono crece cuando los botones bajan de línea: se mide para que no tape el
  // título del flujo que se abre por enlace.
  const medirCabecera = () => document.documentElement.style.setProperty('--alto-cabecera', `${$('.topbar').offsetHeight}px`);
  window.addEventListener('resize', medirCabecera);

  function abrirDesdeEnlace() {
    medirCabecera();
    const id = decodeURIComponent(location.hash.slice(1));
    const d = id && document.getElementById(id);
    if (d && d.tagName === 'DETAILS') { d.open = true; d.scrollIntoView({ block: 'start' }); }
  }

  function botonesActor() {
    const caja = $('#actores');
    const hay = new Set(datos.flujos.map((f) => f.actor));
    const visibles = actores.filter(([k]) => hay.has(k));
    // Con un solo actor, los chips no filtran nada: no se muestran.
    if (visibles.length < 2) { caja.replaceChildren(); caja.hidden = true; return; }
    const boton = (clave, nombre) => {
      const b = el('button', { type: 'button', class: 'chip', 'aria-pressed': String(actor === clave), texto: nombre });
      b.addEventListener('click', () => { actor = clave; botonesActor(); pintar(); });
      return b;
    };
    caja.replaceChildren(boton('', 'Todos'), ...visibles.map(([k, n]) => boton(k, n)));
  }

  function cabecera(j) {
    const producto = j.producto || 'Visión Geográfica™';
    document.title = `Ayuda en video · ${producto}`;
    $('#marca').textContent = `${producto} · Centro de ayuda`;
    if (j.entrada) $('#entrada').textContent = j.entrada;
    if (j.buscar_ejemplo) $('#q').placeholder = j.buscar_ejemplo;
    const nav = $('#enlaces');
    nav.setAttribute('aria-label', producto);
    for (const e of j.enlaces || []) {
      const href = enlacePermitido(e.href);
      if (!href) continue;
      const a = el('a', { class: 'btn' + (e.principal ? ' btn-primary' : ''), href });
      if (e.icono) a.append(el('span', { class: 'ms', 'aria-hidden': 'true', texto: e.icono }));
      a.append(e.texto);
      nav.append(a);
    }
  }

  fetch('ayuda.json', { cache: 'no-cache' }).then((r) => r.json()).then((j) => {
    // v5 (#14, 31-oct; aprobada por #17): dentro de la APK, los flujos que enseñan a pagar se quitan antes de pintar nada.
    let apk = false;
    try {
      if (new URLSearchParams(location.search).get('vg_app') === 'apk') sessionStorage.setItem('vg_app', 'apk');
      apk = sessionStorage.getItem('vg_app') === 'apk';
    } catch { apk = new URLSearchParams(location.search).get('vg_app') === 'apk'; }
    if (apk) j.flujos = j.flujos.filter((f) => f.solo_web !== true);
    datos = j;
    // Los actores en el orden de ayuda.json; los que falten, en el orden en que aparecen en los flujos.
    actores = (j.actores || []).filter((a) => Array.isArray(a) && a.length >= 2);
    for (const f of j.flujos) if (!actores.some(([k]) => k === f.actor)) actores.push([f.actor, f.actor]);
    j.flujos.sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0));
    cabecera(j);
    botonesActor();
    pintar();
    const conVideo = j.flujos.filter((f) => medioPermitido(f.video, j.base)).length;
    $('#conteo').textContent = `${j.flujos.length} flujos, ${conVideo} con video`;
    // Pie de una app (R-FECHA-VERSIÓN; #02, 31-oct): créditos, versión y fecha. El año sale de «actualizado».
    const anio = String(j.actualizado || '').match(/\b(20\d\d)\b/);
    $('#pie').textContent = [j.producto, `© ${anio ? anio[1] + ' ' : ''}Visión Geográfica™`,
      j.version ? `Versión ${j.version}` : '', j.actualizado || ''].filter(Boolean).join(' · ');
    const pol = el('a', { href: 'https://www.visiongeografica.com/privacy/', rel: 'noopener', texto: 'Política de privacidad' });
    $('#pie').append(' · ', pol);
  }).catch(() => {
    $('#contenido').replaceChildren(el('p', { class: 'vacio', texto: 'No se pudo cargar la ayuda. Revise la conexión y vuelva a intentar.' }));
  });

  $('#q').addEventListener('input', (e) => { filtro = e.target.value; pintar(); });
  window.addEventListener('hashchange', abrirDesdeEnlace);
})();
