# Cómic Unlimited — reglas del proyecto

App de iPhone para leer cómics, hecha en SwiftUI. La dueña o dueño del proyecto **no sabe programar** y **no tiene computadora**: todo se hace desde el celular.

## Cómo hablar

- Explicá todo en **español simple**, sin jerga. Si usás una palabra técnica, explicala en una frase.
- Respuestas cortas: primero el resultado, después los detalles.

## Cómo trabajar

- **Cambios chicos**: un paso a la vez. Nada de rehacer media app de golpe.
- **Preguntar antes de compilar o deshacer**: antes de subir cambios que generen una versión nueva (build) o de revertir algo, escribir qué se va a hacer y preguntar si se hace. Recién con el "sí" se sube.
- **Siempre decir cómo probar cada cambio**: qué tocar en el iPhone y qué se debería ver.
- **Nunca usar contenido con derechos de autor**: no copiar dentro de la app portadas, logos, páginas, dibujos ni textos de obras ajenas. Los cómics de ejemplo para leer son inventados y los dibujos se generan con código (`Drawing.swift`).
- **Sí se puede mencionar cómics reales como información**: título, número, fecha de salida, autores y editorial (como el catálogo de una comiquería). Para eso son **Próximos** (saber qué sale y cuándo comprarlo) y **Comunidad** (charlar sobre esos cómics). Para ver una portada oficial, se pone un enlace a la página de la editorial o de la tienda; no se copia la imagen.
- **Portadas y datos de cómics reales: solo desde Comic Vine** (comicvine.gamespot.com/api) **o Metron** (metron.cloud). La app es de uso personal y no comercial.
  - **Próximos** usa Metron primero y, si falla o no está configurado, Comic Vine. **El buscador** de cómics reales usa Comic Vine.
  - Metron: usuario y contraseña de metron.cloud, guardados solo en el iPhone (nunca en el código ni en GitHub). Límite: unas 20 consultas por minuto y 5.000 por día. Hay que confirmar que sus condiciones permiten este uso.
  - Las mismas reglas de abajo valen para las portadas y los datos de Metron.
  - Las portadas se cargan desde internet al momento de verlas; nunca se guardan dentro de la app ni en el repositorio.
  - Se muestra "Datos y portadas: Comic Vine (o Metron). Las portadas pertenecen a sus editoriales." y, cuando se puede, un enlace a la ficha del cómic.
  - La clave de Comic Vine (API key) **nunca** va en el código ni en GitHub (el repositorio es público): se escribe en la app y queda guardada solo en el iPhone.
  - Límite de Comic Vine: unas 200 consultas por hora. No hacer pedidos de más.
- **Órdenes de lectura**: de las listas .cbl de la colección pública github.com/DieselTech/CBL-ReadingLists (hecha para apps de cómics; órdenes de CBRO, CMRO, League of Comic Geeks, Marvel Guides…, con el código de Comic Vine de cada número) o de Metron. Solo se bajan los nombres de las listas (índice, 1 vez por semana) y la lista elegida; no se leen páginas web.
- Sin dependencias externas (sin paquetes de terceros dentro de la app).
- **Fuentes** (Biblioteca → Fuentes): catálogos que se agregan con el link de un JSON (formato en `FUENTES.md`). La app **no trae fuentes incluidas**, **no ejecuta programas** de las fuentes (solo lee la lista y descarga links directos `https://`) y **no se arman fuentes de sitios sin permiso** para compartir esos cómics.
- `comic-unlimited.html` es el prototipo web: es la referencia de diseño, textos y comportamiento.

## Cómo está armado

- `project.yml`: receta de XcodeGen. El `.xcodeproj` **no** se guarda en el repo; se genera al compilar.
- `ComicUnlimited/`: el código de la app (iOS 17 o superior).
  - `App.swift`: arranque y las cinco pestañas.
  - `HomeView.swift`: pestaña Inicio (Seguir leyendo con tus archivos, y Descubrir).
  - `Discover.swift`: fila "Recién salidos" de Inicio (cómics reales de la última semana).
  - `ForYou.swift`: "Para vos" en Inicio; sugerencias de series reales según tus puntajes y listas.
  - `RealLibrary.swift`: tus cómics y series reales (Quiero leer / Leyendo / Leído y puntaje), guardados en el iPhone.
  - `ProfileView.swift`: pestaña Perfil; tus listas de cómics reales y números rápidos.
  - `LibraryView.swift`: pestaña Biblioteca; importar archivos y elegir cómo verlos (Todos, Series, Arcos, Editoriales, Estado).
  - `LibraryGroups.swift`: carpetas de la Biblioteca (serie con "Te faltan", estado), tarjeta y menú de cada cómic.
  - `LibraryArcs.swift`: carpetas por arco (todos sus números por fecha, los que faltan en gris) y por editorial.
  - `LocalLibrary.swift`: guarda una copia de tus archivos, su portada, la página donde quedaste y su unión con Comic Vine.
  - `LocalReader.swift`: lector de tus archivos (páginas en segundo plano, zoom, dirección izq/der/vertical, ajuste entera/ancho/alto, miniaturas, tocar bordes, pantalla encendida y modo nocturno; opciones en el engranaje).
  - `ComicVineMatch.swift`: lee el nombre del archivo (serie, número, año), busca su ficha en Comic Vine y permite elegirla a mano.
  - `PackExtractor.swift`: saca los cómics de adentro de un paquete .zip o .rar (con libarchive), para importarlos por separado.
  - `CbrConverter.swift`: convierte .cbr (RAR) a .cbz con libarchive; escribe .zip sin comprimir.
  - `ComicUnlimited-Bridging-Header.h`: declara las funciones de libarchive que usa Swift.
  - `ComicArchive.swift`: abre .cbz/.zip/.cbr-que-es-zip (lector de zip hecho a mano con Compression de Apple) y PDF (PDFKit).
  - `DetailView.swift`: ficha de un cómic.
  - `ReaderView.swift`: lector a pantalla completa.
  - `UpcomingView.swift`: pestaña Próximos (lanzamientos por semana).
  - `ComicVine.swift`: conexión con Comic Vine y carga de portadas.
  - `ComicVineBrowse.swift`: buscador de cómics reales, ficha de serie y ficha de número.
  - `ComicVineExtras.swift`: personajes y arcos con imagen; traducción automática de textos de Comic Vine (traductor de Apple, iOS 18+).
  - `LibraryActionsHost.swift`: ventanas del menú de cada cómic (elegir ficha, cambiar nombre, borrar), en la raíz de la app.
  - `Sources.swift`: fuentes (formato del JSON, guardarlas, buscar versiones nuevas) y descargas con avance.
  - `SourcesViews.swift`: pantallas de Fuentes (lista, agregar con link, catálogo con botón Descargar).
  - `WordPress.swift`: "Mi página WordPress": lee las publicaciones de tu página y descarga sus archivos.
  - `LibraryAvailability.swift`: botón En biblioteca / Descargar de cada ficha, "Buscar en tus fuentes" y destinos de navegación compartidos.
  - `LocalComicDetail.swift`: ficha de un archivo tuyo sin ficha de Comic Vine.
  - `TPB.swift`: TPB (tomos): qué números trae cada uno, leer "Collects…" de Comic Vine, pantalla para elegirlos y tarjeta "En TPB".
  - `LinkReview.swift`: Revisar fichas que eligió la app y unir un archivo desde la ficha de Comic Vine.
  - `Metron.swift`: conexión con Metron (lanzamientos de la semana).
  - `ReadingOrders.swift`: órdenes de lectura: buscar en la colección de listas .cbl y en Metron, leer .cbl, elegir y guardar el orden de un arco.
  - `Diagnostics.swift`: "Revisar conexión" en Próximos; prueba Metron y Comic Vine y arma un texto para copiar.
  - `ReadingStore.swift`: guarda en el celular la página donde quedaste.
  - `Comic.swift`: los 6 cómics de ejemplo.
  - `Drawing.swift`: dibuja portadas y páginas.
  - `Theme.swift`: colores.
- `.github/workflows/build-ipa.yml`: GitHub Actions compila en una Mac, arma `ComicUnlimited.ipa` sin firmar y lo publica como Release.

## Plan de versiones

- 0.13: manitos (👎 / 👍 / 👍👍) además de estrellas + importar archivos a la Biblioteca.
- 0.14: leer tus archivos en el lector (zoom, guarda la página, aparecen en Seguir leyendo) + nombre y ficha desde Comic Vine.
- 0.15: Biblioteca por grupos (carpetas). Botones arriba: Todos · Series · Estado. Todos con buscador y orden (Recientes · A–Z · Más nuevos · Más viejos, por fecha de publicación de Comic Vine). Series: carpeta por serie con todos los números en orden; los que no tenés, en gris (se apaga en Perfil → Configuración). "Tenés X de Y". Estado: Sin empezar / Leyendo / Leídos. Cambiar nombre. Carpeta "Sin ficha de Comic Vine".
- 0.16: Arcos y Editoriales. Al unir con Comic Vine se guardan editorial, arcos y fecha de publicación (los ya unidos se completan de a poco). Carpeta por arco (por fecha de publicación) con los números que te faltan en gris (misma configuración) y avance; carpeta por editorial.
- 0.17: imágenes de personajes y arcos en la ficha (tocar un arco abre sus números) + traducción automática (Perfil → Configuración: prender/apagar e idioma).
- 0.18: Inicio sin cómics de prueba. "De qué se trata": resumen corto de Comic Vine + solo la parte de la historia (sin listas de personajes, arcos relacionados, ediciones ni tablas).
- 0.19: Fuentes: agregar catálogos con un link JSON (nombre, versión, autor, licencia, lista de cómics), ver sus cómics y descargarlos a la Biblioteca.
- 0.20: manitos al costado de las estrellas (misma fila; si no entran, bajan solas) + "Mi página WordPress" (Biblioteca → Fuentes): se configura UNA página propia, se ven sus publicaciones y se descargan sus archivos (links directos, Pixeldrain con su link oficial, Google Drive y Dropbox; los demás links se abren en Safari). No se saltean logins ni protecciones de ningún servicio.
- 0.21: botón en la ficha de cada cómic real: "Leer" + "Ver en la Biblioteca" si ya lo tenés; "Descargar" si no (busca serie + número en tus fuentes: catálogos JSON y tu página WordPress). Los números en gris dicen "Descargar".
- 0.22: paquetes: un .zip o .rar que adentro tiene cómics enteros (.cbz, .cbr, .zip, .rar, PDF, también en carpetas) se importa como varios cómics separados (al importar y al descargar de fuentes). Avisa cuántos se agregaron.
- 0.22.3: mejor unión con Comic Vine: los cómics de un paquete usan el año del paquete si su archivo no lo dice; no se une a un número de otra época (más de 2 años de diferencia); "34 Fantastic Four 519" prueba también sin el número de orden del principio. Sin repetidos: si importás o descargás un archivo con el mismo nombre y la misma cantidad de páginas que uno que ya tenés, no se agrega de nuevo (avisa cuáles). También es repetido si queda unido a la misma ficha de Comic Vine que otro archivo: al importar se busca la ficha antes de agregarlo, y al elegir la ficha a mano avisa y ofrece borrar el repetido. "Revisar fichas de Comic Vine" (Biblioteca): las fichas que eligió la app sola, con tu portada al lado de la de Comic Vine, "Es correcta" / "Cambiar" / "Todas están bien". En la ficha de un número que no tenés: "¿Ya lo tenés? Elegí el archivo" (sugiere los parecidos). Perfil → Configuración → "Buscar la ficha de Comic Vine al importar" (prendido de entrada): si se apaga, los archivos se agregan sin ficha (los repetidos por nombre se siguen evitando).
- 0.23: orden de lectura desde Metron: en la carpeta de un arco, "Orden de lectura (buscar en Metron)" muestra las listas de lectura de Metron (con su fuente: CBRO, CMRO, Comic Book Herald…); la elegida se guarda en el iPhone y el arco se ordena por esa lista (une por el código de Comic Vine de cada número). Botón Orden de lectura / Por fecha y "Cambiar lista". Mensaje claro cuando un .cbr no se puede abrir.
- 0.23.1: "Orden de lectura (buscar listas)" busca solo, por el nombre del arco, en la colección pública de listas .cbl (y en Metron si anda). También se puede pegar el link de una lista .cbl.
- 0.24: tocar un cómic de la Biblioteca abre su ficha (la de Comic Vine si tiene; si no, una ficha simple con Leer, Elegir ficha, Cambiar nombre y Borrar); solo "Seguir leyendo" de Inicio abre directo el lector. Leer un cómic con ficha lo pasa a "Leyendo" y terminarlo a "Leído" (Perfil). "Recién salidos" muestra solo editoriales de cómics (sin manga ni ediciones de otros países) y espera a saber la editorial antes de mostrar.
- 0.25: mantener apretado un cómic de "Seguir leyendo" (Inicio): Seguir leyendo, Ver el cómic (su ficha) y Quitar de Seguir leyendo (vuelve a aparecer si lo abrís de nuevo). Próximos (con Comic Vine) también muestra solo editoriales de cómics, sin manga (espera a saber la editorial). Tocar un cómic en Próximos abre su ficha dentro de la app. TPB: cada cómic tuyo puede guardar qué números trae ("¿Es un TPB? Elegí qué números trae" en su ficha o en el menú); la app propone los números leyendo el "Collects…" de Comic Vine (y los arcos del TPB). Esos números se ven a color con "En TPB" en arcos, series y órdenes de lectura, cuentan en "Tenés X de Y", y su ficha dice "En biblioteca, dentro de: …" con "Leer el TPB". Si también tenés el suelto, se muestra el suelto y la ficha avisa "También lo tenés en: …".
- 0.26: lector, parte 1: engranaje (⚙︎) con dirección (izq → der, der → izq para manga, vertical continua), tamaño de página (entera, al ancho, al alto), tocar los bordes para pasar (se puede apagar), miniaturas abajo para saltar, pantalla siempre encendida y modo nocturno con calidez y oscuridad a gusto.
- 0.27 (planeado): lector, parte 2: doble página con el iPhone de costado; "Siguiente número" al terminar (según desde dónde lo abriste: serie, arco u orden de lectura; y en Seguir leyendo se ve de qué arco o serie venías); saltar a cada número dentro de un TPB; marcadores.
- Más adelante: Colecciones propias: crear, renombrar, borrar, agregar desde el menú (un cómic puede estar en varias), ordenar arrastrando (orden de lectura) y "Crear colección con este arco" (ordenada por fecha, después se ajusta).
- .cbr: los que por dentro son .zip se abren directo. Los que son RAR se convierten a .cbz al importarlos, con libarchive (viene dentro de iOS; Apple no la permite en el App Store, pero esta app es personal).
- LiveContainer: el selector de archivos pide una COPIA (asCopy) porque leer el original puede fallar adentro de LiveContainer.

## Cómo se prueba

No hay computadora, así que no hay simulador. Cada cambio se prueba así:

1. Se sube el cambio a GitHub (rama `main` o una rama `claude/...`).
2. GitHub Actions compila solo (tarda unos 5–10 minutos). Si falla, hay que mirar el registro en la pestaña **Actions** y arreglarlo antes de pedir que se pruebe.
3. El IPA nuevo aparece en **Releases**: https://github.com/ivorudz/comic-unlimited/releases/latest
4. Se descarga desde Safari y se abre con **LiveContainer** (que lo firma con el Apple ID gratuito).
