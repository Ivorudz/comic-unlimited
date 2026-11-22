"""Modelo de viñetas: red chica que pinta cada punto de la página como fondo, adentro de viñeta o borde.

Lo usan entrenar_modelo.py (entrenar y medir) y exportar_coreml.py (pasarlo al iPhone).
La red es una MobileNetV3 (de torchvision, licencia BSD) con un "decodificador" tipo U-Net que devuelve
el dibujo a la mitad del tamaño de entrada. Los recuadros salen de las manchas "adentro" (componentes_a_recuadros).
"""
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision.models import mobilenet_v3_large, MobileNet_V3_Large_Weights

W, H = 320, 480          # tamaño de entrada (las páginas se estiran a esto, también las apaisadas)
BAND = 0.012             # ancho del "borde" alrededor de cada viñeta, en proporción del lado de la página
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


class Bloque(nn.Module):
    def __init__(self, cin, cout):
        super().__init__()
        self.c = nn.Sequential(nn.Conv2d(cin, cout, 3, padding=1, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True),
                               nn.Conv2d(cout, cout, 3, padding=1, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True))

    def forward(self, x):
        return self.c(x)


class ModeloVinetas(nn.Module):
    # Capas de MobileNetV3 donde se toman las salidas (tamaños 1/2, 1/4, 1/8, 1/16, 1/32).
    CORTES = (1, 3, 6, 12, 16)

    def __init__(self, pretrained=True):
        super().__init__()
        weights = MobileNet_V3_Large_Weights.IMAGENET1K_V2 if pretrained else None
        self.enc = mobilenet_v3_large(weights=weights).features
        ch = [16, 24, 40, 112, 960]
        self.up4 = Bloque(ch[4] + ch[3], 128)
        self.up3 = Bloque(128 + ch[2], 64)
        self.up2 = Bloque(64 + ch[1], 48)
        self.up1 = Bloque(48 + ch[0], 32)
        self.out = nn.Conv2d(32, 3, 1)

    def forward(self, x):
        feats = []
        for i, layer in enumerate(self.enc):
            x = layer(x)
            if i in self.CORTES:
                feats.append(x)
        f1, f2, f3, f4, f5 = feats
        x = self.up4(torch.cat([F.interpolate(f5, size=f4.shape[2:], mode='bilinear', align_corners=False), f4], 1))
        x = self.up3(torch.cat([F.interpolate(x, size=f3.shape[2:], mode='bilinear', align_corners=False), f3], 1))
        x = self.up2(torch.cat([F.interpolate(x, size=f2.shape[2:], mode='bilinear', align_corners=False), f2], 1))
        x = self.up1(torch.cat([F.interpolate(x, size=f1.shape[2:], mode='bilinear', align_corners=False), f1], 1))
        return self.out(x)  # 3 clases, a la mitad del tamaño de entrada


def mascara(boxes, w, h):
    """Dibujo de entrenamiento: 0 fondo, 1 adentro de viñeta, 2 borde. boxes en proporción (x, y, ancho, alto)."""
    m = np.zeros((h, w), np.uint8)
    bx, by = max(1, round(BAND * w)), max(1, round(BAND * h))
    rects = []
    for x, y, bw, bh in boxes:
        x0, y0 = round(x * w), round(y * h)
        x1, y1 = round((x + bw) * w), round((y + bh) * h)
        rects.append((x0, y0, x1, y1))
        m[y0:y1, x0:x1] = 1
    for x0, y0, x1, y1 in rects:  # los bordes van encima, así separan viñetas pegadas o encimadas
        m[max(0, y0 - by):y0 + by, max(0, x0 - bx):x1 + bx] = 2
        m[max(0, y1 - by):y1 + by, max(0, x0 - bx):x1 + bx] = 2
        m[max(0, y0 - by):y1 + by, max(0, x0 - bx):x0 + bx] = 2
        m[max(0, y0 - by):y1 + by, max(0, x1 - bx):x1 + bx] = 2
    return m


def componentes_a_recuadros(clases, min_area=0.004):
    """De la salida (h, w con 0/1/2) a recuadros (x, y, ancho, alto) en proporción. Misma lógica que en Swift."""
    h, w = clases.shape
    adentro = clases == 1
    seen = np.zeros_like(adentro)
    bx, by = BAND * w, BAND * h
    out = []
    for sy in range(h):
        for sx in range(w):
            if not adentro[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            x0 = x1 = sx
            y0 = y1 = sy
            n = 0
            while stack:
                y, x = stack.pop()
                n += 1
                x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < h and 0 <= nx < w and adentro[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if n < min_area * w * h:
                continue
            # El borde pintado se come un poco de la viñeta: se agrega de vuelta.
            fx0, fy0 = max(0, x0 - bx), max(0, y0 - by)
            fx1, fy1 = min(w, x1 + 1 + bx), min(h, y1 + 1 + by)
            out.append((fx0 / w, fy0 / h, (fx1 - fx0) / w, (fy1 - fy0) / h))
    return out


def orden_lectura(boxes, rtl=False):
    """Filas de arriba a abajo (viñetas que se pisan en altura van en la misma fila); en cada fila, de izquierda a
    derecha (o al revés en manga)."""
    rest = sorted(boxes, key=lambda b: b[1])
    out = []
    while rest:
        first = rest[0]
        row = [b for b in rest if b[1] < first[1] + first[3] * 0.5]
        rest = [b for b in rest if b not in row]
        row.sort(key=lambda b: -(b[0] + b[2]) if rtl else b[0])
        out += row
    return out


def preparar(img):
    """PIL → tensor normalizado (1, 3, H, W)."""
    a = np.asarray(img.convert('RGB').resize((W, H)), np.float32) / 255.0
    a = (a - MEAN) / STD
    return torch.from_numpy(a.transpose(2, 0, 1).copy()).float()[None]


def recuadros(model, img, device='cpu', rtl=False):
    with torch.no_grad():
        clases = model(preparar(img).to(device)).argmax(1)[0].cpu().numpy()
    boxes = orden_lectura(componentes_a_recuadros(clases), rtl)
    # Igual que las reglas: una sola viñeta, o una que ocupa casi toda la página, es "sin viñetas".
    if len(boxes) < 2 or any(b[2] * b[3] >= 0.85 for b in boxes):
        return []
    return boxes
