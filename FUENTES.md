# Fuentes de cómics

Una **fuente** es un catálogo que agregás en la app (Biblioteca → **Fuentes** → **Agregar fuente**) pegando el link de un archivo JSON.
La app lee la lista, te muestra los cómics y, si tocás **Descargar**, baja el archivo y lo guarda en tu Biblioteca
(se une solo con Comic Vine y se lee sin internet).

**Importante:** usá solo fuentes que tengan permiso para compartir esos cómics (por ejemplo, de dominio público o con licencia libre).
La app no trae fuentes incluidas y no ejecuta programas de las fuentes: solo lee la lista y descarga los archivos.

## Formato

```json
{
  "name": "mi-catalogo",
  "version": "1.0.0",
  "description": "Cómics de dominio público de los años 40",
  "license": "Public Domain",
  "author": "Nombre <email@ejemplo.com>",
  "repository": { "type": "git", "url": "https://github.com/usuario/mi-catalogo" },
  "homepage": "https://ejemplo.com",
  "comics": [
    {
      "title": "Captain Ejemplo #1",
      "series": "Captain Ejemplo",
      "number": "1",
      "year": 1944,
      "publisher": "Editorial Ejemplo",
      "cover": "https://ejemplo.com/portadas/1.jpg",
      "download": "https://ejemplo.com/archivos/1.cbz",
      "format": "cbz",
      "size": 25000000
    }
  ]
}
```

Hay un ejemplo completo en [`fuentes/ejemplo.json`](fuentes/ejemplo.json).

### Datos de la fuente

| Campo | ¿Obligatorio? | Qué es |
|---|---|---|
| `name` | Sí | Nombre de la fuente. |
| `comics` | Sí | Lista de cómics (puede estar vacía). |
| `version` | No | Versión (por ejemplo `1.0.0`). Si cambia, la app avisa "versión nueva". |
| `description` | No | De qué se trata. |
| `license` | No | Licencia de los cómics (por ejemplo `Public Domain` o `CC BY 4.0`). |
| `author` | No | Texto (`"Nombre <email>"`) o `{ "name": "...", "email": "..." }`. |
| `repository` | No | Texto con un link, o `{ "type": "git", "url": "..." }`. |
| `homepage` | No | Página web de la fuente. |

### Datos de cada cómic

| Campo | ¿Obligatorio? | Qué es |
|---|---|---|
| `title` | Sí | Título que se muestra. |
| `download` | Sí | Link **directo** al archivo (`.cbz`, `.zip`, `.cbr` o `.pdf`). Tiene que empezar con `https://`. |
| `series` | No | Nombre de la serie. Junto con `number` y `year` ayuda a encontrar la ficha en Comic Vine. |
| `number` | No | Número dentro de la serie (texto o número). |
| `year` | No | Año (texto o número). |
| `publisher` | No | Editorial. |
| `cover` | No | Link a la portada (se carga al momento, no se guarda). |
| `format` | No | `cbz`, `zip`, `cbr` o `pdf`. Si no está, se usa la extensión del link. |
| `size` | No | Tamaño del archivo en bytes (solo para mostrarlo). |

Los cómics a los que les falte `title` o `download` se saltean.

## Dónde subir el JSON

Cualquier lugar que dé un link `https://` directo al archivo sirve, por ejemplo un repositorio de GitHub
(usando el link "Raw" del archivo) o tu propio servidor.
