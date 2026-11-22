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

## Modelo entrenado (PanelModel.swift)

La app primero usa un modelo entrenado (`ComicUnlimited/Vinetas.mlmodel`); si no está o falla, usa las
reglas de `PanelDetector.swift`. Para entrenarlo de nuevo (hace falta una placa NVIDIA o mucha paciencia):

```
pip install pillow numpy torch torchvision coremltools
python tools/vinetas/sacar_paginas.py "CARPETA_CON_COMICS" paginas
python tools/vinetas/marcar_vinetas.py paginas etiquetas      # marcar a mano en el navegador
python tools/vinetas/entrenar_modelo.py paginas etiquetas modelo.pt
python tools/vinetas/exportar_coreml.py modelo.pt              # deja ComicUnlimited/Vinetas.mlmodel
python tools/vinetas/probar_vinetas.py "CARPETA_CON_COMICS" --modelo modelo.pt
```

- `marcar_vinetas.py` abre `http://127.0.0.1:8765`: cada página trae los recuadros de las reglas para
  corregir. Un recuadro por viñeta; `T` = página de un solo dibujo; `X` = texto o publicidad.
- `entrenar_modelo.py` separa el 15 % de los cómics para examen y al final dice cuántas páginas de
  examen acierta el modelo y cuántas las reglas.
- El modelo (`modelo_vinetas.py`) es una MobileNetV3 (torchvision, licencia BSD) con un decodificador
  tipo U-Net: pinta cada punto como fondo, adentro de viñeta o borde, y cada mancha de "adentro" es
  una viñeta. Si se cambia cómo se arman los recuadros, cambiarlo también en `PanelModel.swift`.
- Las páginas, las etiquetas y `modelo.pt` quedan en la compu. Solo `Vinetas.mlmodel` va al repositorio
  (no tiene imágenes; son los números que aprendió).

## Reglas

- Los cómics y las imágenes de resultado tienen derechos de autor: **no se suben a GitHub**
  (`resultados-vinetas/` está en `.gitignore`). Solo se miran en la computadora.
- Si se cambia la detección acá, hay que hacer el mismo cambio en `PanelDetector.swift`
  (y subir `PanelStore.version` para que la app vuelva a analizar las páginas).
