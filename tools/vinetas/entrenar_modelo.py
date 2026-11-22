#!/usr/bin/env python3
"""Entrena el modelo de viñetas con las páginas marcadas en marcar_vinetas.py y lo compara con las reglas.

Uso:
    python tools/vinetas/entrenar_modelo.py "CARPETA_DE_PAGINAS" "CARPETA_DE_ETIQUETAS" "modelo.pt" [--vueltas 60]

- Separa algunos cómics enteros para examen (el modelo nunca los ve al aprender) y al final dice, en esas
  páginas, cuántas acierta el modelo y cuántas las reglas.
- Una página "acierta" si encuentra las mismas viñetas que las marcadas (cada una superpuesta en un 75 % o más).
- Necesita: pip install torch torchvision pillow numpy (con placa NVIDIA, la versión de torch con CUDA).
"""
import argparse, json, os, random, sys, time, zlib
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image, ImageEnhance, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import modelo_vinetas as mv  # noqa: E402
import probar_vinetas  # noqa: E402


def cargar(pages, labels):
    data = []
    for f in sorted(os.listdir(labels)):
        if not f.endswith('.json'):
            continue
        with open(os.path.join(labels, f), encoding='utf-8') as fh:
            d = json.load(fh)
        if d.get('kind') == 'skip':
            continue
        img = os.path.join(pages, f[:-5] + '.jpg')
        if os.path.exists(img):
            data.append((img, d['boxes']))
    return data


def es_examen(path):
    comic = os.path.basename(path).rsplit('__', 1)[0]
    return zlib.crc32(comic.encode('utf-8')) % 100 < 15  # 15 % de los cómics, siempre los mismos


def aumentar(img, boxes, rng):
    """Variaciones al azar para que aprenda mejor: recorte, espejo, color, blanco y negro."""
    w, h = img.size
    if rng.random() < 0.6:
        s = rng.uniform(0.8, 1.0)
        cw, ch = int(w * s), int(h * s)
        x0, y0 = rng.randint(0, w - cw), rng.randint(0, h - ch)
        img = img.crop((x0, y0, x0 + cw, y0 + ch))
        nb = []
        for bx, by, bw, bh in boxes:
            a0, b0 = max(bx * w, x0), max(by * h, y0)
            a1, b1 = min((bx + bw) * w, x0 + cw), min((by + bh) * h, y0 + ch)
            if a1 - a0 > 0.25 * bw * w and b1 - b0 > 0.25 * bh * h:  # lo que queda muy cortado se descarta
                nb.append(((a0 - x0) / cw, (b0 - y0) / ch, (a1 - a0) / cw, (b1 - b0) / ch))
        boxes = nb
    if rng.random() < 0.5:
        img = ImageOps.mirror(img)
        boxes = [(1 - x - bw, y, bw, bh) for x, y, bw, bh in boxes]
    if rng.random() < 0.2:
        img = ImageOps.grayscale(img).convert('RGB')
    img = ImageEnhance.Brightness(img).enhance(rng.uniform(0.75, 1.25))
    img = ImageEnhance.Contrast(img).enhance(rng.uniform(0.75, 1.25))
    img = ImageEnhance.Color(img).enhance(rng.uniform(0.6, 1.4))
    return img, boxes


class Datos(torch.utils.data.Dataset):
    def __init__(self, items, train):
        self.items, self.train = items, train
        self.rng = random.Random()

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        path, boxes = self.items[i]
        img = Image.open(path).convert('RGB')
        if self.train:
            img, boxes = aumentar(img, boxes, self.rng)
        x = mv.preparar(img)[0]
        y = torch.from_numpy(mv.mascara(boxes, mv.W // 2, mv.H // 2).astype(np.int64))
        return x, y


def iou(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    inter = max(0, x1 - x0) * max(0, y1 - y0)
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


def como_la_app(boxes):
    return [] if len(boxes) < 2 or any(b[2] * b[3] >= 0.85 for b in boxes) else boxes


def acierta(pred, real, umbral=0.75):
    real = como_la_app(real)
    if len(pred) != len(real):
        return False
    libres = list(real)
    for p in pred:
        mejor = max(libres, key=lambda r: iou(p, r), default=None)
        if mejor is None or iou(p, mejor) < umbral:
            return False
        libres.remove(mejor)
    return True


def examen(model, items, device):
    model.eval()
    ok_m = ok_r = 0
    fallas = []
    for path, boxes in items:
        img = Image.open(path).convert('RGB')
        m = acierta(mv.recuadros(model, img, device), boxes)
        r = acierta(probar_vinetas.detect(img), boxes)
        ok_m += m
        ok_r += r
        if not m:
            fallas.append(os.path.basename(path))
    return ok_m, ok_r, fallas


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('paginas')
    ap.add_argument('etiquetas')
    ap.add_argument('salida')
    ap.add_argument('--vueltas', type=int, default=60)
    ap.add_argument('--lote', type=int, default=8)
    args = ap.parse_args()
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    data = cargar(args.paginas, args.etiquetas)
    train = [d for d in data if not es_examen(d[0])]
    test = [d for d in data if es_examen(d[0])]
    print(f'{len(data)} páginas marcadas: {len(train)} para aprender, {len(test)} para examen. Usando {device}.')
    if len(train) < 20 or not test:
        sys.exit('Faltan páginas marcadas.')

    torch.manual_seed(0)
    model = mv.ModeloVinetas().to(device)
    loader = torch.utils.data.DataLoader(Datos(train, True), batch_size=args.lote, shuffle=True,
                                         num_workers=4, drop_last=True, persistent_workers=True)
    enc = list(model.enc.parameters())
    dec = [p for n, p in model.named_parameters() if not n.startswith('enc.')]
    opt = torch.optim.AdamW([{'params': enc, 'lr': 3e-4}, {'params': dec, 'lr': 1e-3}], weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=[3e-4, 1e-3], total_steps=args.vueltas * len(loader))
    peso = torch.tensor([1.0, 1.0, 3.0], device=device)  # el borde es poquito: que pese más
    scaler = torch.amp.GradScaler(enabled=device == 'cuda')
    mejor = -1
    for ep in range(args.vueltas):
        model.train()
        t, total = time.time(), 0.0
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            with torch.autocast(device, enabled=device == 'cuda'):
                loss = F.cross_entropy(model(x), y, weight=peso)
            opt.zero_grad()
            scaler.scale(loss).backward()
            scaler.step(opt)
            scaler.update()
            sched.step()
            total += loss.item()
        msg = f'vuelta {ep + 1}/{args.vueltas}  error {total / len(loader):.3f}  ({time.time() - t:.0f} s)'
        if (ep + 1) % 5 == 0 or ep + 1 == args.vueltas:
            ok_m, ok_r, _ = examen(model, test, device)
            msg += f'  examen: modelo {ok_m}/{len(test)}, reglas {ok_r}/{len(test)}'
            if ok_m >= mejor:
                mejor = ok_m
                torch.save(model.state_dict(), args.salida)
                msg += '  (guardado)'
        print(msg, flush=True)
    model.load_state_dict(torch.load(args.salida, map_location=device))
    ok_m, ok_r, fallas = examen(model, test, device)
    print(f'\nResultado en {len(test)} páginas de examen: modelo {ok_m} bien ({100 * ok_m / len(test):.0f} %), '
          f'reglas {ok_r} bien ({100 * ok_r / len(test):.0f} %).')
    print('Páginas donde el modelo falla:', *fallas, sep='\n  ')


if __name__ == '__main__':
    main()
