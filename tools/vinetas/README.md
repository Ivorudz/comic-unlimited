# Probar la detección de viñetas con cómics propios

Herramienta para la computadora (no va dentro de la app). Usa la misma lógica que
`ComicUnlimited/PanelDetector.swift`, así se puede probar y ajustar con cómics reales.

## Uso

```
pip install pillow numpy
python3 tools/vinetas/probar_vinetas.py "/ruta/a/la/carpeta/de/comics" --salida resultados-vinetas
```

- `--paginas 20`: cuántas páginas mirar de cada cómic (repartidas de principio a fin).
- `--manga`: orden de derecha a izquierda.
- Para .cbr/.rar hace falta 7-Zip (`7z`) o `unrar` instalado.

Deja en `resultados-vinetas/` una imagen por cómic: recuadros verdes numerados en orden de
lectura; las páginas donde no encontró viñetas tienen borde rojo. También `resumen.txt`.

## Reglas

- Los cómics y las imágenes de resultado tienen derechos de autor: **no se suben a GitHub**
  (`resultados-vinetas/` está en `.gitignore`). Solo se miran en la computadora.
- Si se cambia la detección acá, hay que hacer el mismo cambio en `PanelDetector.swift`
  (y subir `PanelStore.version` para que la app vuelva a analizar las páginas).
