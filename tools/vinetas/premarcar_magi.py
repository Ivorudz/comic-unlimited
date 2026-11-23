#!/usr/bin/env python3
"""Marca las viñetas automáticamente con Magi (modelo de la Universidad de Oxford), solo en la computadora.

Uso:
    python tools/vinetas/premarcar_magi.py "CARPETA_CON_PAGINAS" "CARPETA_MAGI"

- Deja en CARPETA_MAGI un .json por página con los recuadros que encontró Magi (mismo formato que las etiquetas).
- Sirve para comparar Magi con las páginas marcadas a mano (todavía no lo usan las otras herramientas).
- Magi NO va dentro de la app: es grande (2 GB) y su licencia permite solo uso personal y no comercial
  (https://huggingface.co/ragavsachdeva/magi). La primera vez lo baja de Hugging Face.
Necesita: pip install "transformers==4.44.2" accelerate timm einops shapely networkx matplotlib pillow numpy torch
"""
import argparse, json, os
import numpy as np
import torch
from PIL import Image
from transformers import AutoModel

REVISION = '15ad498ad45093ad3b833d625728220c6309ad99'  # versión fija: el código del modelo no cambia sin que lo sepamos
IMAGES = ('.jpg', '.jpeg', '.png', '.webp')


def recuadros(results, w, h):
    out = []
    for x0, y0, x1, y1 in results['panels']:
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(w, x1), min(h, y1)
        if x1 - x0 > 0.01 * w and y1 - y0 > 0.01 * h:
            out.append([round(x0 / w, 4), round(y0 / h, 4), round((x1 - x0) / w, 4), round((y1 - y0) / h, 4)])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('paginas')
    ap.add_argument('salida')
    ap.add_argument('--umbral', type=float, default=0.2, help='confianza mínima de Magi para una viñeta')
    args = ap.parse_args()
    os.makedirs(args.salida, exist_ok=True)
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    model = AutoModel.from_pretrained('ragavsachdeva/magi', revision=REVISION, trust_remote_code=True,
                                      use_safetensors=True).to(device).eval()
    names = sorted(f for f in os.listdir(args.paginas) if f.lower().endswith(IMAGES))
    hechas = 0
    for i, name in enumerate(names):
        dst = os.path.join(args.salida, os.path.splitext(name)[0] + '.json')
        if os.path.exists(dst):
            continue
        img = Image.open(os.path.join(args.paginas, name)).convert('L').convert('RGB')  # Magi trabaja en grises
        with torch.no_grad():
            res = model.predict_detections_and_associations([np.array(img)], panel_detection_threshold=args.umbral)[0]
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump({'boxes': recuadros(res, *img.size), 'kind': 'magi'}, f)
        hechas += 1
        if hechas % 50 == 0:
            print(f'{i + 1}/{len(names)}', flush=True)
    print(f'Listo: {hechas} páginas nuevas en {args.salida}')


if __name__ == '__main__':
    main()
