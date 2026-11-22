#!/usr/bin/env python3
"""Saca páginas sueltas de los cómics de una carpeta, para marcarlas con marcar_vinetas.py.

Uso:
    python tools/vinetas/sacar_paginas.py "CARPETA_CON_COMICS" "CARPETA_DE_PAGINAS" [--paginas 12] [--ancho 800]

- Toma hasta N páginas repartidas de cada cómic (igual que probar_vinetas.py) y las guarda como .jpg de ese ancho.
- Las páginas tienen derechos de autor: quedan en la computadora, NO se suben a GitHub.
"""
import argparse, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probar_vinetas  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('carpeta')
    ap.add_argument('salida')
    ap.add_argument('--paginas', type=int, default=12)
    ap.add_argument('--ancho', type=int, default=800)
    args = ap.parse_args()
    os.makedirs(args.salida, exist_ok=True)
    for name in sorted(os.listdir(args.carpeta)):
        pages = probar_vinetas.pages_of(os.path.join(args.carpeta, name), args.paginas)
        for i, (_, img) in enumerate(pages):
            h = max(20, round(img.height * args.ancho / img.width))
            out = os.path.join(args.salida, f'{name[:40]}__{i:02d}.jpg')
            img.resize((args.ancho, h), Image.BILINEAR).save(out, quality=90)
        if pages:
            print(name, len(pages))


if __name__ == '__main__':
    main()
