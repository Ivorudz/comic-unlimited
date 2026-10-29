# Rutas de la guía "Por dónde empezar"

Estos programas arman los archivos `ComicUnlimited/Guides/ruta-*.json` (no van dentro de la app; se usan una vez, en una compu o en la nube).

1. Bajar la colección pública https://github.com/DieselTech/CBL-ReadingLists (por ejemplo, `git clone --depth 1`).
2. `python3 eventos.py <carpeta de CBL-ReadingLists> eventos.json`
   Junta, de las listas de las carpetas `Events`, qué serie y volumen son el "centro" de cada evento (mismo nombre que la lista).
3. `python3 armar_rutas.py <carpeta de CBL-ReadingLists> eventos.json ../../ComicUnlimited/Guides`
   Lee las listas de CBRO "with events" y "no events" de cada ruta y escribe un JSON por ruta.
4. Para revisar el orden: `python3 ver_camino.py ../../ComicUnlimited/Guides/ruta-avengers.json esencial "New Avengers (2004)" 40` (o `todo` en vez de `esencial`).

Formato de cada JSON: `series` = [nombre, volumen]; `items` = [código de Comic Vine, serie, número, tipo] con tipo 1 = serie principal (lista `PRINCIPAL`), 2 = centro de un evento, 0 = extra (otras series y cruces); `stages` = eras {t: nombre, y: años, i: desde qué posición}; `marks` = {i, t, k: "s" empezá por acá / "e" evento}.
