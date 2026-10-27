# Cómic Unlimited

[![Última versión](https://img.shields.io/github/v/release/ivorudz/comic-unlimited?label=versi%C3%B3n&color=d1006c)](https://github.com/ivorudz/comic-unlimited/releases/latest)
[![Compilación](https://github.com/ivorudz/comic-unlimited/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/ivorudz/comic-unlimited/actions/workflows/build-ipa.yml)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-17191e)
![SwiftUI](https://img.shields.io/badge/SwiftUI-sin%20dependencias-ff4fa3)

**Una app de iPhone para leer tus cómics, ordenarlos como en una comiquería, saber qué sale cada semana y comentarlos con tus amigos.**

Cómic Unlimited lee tus archivos (.cbz, .cbr, .cb7, .cbt, .zip y PDF), los une solos a su ficha de [Comic Vine](https://comicvine.gamespot.com), los acomoda por serie, arco y editorial, te muestra los números que te faltan y te dice en qué orden leerlos. Además trae los lanzamientos de la semana desde [Metron](https://metron.cloud) y una comunidad privada para compartir puntajes y comentarios.

Es una app **personal y sin fines comerciales**, escrita en SwiftUI y **sin programas de terceros adentro**. Se hizo y se prueba entero desde un iPhone: GitHub la compila sola y se instala con LiveContainer.

---

## Qué hace

### 📚 Tu biblioteca
- Importa **.cbz, .zip, .cbr, .cb7, .cbt y PDF** desde la app Archivos. Los RAR, 7-Zip y TAR se convierten solos.
- **Paquetes:** un .zip, .rar, .7z o .tar con muchos cómics adentro se separa en cómics individuales.
- Carpetas por **serie, arco, editorial y estado** (sin empezar, leyendo, leídos), con buscador y orden por fecha de publicación.
- Los **números que te faltan aparecen en gris**, con "Tenés X de Y" y un botón para buscarlos en tus fuentes.
- **TPB (tomos recopilatorios):** cada tomo sabe qué números trae, y esos números cuentan como tuyos en arcos, series y órdenes de lectura.
- **Sin repetidos**, ni por nombre de archivo ni por ficha.

- **Ver en la compu:** leé tus cómics en el navegador de la compu, por tu Wi-Fi, incluso con el iPhone bloqueado.

### 🔎 Fichas de Comic Vine
- Cada archivo se une **solo** con su ficha a partir del nombre (serie, número y año), y se puede revisar o corregir a mano.
- La ficha muestra de qué se trata (con **traducción automática**), autores, personajes y arcos con imagen.
- **"Leer" / "Ver en la Biblioteca"** si ya lo tenés; **"Descargar"** si no.

### 📖 Lector
- Dirección **izquierda a derecha, derecha a izquierda (manga) o vertical continua**.
- Página entera, al ancho o al alto; **dos páginas juntas** con el teléfono de costado.
- Zoom con dos dedos o doble toque, miniaturas para saltar, tocar los bordes para pasar.
- **Ajustes por serie** (dirección y tamaño) y **manga de derecha a izquierda automático**.
- **Modo nocturno** (calidez y oscuridad a gusto), pantalla siempre encendida y recortar bordes blancos (opcional).
- **Marcadores**, saltar a cada número dentro de un TPB y **"Siguiente número"** según el arco o la serie desde donde lo abriste.
- Al terminar: **"¿Qué te pareció?"**, con estrellas, manitos y comentario.

### 🗺️ Arcos y órdenes de lectura
- Cada arco con todos sus números, los tuyos a color y los que faltan en gris.
- **Orden de lectura automático:** busca el arco en la colección pública de listas [CBL-ReadingLists](https://github.com/DieselTech/CBL-ReadingLists) (órdenes de Comic Book Reading Orders, Complete Marvel Reading Orders, League of Comic Geeks y otros) o en Metron.

### 🗓️ Próximos
- Lo que sale **cada semana o cada mes**, desde Metron (o Comic Vine si Metron no responde), sin manga ni ediciones de otros países.
- Tocar un cómic abre su ficha, aunque Comic Vine todavía no lo tenga.
- "Revisar conexión" para ver qué responde cada servicio.

### 💬 Perfil y comunidad
- Listas **Quiero leer / Leyendo / Leído**, que se actualizan solas mientras leés, y puntaje con **estrellas y manitos**.
- "Para vos": sugerencias según tus puntajes y tus listas.
- **Descubrir por género** (superhéroes, terror, ciencia ficción…) con series de todas las épocas, y por editorial.
- **Historial de lectura:** cuándo leíste cada cómic, qué páginas y cuánto tiempo.
- **Metron:** opción para marcar como leído en tu colección, con tus estrellas, y ver el promedio de su comunidad.
- **Comunidad privada con amigos** en una base de datos propia y gratuita ([Supabase](https://supabase.com)): perfiles, amigos que se agregan los dos, y comentarios y puntajes en cada ficha.

### 🔗 Fuentes
- **Catálogos** que agregás con el link de un archivo JSON (formato en [FUENTES.md](FUENTES.md)), con descarga directa a la Biblioteca.
- **Tu página de WordPress:** ves tus publicaciones y bajás sus archivos (links directos, Pixeldrain, Google Drive y Dropbox).

---

## Instalarla

1. En el iPhone, abrí con Safari la [última versión](https://github.com/ivorudz/comic-unlimited/releases/latest) y descargá **ComicUnlimited.ipa**.
2. Abrilo con **[LiveContainer](https://github.com/khanhduytran0/LiveContainer)**, que lo firma con un Apple ID gratuito.
3. Para las fichas y Próximos, cargá en la app tu clave gratuita de [Comic Vine](https://comicvine.gamespot.com/api/) y, si querés, tu cuenta de [Metron](https://metron.cloud).

## Cómo se compila

No hace falta una computadora: cada cambio que se sube a GitHub se compila solo.

- [`project.yml`](project.yml) es la receta de [XcodeGen](https://github.com/yonaskolb/XcodeGen); el proyecto de Xcode no se guarda, se genera al compilar.
- [GitHub Actions](.github/workflows/build-ipa.yml) compila en una Mac (`xcodebuild`, sin firmar), arma el `.ipa` y lo publica como Release.
- Código en [`ComicUnlimited/`](ComicUnlimited): SwiftUI, iOS 17 o superior, unos 45 archivos. El mapa de cada archivo está en [CLAUDE.md](CLAUDE.md).

## Datos, derechos y privacidad

- La app **no trae cómics de nadie**. Los cómics de ejemplo son inventados y sus dibujos se generan con código. Lo que leés son tus propios archivos.
- Datos y portadas de cómics reales: **solo desde Comic Vine y Metron**. Las portadas se cargan al verlas y nunca se guardan en la app ni en este repositorio; pertenecen a sus editoriales.
- **Ninguna clave ni contraseña va en el código.** La clave de Comic Vine, la cuenta de Metron y los datos de la comunidad se escriben en la app y quedan guardados solo en el iPhone.
- La comunidad usa una base de datos que crea cada dueño. Sus reglas hacen que cada persona solo pueda cambiar lo suyo y que los comentarios los vean solo los amigos.
- Las fuentes solo leen listas y bajan links directos. La app no ejecuta programas de terceros ni saltea logins ni protecciones de ningún servicio.

## Más

- [Historial de versiones](CHANGELOG.md)
- [Roadmap: lo que viene](ROADMAP.md)
- [Formato de las fuentes](FUENTES.md)

## Gracias

- [Comic Vine](https://comicvine.gamespot.com) y [Metron](https://metron.cloud) por sus datos abiertos.
- [CBL-ReadingLists](https://github.com/DieselTech/CBL-ReadingLists) por los órdenes de lectura.
- [Supabase](https://supabase.com) por la base de datos gratuita.
- [LiveContainer](https://github.com/khanhduytran0/LiveContainer) por hacer posible instalarla sin computadora.
