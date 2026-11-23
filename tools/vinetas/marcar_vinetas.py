#!/usr/bin/env python3
"""Herramienta para marcar las viñetas de páginas de cómics a mano (para entrenar el modelo de viñetas).

Uso:
    python tools/vinetas/marcar_vinetas.py "CARPETA_CON_PAGINAS" "CARPETA_DE_ETIQUETAS"

- CARPETA_CON_PAGINAS: imágenes .jpg/.png sueltas (por ejemplo las que deja sacar_paginas.py).
- CARPETA_DE_ETIQUETAS: donde se guarda un .json por página con los recuadros marcados.
- Abre http://127.0.0.1:8765 en el navegador. Cada página viene con los recuadros que encuentran las reglas
  (probar_vinetas.py); se corrigen y se guarda.
- Todo queda en la computadora: las páginas y las etiquetas NO se suben a GitHub (tienen derechos de autor).
Necesita: pip install pillow numpy
"""
import json, os, random, sys, webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import unquote
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probar_vinetas  # noqa: E402

PORT = 8765
IMAGES = ('.jpg', '.jpeg', '.png', '.webp')


class App:
    def __init__(self, pages, labels):
        self.pages, self.labels = pages, labels
        names = sorted(f for f in os.listdir(pages) if f.lower().endswith(IMAGES))
        random.Random(7).shuffle(names)  # mezcladas: cualquier tramo tiene de todo
        self.names = names
        os.makedirs(labels, exist_ok=True)

    def label_path(self, name):
        return os.path.join(self.labels, os.path.splitext(name)[0] + '.json')

    def status(self):
        out = []
        for n in self.names:
            p = self.label_path(n)
            done = os.path.exists(p)
            doubt = False
            if done:
                with open(p, encoding='utf-8') as f:
                    d = json.load(f)
                doubt = d.get('kind') == 'skip' or bool(d.get('dudosa'))
            out.append({'name': n, 'done': done, 'doubt': doubt})
        return out

    def label(self, name):
        p = self.label_path(name)
        if os.path.exists(p):
            with open(p, encoding='utf-8') as f:
                d = json.load(f)
            d['saved'] = True
            return d
        boxes = probar_vinetas.detect(Image.open(os.path.join(self.pages, name)))
        return {'boxes': [list(b) for b in boxes], 'kind': 'panels', 'saved': False}

    def save(self, name, data):
        kind = data.get('kind')
        boxes = data.get('boxes')
        if kind not in ('panels', 'text', 'diagonal', 'skip') or not isinstance(boxes, list):
            raise ValueError('datos inválidos')
        clean = []
        for b in boxes:
            x, y, w, h = (min(1.0, max(0.0, float(v))) for v in b)
            if w > 0.005 and h > 0.005:
                clean.append([round(x, 4), round(y, 4), round(w, 4), round(h, 4)])
        with open(self.label_path(name), 'w', encoding='utf-8') as f:
            json.dump({'boxes': clean, 'kind': kind, 'dudosa': bool(data.get('dudosa'))}, f)


def handler(app):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def send(self, code, body, ctype):
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(body)

        def name(self, prefix):
            n = unquote(self.path[len(prefix):])
            if n not in app.names:  # solo archivos de la lista (nada de rutas raras)
                raise KeyError(n)
            return n

        def do_GET(self):
            try:
                if self.path == '/':
                    self.send(200, PAGE.encode('utf-8'), 'text/html; charset=utf-8')
                elif self.path == '/api/list':
                    self.send(200, json.dumps(app.status()).encode(), 'application/json')
                elif self.path.startswith('/api/label/'):
                    self.send(200, json.dumps(app.label(self.name('/api/label/'))).encode(), 'application/json')
                elif self.path.startswith('/img/'):
                    with open(os.path.join(app.pages, self.name('/img/')), 'rb') as f:
                        self.send(200, f.read(), 'image/jpeg')
                else:
                    self.send(404, b'no', 'text/plain')
            except KeyError:
                self.send(404, b'no', 'text/plain')

        def do_POST(self):
            try:
                n = self.name('/api/label/')
                size = int(self.headers.get('Content-Length', 0))
                app.save(n, json.loads(self.rfile.read(min(size, 1_000_000))))
                self.send(200, b'{"ok":true}', 'application/json')
            except (KeyError, ValueError, TypeError) as e:
                self.send(400, str(e).encode(), 'text/plain')
    return H


PAGE = r'''<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Marcar viñetas</title>
<style>
 :root { --bg:#1d1d1f; --panel:#2c2c2e; --text:#f2f2f7; --muted:#a1a1a6; --accent:#30d158; --sel:#ffd60a; --bad:#ff453a; }
 * { box-sizing:border-box; }
 body { margin:0; background:var(--bg); color:var(--text); font:15px system-ui, sans-serif; display:flex; height:100vh; }
 #side { width:330px; padding:16px; background:var(--panel); overflow:auto; }
 #main { flex:1; display:flex; align-items:center; justify-content:center; overflow:hidden; }
 #wrap { position:relative; user-select:none; }
 #wrap img { display:block; max-height:96vh; max-width:calc(100vw - 360px); }
 .box { position:absolute; border:3px solid var(--accent); background:rgba(48,209,88,.12); cursor:move; }
 .box.sel { border-color:var(--sel); background:rgba(255,214,10,.15); }
 .h { position:absolute; width:14px; height:14px; background:var(--sel); border:2px solid #000; display:none; }
 .box.sel .h { display:block; }
 .h.nw{left:-8px;top:-8px;cursor:nwse-resize}.h.ne{right:-8px;top:-8px;cursor:nesw-resize}
 .h.sw{left:-8px;bottom:-8px;cursor:nesw-resize}.h.se{right:-8px;bottom:-8px;cursor:nwse-resize}
 .num { position:absolute; left:0; top:0; background:var(--accent); color:#000; font-weight:700; padding:0 5px; }
 button { width:100%; margin:4px 0; padding:10px; border:0; border-radius:8px; background:#3a3a3c; color:var(--text); font-size:15px; cursor:pointer; text-align:left; }
 button:hover { background:#48484a; } button.main { background:var(--accent); color:#000; font-weight:700; }
 kbd { background:#48484a; border-radius:4px; padding:0 5px; font-size:13px; }
 .muted { color:var(--muted); font-size:13px; line-height:1.45; }
 #bar { height:8px; background:#3a3a3c; border-radius:4px; overflow:hidden; margin:6px 0 2px; }
 #bar div { height:100%; background:var(--accent); width:0; }
 #msg { min-height:20px; color:var(--sel); }
 h1 { font-size:20px; margin:0 0 6px; }
</style></head><body>
<div id="side">
 <h1>Marcar viñetas</h1>
 <div id="count" class="muted"></div><div id="bar"><div></div></div>
 <div id="state" class="muted"></div>
 <p id="msg"></p>
 <button class="main" id="next">Guardar y siguiente <kbd>Enter</kbd></button>
 <button id="whole">Toda la página es un solo dibujo <kbd>T</kbd></button>
 <button id="text">Página de texto o publicidad <kbd>X</kbd></button>
 <button id="diag">Viñetas en diagonal (se lee entera) <kbd>D</kbd></button>
 <button id="up">Subir número del recuadro elegido <kbd>↑</kbd></button>
 <button id="down">Bajar número del recuadro elegido <kbd>↓</kbd></button>
 <button id="doubt">Dudosa: volver a mirarla después <kbd>R</kbd></button>
 <button id="nextdoubt">Ir a la próxima dudosa o salteada <kbd>V</kbd></button>
 <button id="del">Borrar recuadro elegido <kbd>Supr</kbd></button>
 <button id="clear">Borrar todos <kbd>C</kbd></button>
 <button id="skip">Saltear (no sé cómo marcarla) <kbd>S</kbd></button>
 <button id="prev">Volver a la anterior <kbd>←</kbd></button>
 <button id="todo">Ir a la próxima sin marcar</button>
 <p class="muted"><b>Cómo marcar</b><br>
 • Un recuadro por viñeta, incluido su borde negro.<br>
 • Arrastrá en un lugar vacío para dibujar uno nuevo.<br>
 • Tocá un recuadro para elegirlo; arrastralo para moverlo o tirá de las esquinas amarillas.<br>
 • Viñeta sin borde que llega al filo de la hoja: hasta el filo.<br>
 • Recuadro chico encima de un dibujo grande: marcá los dos.<br>
 • Tapa o dibujo de página entera: <kbd>T</kbd>.<br>
 • Cartas, créditos, publicidad: <kbd>X</kbd>.<br>
 • Viñetas torcidas que no entran en un rectángulo: <kbd>D</kbd> (la app muestra la página entera).<br>
 • Los globos de diálogo que salen de la viñeta no cuentan.<br>
 Se guarda solo al pasar de página (siguiente o anterior).</p>
</div>
<div id="main"><div id="wrap"><img id="img" draggable="false"></div></div>
<script>
let list = [], idx = 0, boxes = [], sel = -1, kind = 'panels', dudosa = false, drag = null;
const img = document.getElementById('img'), wrap = document.getElementById('wrap');
const $ = id => document.getElementById(id);
const clamp = v => Math.min(1, Math.max(0, v));

async function start() {
  list = await (await fetch('/api/list')).json();
  idx = Math.max(0, list.findIndex(p => !p.done));
  if (list.every(p => p.done)) idx = 0;
  load();
}
async function load() {
  const p = list[idx];
  const d = await (await fetch('/api/label/' + encodeURIComponent(p.name))).json();
  boxes = d.boxes; kind = d.kind || 'panels'; dudosa = !!d.dudosa; sel = -1;
  img.src = '/img/' + encodeURIComponent(p.name);
  $('state').textContent = (d.saved ? 'Ya marcada: ' + ({panels:'viñetas', text:'texto', diagonal:'diagonal', skip:'salteada'}[kind]) : 'Recuadros puestos por las reglas: revisalos') + ' — ' + p.name;
  progress(); draw();
}
function progress() {
  const done = list.filter(p => p.done).length;
  $('count').textContent = `Página ${idx + 1} de ${list.length} · marcadas: ${done}`;
  $('bar').firstChild.style.width = (100 * done / list.length) + '%';
}
function draw() {
  wrap.querySelectorAll('.box').forEach(b => b.remove());
  boxes.forEach((b, i) => {
    const d = document.createElement('div');
    d.className = 'box' + (i === sel ? ' sel' : '');
    Object.assign(d.style, { left: b[0]*100+'%', top: b[1]*100+'%', width: b[2]*100+'%', height: b[3]*100+'%' });
    d.innerHTML = `<span class="num">${i+1}</span>` + ['nw','ne','sw','se'].map(c => `<div class="h ${c}" data-c="${c}"></div>`).join('');
    d.dataset.i = i; wrap.appendChild(d);
  });
  $('doubt').textContent = (dudosa ? '✓ Dudosa (tocá para quitar)' : 'Dudosa: volver a mirarla después') + ' R';
  $('msg').textContent = kind === 'text' ? 'Marcada como texto o publicidad' : kind === 'diagonal' ? 'Viñetas en diagonal: se lee entera' : kind === 'skip' ? 'Salteada' : '';
}
function pos(e) { const r = img.getBoundingClientRect(); return [clamp((e.clientX - r.left) / r.width), clamp((e.clientY - r.top) / r.height)]; }
wrap.addEventListener('mousedown', e => {
  e.preventDefault(); kind = 'panels';
  const [x, y] = pos(e), boxEl = e.target.closest('.box');
  if (e.target.classList.contains('h')) { sel = +boxEl.dataset.i; drag = { mode: e.target.dataset.c, start: [x, y], orig: boxes[sel].slice() }; }
  else if (boxEl) { sel = +boxEl.dataset.i; drag = { mode: 'move', start: [x, y], orig: boxes[sel].slice() }; }
  else { boxes.push([x, y, 0, 0]); sel = boxes.length - 1; drag = { mode: 'new', start: [x, y] }; }
  draw();
});
window.addEventListener('mousemove', e => {
  if (!drag) return;
  const [x, y] = pos(e), [sx, sy] = drag.start, o = drag.orig;
  let b;
  if (drag.mode === 'new') b = [Math.min(sx, x), Math.min(sy, y), Math.abs(x - sx), Math.abs(y - sy)];
  else if (drag.mode === 'move') b = [clamp(o[0] + x - sx), clamp(o[1] + y - sy), o[2], o[3]];
  else {
    let x0 = o[0], y0 = o[1], x1 = o[0] + o[2], y1 = o[1] + o[3];
    if (drag.mode.includes('w')) x0 = x; if (drag.mode.includes('e')) x1 = x;
    if (drag.mode.includes('n')) y0 = y; if (drag.mode.includes('s')) y1 = y;
    b = [Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0)];
  }
  b[2] = Math.min(b[2], 1 - b[0]); b[3] = Math.min(b[3], 1 - b[1]);
  boxes[sel] = b; draw();
});
window.addEventListener('mouseup', () => {
  if (drag && drag.mode === 'new' && (boxes[sel][2] < 0.01 || boxes[sel][3] < 0.01)) { boxes.splice(sel, 1); sel = -1; draw(); }
  drag = null;
});
async function save() {
  const p = list[idx];
  const r = await fetch('/api/label/' + encodeURIComponent(p.name), { method: 'POST', body: JSON.stringify({ boxes: kind === 'panels' ? boxes : [], kind, dudosa }) });
  if (!r.ok) { $('msg').textContent = 'No se pudo guardar: ' + await r.text(); return false; }
  p.done = true; p.doubt = dudosa || kind === 'skip'; return true;
}
async function go(step) { if (await save()) { idx = (idx + step + list.length) % list.length; load(); } }
const act = {
  next: () => go(1),
  prev: () => go(-1),
  whole: () => { kind = 'panels'; boxes = [[0, 0, 1, 1]]; sel = 0; draw(); },
  text: () => { kind = 'text'; boxes = []; sel = -1; draw(); },
  diag: () => { kind = 'diagonal'; boxes = []; sel = -1; draw(); },
  skip: () => { kind = 'skip'; draw(); },
  up: () => move(-1),
  down: () => move(1),
  doubt: () => { dudosa = !dudosa; draw(); },
  nextdoubt: async () => {
    if (!await save()) return;
    for (let s = 1; s <= list.length; s++) {
      const j = (idx + s) % list.length;
      if (list[j].doubt) { idx = j; load(); return; }
    }
    $('msg').textContent = 'No hay páginas dudosas ni salteadas';
  },
  del: () => { if (sel >= 0) { boxes.splice(sel, 1); sel = -1; draw(); } },
  clear: () => { boxes = []; sel = -1; kind = 'panels'; draw(); },
  todo: () => { const i = list.findIndex((p, j) => j > idx && !p.done); if (i >= 0) { idx = i; load(); } },
};
function move(step) {  // cambia el número (orden de lectura) del recuadro elegido
  const j = sel + step;
  if (sel < 0 || j < 0 || j >= boxes.length) return;
  [boxes[sel], boxes[j]] = [boxes[j], boxes[sel]]; sel = j; kind = 'panels'; draw();
}
Object.keys(act).forEach(k => $(k).onclick = act[k]);
window.addEventListener('keydown', e => {
  const k = { Enter: 'next', ArrowRight: 'next', ArrowLeft: 'prev', Delete: 'del', Backspace: 'del', ArrowUp: 'up', ArrowDown: 'down', r: 'doubt', v: 'nextdoubt', t: 'whole', x: 'text', d: 'diag', s: 'skip', c: 'clear' }[e.key.length === 1 ? e.key.toLowerCase() : e.key];
  if (k) { e.preventDefault(); act[k](); }
});
start();
</script></body></html>'''


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    app = App(sys.argv[1], sys.argv[2])
    if not app.names:
        sys.exit('No hay imágenes en ' + sys.argv[1])
    server = HTTPServer(('127.0.0.1', PORT), handler(app))
    url = f'http://127.0.0.1:{PORT}'
    print(f'{len(app.names)} páginas. Abrí {url} (Ctrl+C para cerrar).')
    if not os.environ.get("NO_BROWSER"):
        webbrowser.open(url)
    server.serve_forever()


if __name__ == '__main__':
    main()
