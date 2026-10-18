# Cómic Unlimited — reglas del proyecto

App de iPhone para leer cómics, hecha en SwiftUI. La dueña o dueño del proyecto **no sabe programar** y **no tiene computadora**: todo se hace desde el celular.

## Cómo hablar

- Explicá todo en **español simple**, sin jerga. Si usás una palabra técnica, explicala en una frase.
- Respuestas cortas: primero el resultado, después los detalles.

## Cómo trabajar

- **Cambios chicos**: un paso a la vez. Nada de rehacer media app de golpe.
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
- Sin dependencias externas (sin paquetes de terceros dentro de la app).
- `comic-unlimited.html` es el prototipo web: es la referencia de diseño, textos y comportamiento.

## Cómo está armado

- `project.yml`: receta de XcodeGen. El `.xcodeproj` **no** se guarda en el repo; se genera al compilar.
- `ComicUnlimited/`: el código de la app (iOS 17 o superior).
  - `App.swift`: arranque y las cinco pestañas.
  - `HomeView.swift`: pestaña Inicio (Seguir leyendo y Descubrir).
  - `Discover.swift`: fila "Recién salidos" de Inicio (cómics reales de la última semana).
  - `ForYou.swift`: "Para vos" en Inicio; sugerencias de series reales según tus puntajes y listas.
  - `RealLibrary.swift`: tus cómics y series reales (Quiero leer / Leyendo / Leído y puntaje), guardados en el iPhone.
  - `ProfileView.swift`: pestaña Perfil; tus listas de cómics reales y números rápidos.
  - `LibraryView.swift`: pestaña Biblioteca; importar archivos y elegir cómo verlos (Todos, Series, Estado).
  - `LibraryGroups.swift`: carpetas de la Biblioteca (serie con "Te faltan", estado), tarjeta y menú de cada cómic.
  - `LocalLibrary.swift`: guarda una copia de tus archivos, su portada, la página donde quedaste y su unión con Comic Vine.
  - `LocalReader.swift`: lector de tus archivos (páginas en segundo plano, zoom con dos dedos o doble toque).
  - `ComicVineMatch.swift`: lee el nombre del archivo (serie, número, año), busca su ficha en Comic Vine y permite elegirla a mano.
  - `CbrConverter.swift`: convierte .cbr (RAR) a .cbz con libarchive; escribe .zip sin comprimir.
  - `ComicUnlimited-Bridging-Header.h`: declara las funciones de libarchive que usa Swift.
  - `ComicArchive.swift`: abre .cbz/.zip/.cbr-que-es-zip (lector de zip hecho a mano con Compression de Apple) y PDF (PDFKit).
  - `DetailView.swift`: ficha de un cómic.
  - `ReaderView.swift`: lector a pantalla completa.
  - `UpcomingView.swift`: pestaña Próximos (lanzamientos por semana).
  - `ComicVine.swift`: conexión con Comic Vine y carga de portadas.
  - `ComicVineBrowse.swift`: buscador de cómics reales, ficha de serie y ficha de número.
  - `Metron.swift`: conexión con Metron (lanzamientos de la semana).
  - `Diagnostics.swift`: "Revisar conexión" en Próximos; prueba Metron y Comic Vine y arma un texto para copiar.
  - `ReadingStore.swift`: guarda en el celular la página donde quedaste.
  - `Comic.swift`: los 6 cómics de ejemplo.
  - `Drawing.swift`: dibuja portadas y páginas.
  - `Theme.swift`: colores.
- `.github/workflows/build-ipa.yml`: GitHub Actions compila en una Mac, arma `ComicUnlimited.ipa` sin firmar y lo publica como Release.

## Plan de versiones

- 0.13: manitos (👎 / 👍 / 👍👍) además de estrellas + importar archivos a la Biblioteca.
- 0.14: leer tus archivos en el lector (zoom, guarda la página, aparecen en Seguir leyendo) + nombre y ficha desde Comic Vine.
- 0.15: Biblioteca por grupos (carpetas). Botones arriba: Todos · Series · Estado. Todos con buscador y orden (Recientes · A–Z). Series: carpeta por serie, números en orden y "Te faltan" (Tenés X de Y). Estado: Sin empezar / Leyendo / Leídos. Cambiar nombre. Carpeta "Sin ficha de Comic Vine".
- 0.16: Arcos y Editoriales. Al unir con Comic Vine se guardan editorial, arcos y fecha de publicación (los ya unidos se completan de a poco). Carpeta por arco (por fecha de publicación) con "Te faltan para completar el arco" y avance; carpeta por editorial.
- 0.17: Colecciones propias: crear, renombrar, borrar, agregar desde el menú (un cómic puede estar en varias), ordenar arrastrando (orden de lectura) y "Crear colección con este arco" (ordenada por fecha, después se ajusta).
- .cbr: los que por dentro son .zip se abren directo. Los que son RAR se convierten a .cbz al importarlos, con libarchive (viene dentro de iOS; Apple no la permite en el App Store, pero esta app es personal).
- LiveContainer: el selector de archivos pide una COPIA (asCopy) porque leer el original puede fallar adentro de LiveContainer.

## Cómo se prueba

No hay computadora, así que no hay simulador. Cada cambio se prueba así:

1. Se sube el cambio a GitHub (rama `main` o una rama `claude/...`).
2. GitHub Actions compila solo (tarda unos 5–10 minutos). Si falla, hay que mirar el registro en la pestaña **Actions** y arreglarlo antes de pedir que se pruebe.
3. El IPA nuevo aparece en **Releases**: https://github.com/ivorudz/comic-unlimited/releases/latest
4. Se descarga desde Safari y se abre con **LiveContainer** (que lo firma con el Apple ID gratuito).
