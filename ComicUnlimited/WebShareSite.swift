import Foundation

// La página que ve la compu en "Ver en la compu" (WebShare.swift la sirve).
// Todo va adentro de este texto: sin internet, sin programas de terceros.
// - Biblioteca: portadas, buscador, orden y avance de cada cómic.
// - Lector: flechas o clic a los costados, una o dos páginas, entera o al ancho, pantalla completa.
// - Al abrir un cómic guarda todas sus páginas en la compu: si el iPhone se desconecta, se sigue leyendo.
// - La página donde quedaste vuelve al iPhone.

enum WebShareSite {
    static let html = #"""
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cómic Unlimited</title>
<style>
:root {
  --paper: #EEF2F4; --card: #FFFFFF; --ink: #17191E; --ink2: #5B6170; --line: #D5DCE1; --chip: #E1E7EB;
  --magenta: #D1006C; --cyan: #0090C4; --yellow: #FFD400;
  --display: "Helvetica Neue", "Arial Black", Arial, sans-serif;
  --body: -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root { --paper: #121419; --card: #1C1F26; --ink: #EEF1F4; --ink2: #9AA1AE; --line: #2B2F38; --chip: #262A33;
          --magenta: #FF4FA3; --cyan: #3CC3F0; color-scheme: dark; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--paper); color: var(--ink); font: 15px/1.45 var(--body); }
main { max-width: 1280px; margin: 0 auto; padding: 28px max(20px, 3vw) 60px; }
h1 { font: 900 clamp(30px, 4vw, 46px)/1 var(--display); letter-spacing: -0.02em; margin: 0;
     text-shadow: 3px 1.5px 0 color-mix(in srgb, var(--cyan) 55%, transparent), -2px -1px 0 color-mix(in srgb, var(--magenta) 50%, transparent); }
.sub { color: var(--ink2); margin: 6px 0 0; }
.bar { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin: 22px 0 18px; }
.search { flex: 1 1 260px; display: flex; align-items: center; gap: 10px; background: var(--card); border: 2px solid var(--ink);
          border-radius: 999px; padding: 8px 16px; box-shadow: 4px 4px 0 var(--magenta); }
.search input { flex: 1; border: 0; background: none; color: var(--ink); font: inherit; font-size: 16px; outline: none; min-width: 0; }
select, button { font: inherit; }
select { background: var(--card); color: var(--ink); border: 1px solid var(--line); border-radius: 10px; padding: 9px 10px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 22px 18px; }
.card { all: unset; cursor: pointer; display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.cover { aspect-ratio: 2 / 3; width: 100%; border-radius: 6px; overflow: hidden; background: var(--chip);
         border: 1px solid var(--line); display: grid; place-items: center; color: var(--ink2); font-size: 28px; }
.cover img { width: 100%; height: 100%; object-fit: cover; display: block; }
.card:hover .cover, .card:focus-visible .cover { outline: 3px solid var(--magenta); outline-offset: 2px; }
.card b { font-size: 14px; line-height: 1.25; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.meta { font-size: 12px; color: var(--ink2); }
.prog { height: 4px; border-radius: 2px; background: var(--chip); overflow: hidden; }
.prog i { display: block; height: 100%; background: var(--magenta); }
.done { color: var(--magenta); font-weight: 700; }
.notice { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px; max-width: 520px; }
.notice input { font: 600 22px ui-monospace, Menlo, monospace; letter-spacing: 0.2em; width: 9em; padding: 8px 10px;
                border: 2px solid var(--ink); border-radius: 10px; background: var(--paper); color: var(--ink); }
.btn { background: var(--magenta); color: #fff; border: 0; border-radius: 10px; padding: 10px 16px; font-weight: 800; cursor: pointer; }
.btn:focus-visible, select:focus-visible { outline: 3px solid var(--cyan); outline-offset: 2px; }

/* Lector */
#reader { position: fixed; inset: 0; background: #0b0c0f; color: #eef1f4; display: none; z-index: 10; user-select: none; }
#reader.open { display: block; }
#stage { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; gap: 0; overflow: auto; }
#stage img { display: block; max-height: 100vh; max-width: 100%; object-fit: contain; }
#stage.two img { max-width: 50%; }
#stage.width { align-items: flex-start; }
#stage.width img { max-height: none; width: min(100%, 1100px); max-width: none; }
#stage.width.two img { width: min(50%, 900px); }
.zone { position: absolute; top: 0; bottom: 0; width: 30%; cursor: pointer; z-index: 1; }
.zone.l { left: 0; } .zone.r { right: 0; }
#top, #bottom { position: absolute; left: 0; right: 0; z-index: 2; display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
                padding: 10px 16px; background: rgba(11,12,15,.86); transition: opacity .2s; }
#top { top: 0; } #bottom { bottom: 0; }
#reader.hide #top, #reader.hide #bottom { opacity: 0; pointer-events: none; }
#top b { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.rb { background: #262a33; color: #eef1f4; border: 0; border-radius: 8px; padding: 7px 11px; cursor: pointer; font-weight: 700; }
.rb.on { background: #FF4FA3; color: #121419; }
.rb:focus-visible { outline: 2px solid #3CC3F0; }
#slider { flex: 1; min-width: 120px; accent-color: #FF4FA3; }
#count { font-variant-numeric: tabular-nums; min-width: 5.5em; text-align: center; }
#saved { font-size: 12px; color: #9AA1AE; }
#wait { position: absolute; inset: 0; display: grid; place-items: center; color: #9AA1AE; pointer-events: none; }
@media (prefers-reduced-motion: reduce) { #top, #bottom { transition: none; } }
</style>
</head>
<body>
<main>
  <h1>Cómic Unlimited</h1>
  <p class="sub" id="sub">Tus cómics, leídos directo desde tu iPhone.</p>
  <div id="content"></div>
</main>

<div id="reader" aria-label="Lector">
  <div id="stage"></div>
  <div id="wait">Cargando…</div>
  <div class="zone l" id="zl" title="Página anterior"></div>
  <div class="zone r" id="zr" title="Página siguiente"></div>
  <div id="top">
    <button class="rb" id="back">← Biblioteca</button>
    <b id="rtitle"></b>
    <button class="rb" id="fit" title="Tamaño de la página">Entera</button>
    <button class="rb" id="two" title="Dos páginas juntas (D)">Dos páginas</button>
    <button class="rb" id="full" title="Pantalla completa (F)">Pantalla completa</button>
  </div>
  <div id="bottom">
    <button class="rb" id="prev" aria-label="Página anterior">‹</button>
    <input type="range" id="slider" min="1" value="1" aria-label="Ir a la página">
    <button class="rb" id="next" aria-label="Página siguiente">›</button>
    <span id="count"></span>
    <span id="saved"></span>
  </div>
</div>

<script>
(function () {
  "use strict";
  var params = new URLSearchParams(location.search);
  var code = params.get("c") || "";
  try { if (!code) code = localStorage.getItem("cu-code") || ""; } catch (e) {}
  var content = document.getElementById("content");
  var library = [];
  var query = "", order = "recent";
  try { order = localStorage.getItem("cu-order") || "recent"; } catch (e) {}

  function api(path) { return "/api/" + path + (path.indexOf("?") < 0 ? "?" : "&") + "c=" + encodeURIComponent(code); }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (ch) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]; }); }

  // ---------- Código ----------
  function askCode(message) {
    content.innerHTML = '<div class="notice" style="margin-top:24px"><p>' + esc(message) +
      '</p><form id="codeForm"><label for="codeInput">Código de 6 números que muestra la app (Ver en la compu):</label><br>' +
      '<input id="codeInput" inputmode="numeric" maxlength="6" autocomplete="off"> <button class="btn">Entrar</button></form></div>';
    var form = document.getElementById("codeForm");
    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      code = document.getElementById("codeInput").value.trim();
      loadLibrary();
    });
    document.getElementById("codeInput").focus();
  }

  // ---------- Biblioteca ----------
  function loadLibrary() {
    if (!code) { askCode("Para entrar falta el código."); return; }
    content.innerHTML = '<p class="sub">Cargando tu biblioteca…</p>';
    fetch(api("library")).then(function (r) {
      if (r.status === 403) throw new Error("code");
      if (!r.ok) throw new Error("net");
      return r.json();
    }).then(function (list) {
      try { localStorage.setItem("cu-code", code); } catch (e) {}
      library = list;
      renderLibrary();
    }).catch(function (err) {
      if (err.message === "code") { askCode("El código no es correcto (cambia cada vez que empezás a compartir)."); }
      else { content.innerHTML = '<div class="notice" style="margin-top:24px">No se pudo conectar con el iPhone. Revisá que la app esté abierta en "Ver en la compu" (o con "Seguir con el teléfono bloqueado" prendido) y en el mismo Wi-Fi. <button class="btn" id="retry">Probar de nuevo</button></div>';
             document.getElementById("retry").onclick = loadLibrary; }
    });
  }

  function renderLibrary() {
    document.getElementById("sub").textContent = library.length + (library.length === 1 ? " cómic" : " cómics") + " en tu iPhone.";
    content.innerHTML =
      '<div class="bar"><label class="search"><span aria-hidden="true">🔍</span><input id="q" type="search" placeholder="Buscar en tu biblioteca" value="' + esc(query) + '"></label>' +
      '<select id="order" aria-label="Orden"><option value="recent">Recientes</option><option value="az">A–Z</option><option value="added">Últimos agregados</option></select></div>' +
      '<div class="grid" id="grid"></div>';
    var q = document.getElementById("q"), sel = document.getElementById("order");
    sel.value = order;
    q.addEventListener("input", function () { query = q.value; renderGrid(); });
    sel.addEventListener("change", function () { order = sel.value; try { localStorage.setItem("cu-order", order); } catch (e) {} renderGrid(); });
    renderGrid();
  }

  function renderGrid() {
    var grid = document.getElementById("grid");
    var words = query.toLowerCase().split(/\s+/).filter(Boolean);
    var list = library.filter(function (c) {
      var t = (c.title + " " + (c.series || "")).toLowerCase();
      return words.every(function (w) { return t.indexOf(w) >= 0; });
    });
    list.sort(function (a, b) {
      if (order === "az") return a.title.localeCompare(b.title, "es", { numeric: true });
      if (order === "added") return b.added - a.added;
      return (b.opened || b.added / 1e6) - (a.opened || a.added / 1e6);
    });
    if (!list.length) { grid.innerHTML = '<p class="sub">No hay cómics que coincidan.</p>'; return; }
    grid.innerHTML = list.map(function (c) {
      var pct = c.finished ? 100 : Math.round(((c.lastPage || 0) + 1) / Math.max(c.pages, 1) * 100);
      var started = c.finished || c.opened > 0;
      var meta = c.finished ? '<span class="done">Leído</span>' : (started ? "Página " + ((c.lastPage || 0) + 1) + " de " + c.pages : c.pages + " páginas");
      return '<button class="card" data-id="' + esc(c.id) + '"><div class="cover"><img loading="lazy" alt="" src="' + api("cover/" + encodeURIComponent(c.id)) + '" onerror="this.remove()"></div>' +
        '<b>' + esc(c.title) + '</b><span class="meta">' + meta + '</span>' + (started ? '<div class="prog"><i style="width:' + pct + '%"></i></div>' : '') + '</button>';
    }).join("");
    Array.prototype.forEach.call(grid.querySelectorAll(".card"), function (el) {
      el.addEventListener("click", function () { openComic(el.getAttribute("data-id")); });
    });
  }

  // ---------- Lector ----------
  var reader = document.getElementById("reader"), stage = document.getElementById("stage");
  var comic = null, page = 0, blobs = {}, loading = {}, token = 0, saveTimer = null, hideTimer = null;
  var fitWidth = false, two = false;
  try { fitWidth = localStorage.getItem("cu-fit") === "width"; two = localStorage.getItem("cu-two") === "1"; } catch (e) {}

  function pageURL(i) { return api("page/" + encodeURIComponent(comic.id) + "/" + i); }

  function fetchPage(i, myToken) {
    if (blobs[i] || loading[i]) return loading[i] || Promise.resolve(blobs[i]);
    loading[i] = fetch(pageURL(i)).then(function (r) { if (!r.ok) throw new Error("page"); return r.blob(); })
      .then(function (b) { if (myToken !== token) return null; blobs[i] = URL.createObjectURL(b); delete loading[i]; updateSaved(); return blobs[i]; })
      .catch(function () { delete loading[i]; return null; });
    return loading[i];
  }

  function updateSaved() {
    if (!comic) return;
    var n = Object.keys(blobs).length;
    document.getElementById("saved").textContent = n >= comic.pages
      ? "Todo el cómic guardado en la compu: podés bloquear el iPhone."
      : "Guardando en la compu: " + n + " de " + comic.pages + " páginas";
  }

  // Baja todas las páginas, empezando por las de al lado de donde estás (de a 2 a la vez).
  function prefetchAll(myToken) {
    var orderList = [];
    for (var d = 0; d < comic.pages; d++) {
      [page + d, page - d].forEach(function (i) { if (i >= 0 && i < comic.pages && orderList.indexOf(i) < 0) orderList.push(i); });
    }
    var next = 0;
    function worker() {
      if (myToken !== token || next >= orderList.length) return;
      var i = orderList[next++];
      fetchPage(i, myToken).then(worker);
    }
    worker(); worker();
  }

  function shownPages() {
    if (!two || page === 0) return [page];
    var first = page % 2 === 1 ? page : page - 1;   // tapa sola; después de a pares 1-2, 3-4…
    return first + 1 < comic.pages ? [first, first + 1] : [first];
  }

  function render() {
    var list = shownPages();
    page = list[0];
    stage.className = (fitWidth ? "width" : "") + (list.length > 1 ? " two" : "");
    stage.innerHTML = "";
    var myToken = token;
    document.getElementById("wait").style.display = "grid";
    list.forEach(function (i) {
      var img = document.createElement("img");
      img.alt = "Página " + (i + 1);
      stage.appendChild(img);
      fetchPage(i, myToken).then(function (url) {
        if (myToken !== token) return;
        img.src = url || pageURL(i);
        document.getElementById("wait").style.display = "none";
      });
    });
    stage.scrollTop = 0;
    var last = list[list.length - 1];
    document.getElementById("count").textContent = (list.length > 1 ? (list[0] + 1) + "–" + (last + 1) : (page + 1)) + " / " + comic.pages;
    var slider = document.getElementById("slider");
    slider.max = comic.pages; slider.value = page + 1;
    document.getElementById("fit").textContent = fitWidth ? "Al ancho" : "Entera";
    document.getElementById("two").classList.toggle("on", two);
    scheduleSave(last);
  }

  function scheduleSave(last) {
    clearTimeout(saveTimer);
    var c = comic, p = last;
    var local = library.find(function (x) { return x.id === c.id; });
    if (local) { local.lastPage = p; local.opened = Date.now() / 1000; if (p >= c.pages - 1) local.finished = true; }
    saveTimer = setTimeout(function () { fetch(api("progress/" + encodeURIComponent(c.id) + "/" + p)).catch(function () {}); }, 1200);
  }

  function go(delta) {
    if (!comic) return;
    var list = shownPages();
    var target = delta > 0 ? list[list.length - 1] + 1 : list[0] - 1;
    if (target < 0 || target >= comic.pages) return;
    page = target;
    render();
    showControls();
  }

  function openComic(id) {
    comic = library.find(function (c) { return c.id === id; });
    if (!comic) return;
    token++;
    blobs = {}; loading = {};
    page = comic.finished ? 0 : Math.min(comic.lastPage || 0, comic.pages - 1);
    document.getElementById("rtitle").textContent = comic.title;
    reader.classList.add("open");
    document.body.style.overflow = "hidden";
    render();
    updateSaved();
    prefetchAll(token);
    showControls();
  }

  function closeComic() {
    token++;
    Object.keys(blobs).forEach(function (k) { URL.revokeObjectURL(blobs[k]); });
    blobs = {}; loading = {};
    reader.classList.remove("open");
    document.body.style.overflow = "";
    if (document.fullscreenElement) document.exitFullscreen().catch(function () {});
    comic = null;
    renderGrid();
  }

  function showControls() {
    reader.classList.remove("hide");
    clearTimeout(hideTimer);
    hideTimer = setTimeout(function () { reader.classList.add("hide"); }, 2500);
  }

  document.getElementById("zl").onclick = function () { go(-1); };
  document.getElementById("zr").onclick = function () { go(1); };
  document.getElementById("prev").onclick = function () { go(-1); };
  document.getElementById("next").onclick = function () { go(1); };
  document.getElementById("back").onclick = closeComic;
  document.getElementById("fit").onclick = function () { fitWidth = !fitWidth; try { localStorage.setItem("cu-fit", fitWidth ? "width" : "page"); } catch (e) {} render(); };
  document.getElementById("two").onclick = function () { two = !two; try { localStorage.setItem("cu-two", two ? "1" : "0"); } catch (e) {} render(); };
  document.getElementById("full").onclick = function () {
    if (document.fullscreenElement) document.exitFullscreen().catch(function () {});
    else if (reader.requestFullscreen) reader.requestFullscreen().catch(function () {});
  };
  document.getElementById("slider").addEventListener("input", function (ev) { page = Number(ev.target.value) - 1; render(); });
  reader.addEventListener("mousemove", showControls);
  document.addEventListener("keydown", function (ev) {
    if (!comic) return;
    if (ev.key === "ArrowRight" || ev.key === " " || ev.key === "PageDown") { ev.preventDefault(); go(1); }
    else if (ev.key === "ArrowLeft" || ev.key === "PageUp") { ev.preventDefault(); go(-1); }
    else if (ev.key === "Escape" && !document.fullscreenElement) { closeComic(); }
    else if (ev.key === "f" || ev.key === "F") { document.getElementById("full").click(); }
    else if (ev.key === "d" || ev.key === "D") { document.getElementById("two").click(); }
  });

  loadLibrary();
})();
</script>
</body>
</html>
"""#
}
