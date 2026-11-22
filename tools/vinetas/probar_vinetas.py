#!/usr/bin/env python3
"""Prueba la detección de viñetas con cómics de una carpeta (se usa en la computadora, NO va dentro de la app).

Uso:
    python3 tools/vinetas/probar_vinetas.py "CARPETA_CON_COMICS" [--salida resultados] [--paginas 20] [--manga]

- Lee .cbz/.zip (y .cbr/.rar si está instalado 7z o unrar), y carpetas con imágenes.
- Por cada cómic toma hasta N páginas, detecta las viñetas y guarda una imagen por cómic con los recuadros
  verdes numerados (en orden de lectura) en la carpeta de salida, más un resumen.txt.
- No modifica ni copia los cómics. Las imágenes de resultado son solo para mirar en la computadora:
  no subirlas a GitHub (tienen derechos de autor).

La lógica es la MISMA que ComicUnlimited/PanelDetector.swift (PanelStore versión 4). Si se cambia una, cambiar la otra.
Necesita: pip install pillow numpy
"""
import argparse, io, os, subprocess, sys, tempfile, zipfile
import numpy as np
from PIL import Image, ImageDraw

W = 400          # ancho de trabajo
TOL = 32         # "mismo color": diferencia por canal
SIMILAR = 40     # colores parecidos
SHARE = 0.72     # parte de la línea que tiene que ser del color de la calle
EDGE = 5         # % de cada punta donde tiene que aparecer el color de la calle (por marcos o bordes sucios)
COVER = 0.85     # segundo intento: parte de la página que tienen que cubrir las viñetas
IMAGES = ('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp')


class Page:
    def __init__(self, img):
        img = img.convert('RGB')
        self.h = max(20, round(img.height * W / img.width))
        self.w = W
        self.a = np.asarray(img.resize((W, self.h), Image.BILINEAR)).astype(int)
        self.pieces = []

    def line(self, horizontal, k, a0, a1):
        return self.a[k, a0:a1] if horizontal else self.a[a0:a1, k]


def near(px, c):
    return np.abs(px - c).max(axis=1) <= TOL


def same(c, o):
    return np.abs(c - o).max() <= SIMILAR


def adding(c, colors):
    return colors if any(same(c, o) for o in colors) else colors + [c]


def separator(px, colors, loose=True):
    # loose: las puntas solo tienen que tocar el color en el último 5 %; al recortar bordes (trim) se pide más.
    n = len(px)
    if n == 0:
        return None
    end = max(2, n * EDGE // 100) if loose else max(2, n // 50)
    for c in colors:
        m = near(px, c)
        if m.sum() < SHARE * n:
            continue
        if loose and m[:end].any() and m[-end:].any():
            return c
        if not loose and m[:end].sum() * 2 >= end and m[-end:].sum() * 2 >= end:
            return c
    return None


def page_colors(pg, skip=0, uniform=95):
    found = []  # [color, count]
    for horizontal in (True, False):
        lines, length = (pg.h, pg.w) if horizontal else (pg.w, pg.h)
        for k in range(lines):
            px = pg.line(horizontal, k, length * skip // 100, length - length * skip // 100)
            c = px.mean(axis=0).astype(int)
            if near(px, c).sum() * 100 >= len(px) * uniform:
                for f in found:
                    if same(f[0], c):
                        f[1] += 1
                        break
                else:
                    found.append([c, 1])
    found = [f for f in found if f[1] >= 2]
    found.sort(key=lambda f: -f[1])
    return [f[0] for f in found[:3]]


def trim(pg, b, colors):
    x0, y0, x1, y1 = b
    changed = True
    while changed and x1 - x0 > 4 and y1 - y0 > 4:
        changed = False
        if separator(pg.line(True, y0, x0, x1), colors, False) is not None: y0 += 1; changed = True
        if y1 - y0 > 4 and separator(pg.line(True, y1 - 1, x0, x1), colors, False) is not None: y1 -= 1; changed = True
        if separator(pg.line(False, x0, y0, y1), colors, False) is not None: x0 += 1; changed = True
        if x1 - x0 > 4 and separator(pg.line(False, x1 - 1, y0, y1), colors, False) is not None: x1 -= 1; changed = True
    return x0, y0, x1, y1


def cut(pg, b, colors, depth, rtl):
    x0, y0, x1, y1 = trim(pg, b, colors)
    if x1 - x0 < 8 or y1 - y0 < 8:
        return
    if depth < 10:
        for horizontal in (True, False):
            lines = range(y0, y1) if horizontal else range(x0, x1)
            a0, a1 = (x0, x1) if horizontal else (y0, y1)
            seps = [separator(pg.line(horizontal, k, a0, a1), colors) for k in lines]
            min_band = max(3, (pg.h if horizontal else pg.w) * 4 // 100)
            bands, start = [], None
            for i, s in enumerate(seps):
                if s is None and start is None: start = i
                if s is not None and start is not None: bands.append((start, i)); start = None
            if start is not None: bands.append((start, len(seps)))
            bands = [bd for bd in bands if bd[1] - bd[0] >= min_band]
            if len(bands) < 2:
                continue
            used = []
            for (_, e), (n, _) in zip(bands, bands[1:]):
                run = [c for c in seps[e:n] if c is not None]
                if run:
                    best = max(run, key=lambda c: sum(1 for o in run if same(o, c)))
                    used = adding(best, used)
            used = used or colors
            base = y0 if horizontal else x0
            ordered = bands[::-1] if (not horizontal and rtl) else bands
            for s, e in ordered:
                part = (x0, base + s, x1, base + e) if horizontal else (base + s, y0, base + e, y1)
                cut(pg, part, used, depth + 1, rtl)
            return
    pg.pieces.append((x0, y0, x1, y1))


def detect(img, rtl=False):
    """Viñetas en orden de lectura, como (x, y, ancho, alto) de 0 a 1. [] si no hay."""
    if img.width <= 40 or img.height <= 40:
        return []
    pg = Page(img)
    if pg.h > pg.w * 4:
        return []
    # Primer intento: colores de filas o columnas enteras. Si no hay ninguna, puede haber un marco
    # dibujado alrededor de la página: se mira sin el 5 % de cada borde.
    found = panels_with(pg, page_colors(pg) or page_colors(pg, EDGE), rtl)
    if found:
        return found
    # Segundo intento, más flexible (márgenes de otro color, calles finitas): sin mirar el 5 % de cada
    # borde y con 90 % de un color. Solo vale si las viñetas cubren casi toda la página (si no, son
    # pedazos de una tapa o de un dibujo grande).
    found = panels_with(pg, page_colors(pg, EDGE, 90), rtl)
    if sum(w * h for _, _, w, h in found) >= COVER:
        return found
    return []


def panels_with(pg, colors, rtl):
    if not colors:
        return []
    pg.pieces = []
    cut(pg, (0, 0, pg.w, pg.h), colors, 0, rtl)
    area = pg.w * pg.h
    found = [p for p in pg.pieces
             if (p[2] - p[0]) * 10 >= pg.w and (p[3] - p[1]) * 100 >= pg.h * 6
             and (p[2] - p[0]) * (p[3] - p[1]) * 100 >= area * 2]
    if len(found) < 2 or any((p[2] - p[0]) * (p[3] - p[1]) * 100 >= area * 85 for p in found):
        return []
    return [(p[0] / pg.w, p[1] / pg.h, (p[2] - p[0]) / pg.w, (p[3] - p[1]) / pg.h) for p in found]


# ---------- Leer cómics ----------

def pages_of(path, limit):
    """Devuelve [(nombre, Image)] con hasta `limit` páginas repartidas por el cómic."""
    names, opener = [], None
    low = path.lower()
    if os.path.isdir(path):
        names = sorted(f for f in os.listdir(path) if f.lower().endswith(IMAGES))
        opener = lambda n: Image.open(os.path.join(path, n))
    elif low.endswith(('.cbz', '.zip')) or zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        names = sorted(n for n in z.namelist() if n.lower().endswith(IMAGES) and '__MACOSX' not in n)
        opener = lambda n: Image.open(io.BytesIO(z.read(n)))
    elif low.endswith(('.cbr', '.rar', '.cb7', '.7z')):
        tmp = tempfile.mkdtemp(prefix='vinetas-')
        for tool in (['7z', 'x', '-y', f'-o{tmp}', path], ['unrar', 'x', '-y', path, tmp + os.sep]):
            try:
                subprocess.run(tool, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                break
            except (OSError, subprocess.CalledProcessError):
                continue
        else:
            print(f'  (no se pudo abrir {os.path.basename(path)}: instalá 7-Zip o unrar)')
            return []
        files = []
        for root, _, fs in os.walk(tmp):
            files += [os.path.join(root, f) for f in fs if f.lower().endswith(IMAGES)]
        names = sorted(files)
        opener = lambda n: Image.open(n)
    else:
        return []
    if not names:
        return []
    step = max(1, len(names) / max(1, limit))
    chosen = sorted({names[min(len(names) - 1, int(i * step))] for i in range(min(limit, len(names)))})
    out = []
    for n in chosen:
        try:
            out.append((os.path.basename(n), opener(n).convert('RGB')))
        except Exception:
            pass
    return out


def annotate(img, panels):
    im = img.copy()
    im.thumbnail((500, 760))
    d = ImageDraw.Draw(im)
    for i, (x, y, w, h) in enumerate(panels):
        box = (x * im.width, y * im.height, (x + w) * im.width, (y + h) * im.height)
        d.rectangle(box, outline=(0, 230, 0), width=4)
        d.rectangle((box[0], box[1], box[0] + 26, box[1] + 26), fill=(0, 150, 0))
        d.text((box[0] + 7, box[1] + 5), str(i + 1), fill='white')
    if not panels:
        d.rectangle((0, 0, im.width - 1, im.height - 1), outline=(230, 0, 0), width=6)
    return im


def sheet(images, cols=5):
    w = max(i.width for i in images); h = max(i.height for i in images)
    rows = (len(images) + cols - 1) // cols
    s = Image.new('RGB', (cols * (w + 8), rows * (h + 8)), (60, 60, 60))
    for i, im in enumerate(images):
        s.paste(im, ((i % cols) * (w + 8), (i // cols) * (h + 8)))
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('carpeta')
    ap.add_argument('--salida', default='resultados-vinetas')
    ap.add_argument('--paginas', type=int, default=20)
    ap.add_argument('--manga', action='store_true', help='orden de derecha a izquierda')
    args = ap.parse_args()
    os.makedirs(args.salida, exist_ok=True)
    items = sorted(os.listdir(args.carpeta))
    lines = []
    for name in items:
        path = os.path.join(args.carpeta, name)
        pages = pages_of(path, args.paginas)
        if not pages:
            continue
        print(name)
        shots, counts = [], []
        for pname, img in pages:
            panels = detect(img, args.manga)
            counts.append(len(panels))
            shots.append(annotate(img, panels))
            lines.append(f'{name}\t{pname}\t{len(panels)}')
        out = os.path.join(args.salida, os.path.splitext(name)[0][:80] + '.jpg')
        sheet(shots).save(out, quality=80)
        empty = sum(1 for c in counts if c == 0)
        print(f'  {len(pages)} páginas, {empty} sin viñetas (borde rojo) -> {out}')
    with open(os.path.join(args.salida, 'resumen.txt'), 'w', encoding='utf-8') as f:
        f.write('comic\tpagina\tvinetas\n' + '\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
