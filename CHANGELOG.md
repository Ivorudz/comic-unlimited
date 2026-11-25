# Historial de versiones

Cada versión se compila sola en GitHub y aparece en [Releases](https://github.com/ivorudz/comic-unlimited/releases).

## 0.48.2 · Botón de Marvel como "Descargar"
- "Buscar en Marvel Comics" / "Leer en Marvel Comics" tiene el mismo color, tamaño y letra que "Descargar".

## 0.48.1 · Arreglos de Marvel Comics automático
- La búsqueda automática se quedaba en "Buscando…" sin escribir nada: arrancaba antes de que la página terminara de cargar. Ahora espera a que cargue y escribe la búsqueda.
- Si en 25 segundos no encuentra nada, pasa a "buscalo a mano" (antes podía quedarse esperando para siempre).
- Inicio de sesión: si no tenés la sesión iniciada, la app toca "Sign In" sola y completa tu mail y contraseña cuando aparecen (no mientras está buscando un cómic).

## 0.48 · Marvel Comics automático
- **Cuenta de Marvel Comics** en Perfil → Configuración → Cuentas (junto a Metron y Comic Vine). La contraseña se guarda en el llavero del iPhone.
- Si la página de Marvel pide iniciar sesión, la app **completa tu mail y contraseña sola** (solo en las páginas de inicio de sesión de Marvel Comics, WEBTOON o Disney).
- La primera vez con cada cómic, la app **lo busca sola** en Marvel Comics, elige el resultado con la misma serie y número (y el volumen del año correcto), **lo guarda y abre el lector**. Si se equivocó: "No es este". Si no lo encuentra, queda el nombre copiado para buscarlo a mano.

## 0.47 · Leer Marvel Comics en la app (prueba)
- **"Leer en Marvel Comics" abre el lector oficial de Marvel Comics dentro de nuestra app**, con tu cuenta. La página solo deja leer en computadora, así que el navegador de adentro se presenta como una computadora (Mac, sin pantalla táctil). Es una prueba, para uso personal y no comercial, como autorizó el dueño.
- La primera vez: "Buscar en Marvel Comics", buscás el cómic, lo abrís y tocás "Guardar". Desde ahí el botón abre directo el lector de ese cómic.
- Mantener apretado el botón: **abrir en la app oficial de Marvel Comics** directo en ese cómic, u olvidar el link.

## 0.46.1 · Arreglo del botón de Marvel Comics
- El botón "Buscar en Marvel Comics" no aparecía en las fichas: la app nunca llegaba a averiguar si el cómic era de Marvel. Ahora aparece.

## 0.46 · Leer en Marvel Comics
- En la ficha de cada cómic de **Marvel**, botón **"Buscar en Marvel Comics"** / **"Leer en Marvel Comics"**: abre la página oficial de Marvel Comics **dentro de la app**, en versión de computadora (en el celular la página no deja leer). Entrás con tu cuenta una vez y queda guardada.
- La primera vez, la app copia el nombre del cómic para que lo pegues en el buscador de Marvel. Cuando lo abrís, aparece **"¿Es este? Guardar"**: con un toque queda guardado y la próxima vez el botón abre ese cómic directo.
- Menú (⋯): recargar, abrir en Safari, olvidar el link y cerrar sesión de Marvel. Los botones de "Abrir en la app" de la página abren la app oficial. Se puede girar el teléfono.
- Incluye la mejora de la detección de viñetas de la 0.45.1.

## 0.45.1 · Mejor detección de viñetas
- La detección de viñetas se rehízo: ahora busca **calles de cualquier color** (blancas, negras, grises, beige…), anda con **viñetas que tocan el borde de la página** y ya no corta viñetas por el pelo o las sombras oscuras.
- Probada con páginas reales: encuentra todas las viñetas en el orden correcto en las que antes fallaban.
- Las páginas ya analizadas se vuelven a analizar solas con el método nuevo.

## 0.45 · Viñetas inteligentes
- **Zoom a la viñeta**: la app busca los recuadros de cada página (en el iPhone, sin internet). Doble toque sobre una viñeta la agranda justo para que llene la pantalla; otro doble toque vuelve a la página entera. Viene prendido.
- **Viñeta por viñeta** (⚙︎ → Viñetas): tocar los bordes pasa de viñeta en viñeta, con el zoom justo; después de la última, a la página siguiente (que se ve entera primero). Arriba dice en qué viñeta estás ("2 / 5"). Funciona en manga (de derecha a izquierda).
- **Mostrar viñetas detectadas** (⚙︎ → Viñetas): dibuja un borde de tu color y el número de orden sobre cada viñeta encontrada, para ver si las encontró bien.
- En páginas de un solo dibujo, o si no encuentra los recuadros, el doble toque hace el zoom de siempre. No anda en modo vertical ni con dos páginas juntas.
- Lo encontrado se guarda (en la carpeta de caché), así cada página se analiza una sola vez.

## 0.44.1 · Lector y fichas modernos
- El lector usa **el color que elegiste** en Personalizar (barra, marcadores, candado, miniatura actual, opciones), en vez del rosa de siempre.
- Con el **Estilo moderno**, el lector también se ve moderno: botones de arriba de vidrio, y abajo las miniaturas y la barra van en una tarjeta de vidrio flotante con borde de luz; la miniatura de la página actual se agranda y brilla con tu color.
- **Al terminar un cómic** (Estilo moderno): sello de "terminado" con tu color, de fondo la tapa del cómic difuminada, "¿Qué te pareció?" en una tarjeta de vidrio y "Siguiente número" con la tapa del que sigue, degradado de tu color y brillo. También en el final del modo vertical.
- **Fichas modernas** (de un número, de una serie, de Metron y de un archivo sin ficha): arriba, la tapa grande difuminada que se funde con el fondo (como en Música); la tapa con un resplandor de tu color; en la ficha de un número, título y datos centrados y "Ver toda la serie" como botón de vidrio; Leer y Descargar con tu color y brillo, los otros botones de vidrio; autores y acciones en tarjetas de vidrio.

## 0.44 · Lector más cómodo
- **Deslizá hacia abajo para cerrar** el lector (la página baja con el dedo; si la soltás antes, vuelve). No funciona con zoom ni en modo vertical.
- **Barra para saltar**: al arrastrar la barra de abajo se ve la página en grande y su número; al soltar, vas a esa página.
- **Brillo como en Netflix**: apoyá el dedo en el rincón de abajo a la izquierda y deslizá hacia arriba o abajo; el brillo cambia en el momento y aparece una barrita con un sol mientras movés el dedo. No hace falta tocar el centro. Un toque suelto ahí sigue pasando de página. Al cerrar el lector vuelve el del iPhone (y en ⚙︎ → Pantalla está "Volver al brillo del iPhone").
- **Cuánto falta**: abajo, al lado del número de página, "~6 min", según lo rápido que leés (historial).
- **Candado de giro** (arriba): traba el lector derecho o de costado, como esté en ese momento.
- **Hora y batería** en chiquito abajo mientras leés (se apaga en ⚙︎ → Pantalla).

## 0.43.1 · Portadas al instante
- **Barra de abajo flotante**: con el Estilo moderno, las pestañas van en una cápsula de vidrio que flota sobre el contenido (como en las apps nuevas); el resaltado se desliza de una pestaña a otra, y se esconde cuando aparece el teclado. Si cambiás el estilo, la barra cambia al volver a abrir la app.
- "Seguir leyendo": la tapa difuminada de fondo ya no se sale de la tarjeta.
- **Portadas guardadas**: la app guarda una copia de cada portada en el iPhone (como Safari), así se ven al instante, también después de actualizar la app. Se borran solas a los 30 días (y si pasan de 300 MB, las más viejas). En Personalizar se ve cuánto ocupan y se pueden borrar.

## 0.43 · Comunidad y Perfil modernos
- Con el Estilo moderno, **Comunidad**, **Próximos**, el **perfil de cada amigo** y **Perfil** también tienen el fondo de colores que se mueve, tarjetas de vidrio y entrada animada; las filas y tarjetas se inclinan al apretarlas.
- Incluye lo de la 0.42.1 (barra de vidrio, sombras sin cortes y carpetas apiladas).

## 0.42.1 · Barra de vidrio y carpetas apiladas
- La **barra de pestañas de abajo es de vidrio** (se ve lo de atrás, difuminado) con el Estilo moderno.
- "Seguir leyendo" y las filas de Inicio: las sombras de las tarjetas ya no se cortan en línea recta.
- Biblioteca: cada **grupo** (serie, arco, editorial, estado, lista) muestra **hasta 3 tapas apiladas**, como varios cómics uno arriba del otro.
- Biblioteca: todas las tarjetas quedan **a la misma altura**, aunque el título ocupe un renglón o dos.

## 0.42 · Inicio y Biblioteca modernos
- La opción de Personalizar pasa a llamarse **Estilo moderno** y ahora vale para **Rutas, Inicio y Biblioteca** (prendida de entrada; apagada, todo vuelve al estilo anterior).
- **Inicio**: fondo de colores que se mueve despacio; barra de búsqueda de vidrio con borde de colores y resplandor; "Seguir leyendo" con la tapa difuminada de fondo; las filas entran una tras otra al abrir.
- **Biblioteca**: mismo fondo; botón ＋ con resplandor; Fuentes y Ver en la compu de vidrio; los botones Todos / Series / Arcos… en una barra de vidrio donde el resaltado se desliza.
- En todas: tapas con esquinas más redondas y sombra suave; las tarjetas se achican, se inclinan y vibran al apretarlas.
- Con "Reducir movimiento" del iPhone, nada se mueve.

## 0.41.1 · Adentro de cada ruta, también moderno
- Brillo nuevo en las tarjetas: un reflejo suave y difuso que pasa cada tanto, como una ola que baja de tarjeta en tarjeta, y un borde de luz arriba, como un vidrio.
- Con **Rutas modernas** prendido, la pantalla de cada ruta también es moderna: encabezado grande con el dibujo flotando, aro de avance, medallas y puntos; fondo de colores de la ruta que se mueve; "Seguí por acá" de vidrio con resplandor; botones que se inclinan al apretarlos. Apagado, todo queda como antes.

## 0.41 · Rutas modernas
- La pestaña **Rutas** pasa a ser súper simple: cada ruta es un botón grande con su propio dibujo (escudo con rayo, hélice de ADN, telaraña, ciudad de noche con luna, planeta con anillo) y el avance en un aro.
- Efectos: fondo de colores que se mueve, entrada escalonada, dibujos que flotan, un brillo que pasa, botones que se inclinan al apretarlos y vibran. Si en el iPhone tenés "Reducir movimiento", todo queda quieto.
- Arriba, tu nivel y puntos en chiquito y el botón **?** (Lo básico); abajo, "¿No sabés qué te gusta?".
- **Personalizar → Rutas modernas**: apagalo para volver a la vista anterior, con más detalle.

## 0.40 · Rutas más útiles
- **A color solo lo que tenés**: en cada ruta, las tapas de los cómics que están en tu Biblioteca (sueltos o dentro de un TPB) se ven a color; las demás, en gris. Cada tramo dice cuántos tenés.
- **Leer o Descargar** desde "Seguí por acá": si tenés el número, lo abrís directo; si no, lo busca en tus fuentes. En cada parada, los que tenés tienen botón **Leer**.
- **Ir a una era** (botón de lista arriba) y **Ir a donde estoy** (botón flotante abajo) para moverte rápido por el camino.
- Pestaña Rutas más limpia: sin el párrafo de explicación; "Lo básico" pasa al botón **?**; la tarjeta de nivel usa tu color principal; cada ruta muestra la tapa del próximo número que te toca.
- Letra que se adapta al tamaño elegido en el iPhone.

## 0.39.1 · Avance a tu gusto
- **Biblioteca más limpia**: botón **＋** al lado del título para importar; Fuentes y Ver en la compu en una sola fila de botoncitos; sin textos de más (y sin la instrucción vieja "Tocá un cómic para leerlo", que ya no era así).
- Cada cómic muestra el título, una barrita de avance sobre la tapa y tu avance como lo elegiste en Personalizar; "Sin ficha" solo en los que no tienen ficha de Comic Vine.
- Biblioteca vacía con botón **Importar cómics**; mensajes cortos al importar y en Arcos; letra que se adapta al tamaño del iPhone.
- Todas las tapas tienen el mismo tamaño: las que tienen otra forma se recortan en vez de agrandarse (antes se veían más grandes y tapaban la editorial).
- Buscador más simple: se llama "Buscar", sin "Cómics reales" ni explicaciones; cada resultado muestra solo nombre, año y editorial.
- Personalizar → **Avance en Seguir leyendo**: elegí si cada tarjeta dice "Quedan 17 páginas", "Página 5 de 22" o "23 % leído".

## 0.39 · Personalizar
- Nueva pantalla **Perfil → Configuración → Personalizar**:
  - **Color principal**: magenta, azul, verde, naranja, violeta, rojo o amarillo (botones, pestañas y detalles de toda la app).
  - **Modo**: automático (como el iPhone), claro u oscuro.
  - **Letra de los títulos**: cómic (ancha, como siempre) o clásica.
  - **Tamaño de las portadas**: chicas, medianas o grandes (filas de Inicio, "Ver todo" y grillas de la Biblioteca).
  - **Filas de Inicio**: prendé, apagá y ordená Seguir leyendo, Recién salidos, Para vos, De tus series, Series nuevas, Géneros y Editoriales.
  - "Volver a como venía".
- Incluye los cambios de la 0.38.1.

## 0.38.1 · Seguir leyendo más claro
- Los cómics terminados salen solos de "Seguir leyendo".
- Cada tarjeta dice cuántas páginas te quedan, y de qué arco, serie, lista o **ruta** venías (si venías de alguno).
- Lo que abrís desde una ruta recuerda la ruta: al terminar, "Siguiente número" sigue la ruta con el camino que elegiste.
- Barra de búsqueda más simple: solo "Buscar cómics".

## 0.38 · Inicio más limpio
- Título "Cómic Unlimited" más chico, en un renglón.
- Filas con solo su nombre (sin aclaraciones) y **Ver todo** para ver todos los cómics de la fila en grilla.
- "Seguir leyendo" muestra primero lo que estás leyendo; los terminados van al final.
- Los avisos tienen botón: **Ir a la Biblioteca**, **Ir a Configuración** o **Buscar cómics**.
- Deslizá hacia abajo para actualizar Recién salidos.
- Si una portada no carga (internet lento), la app vuelve a probar sola.
- Los textos de Inicio respetan el tamaño de letra elegido en el iPhone.

## 0.37.1 · Rutas más simples y descargas más claras
- Cada ruta se ve más limpia: arriba solo tu avance (esenciales leídos, medallas y puntos), "Seguí por acá" y el camino.
- **Camino, Cómo verlo, Punto de partida** y "Guardar en Mis listas" pasan a la **ruedita (⚙︎)** de arriba a la derecha.
- El cartel de cada era se lee bien también en modo oscuro.
- Los títulos de tu página WordPress se ven bien: "Star Wars – Rogue One" en vez de "Star Wars &#8211; Rogue One".
- Si un link de descarga devuelve una página web en vez del cómic, la app lo dice (con el nombre de esa página) y muestra **Abrir en Safari** para bajarlo desde el navegador.
- El nombre del archivo ya no repite el año ("(2026) (2026)").

## 0.37 · Pestaña Rutas
- Las **rutas de lectura** pasan a ser una pestaña principal, **Rutas**, en el lugar donde estaba Próximos.
- **Próximos** ahora está arriba de todo en **Comunidad**.

## 0.36 · Por dónde empezar
- Botón grande **"¿No sabés por dónde empezar a leer?"** abajo de todo en Comunidad.
- **Rutas de lectura** de Avengers, X-Men, Spider-Man, Batman y Liga de la Justicia, con el orden de **Comic Book Reading Orders (CBRO)** número por número, dividido en eras.
- **Tres caminos:** Esencial (solo las series principales, sus anuales y el centro de cada evento: unos 900 números por ruta), + Extras (las demás series y los cruces aparecen como opcionales) y Con todo.
- **Dos formas de verlo:** Camino (paradas con tapas en zigzag, como un juego) o Bloques (lista ordenada por eras).
- **Punto de partida a elección:** desde el principio, desde una era, desde un "★ Empezá por acá" o desde cualquier parada. "Seguí por acá" te dice qué leer después.
- **Puntos, niveles y medallas:** 10 puntos por número (20 los extras), una medalla por era completa y +300 por ruta. Los cómics que terminás en el lector suman solos; también podés marcar "Ya lo leí".
- "Guardar este camino en Mis listas" y recomendaciones sueltas por si no sabés qué te gusta.

## 0.35.1 · Arcos en tus listas
- Cada arco tiene los botones **Quiero leer / Leyendo / Leído** y tu puntaje: aparece en tus listas de Perfil con la etiqueta "Arco" y tocándolo se abre.
- Empezar a leer un cómic desde un arco pasa el arco solo a "Leyendo".

## 0.35 · Mis listas
- **Listas propias** (Biblioteca → Listas): creá listas con tu propio orden, agregá cómics desde el menú de cada cómic o desde la ficha de cualquier número (aunque no lo tengas) y ordenalos arrastrando.
- **Subir una lista .cbl** (archivo, link o buscándola en la colección CBL-ReadingLists): trae todos los números en orden; los que tenés a color y los que te faltan en gris, con "Descargar".
- **Leer en orden**: "Siguiente número" sigue la lista.

## 0.34.1 · Ver en la compu, sin esperas
- Si el navegador de la compu prueba con "https", la app corta enseguida y el navegador pasa solo a "http" (antes se quedaba esperando).
- La pantalla avisa que hay que escribir la dirección completa, con http:// adelante.

## 0.34 · Ver en la compu
- **Ver en la compu** (Biblioteca o Perfil → Configuración): el iPhone comparte tus cómics por tu Wi-Fi y la compu los lee en el navegador, con un código de 6 números. Nada se sube a internet.
- Lector en la compu: flechas o clic, una o dos páginas, entera o al ancho, pantalla completa. Guarda todo el cómic al abrirlo y la página donde quedaste vuelve al iPhone.
- **Seguir con el teléfono bloqueado** (prendido de entrada): la app reproduce un silencio mientras comparte para que iOS no la duerma. Se apaga sola tras 30 minutos sin uso.

## 0.33.1 · Ficha más clara
- En la ficha de cada número, "De qué se trata" aparece justo debajo de Leer / Descargar.
- Se quitó la aclaración "Lo busca en tus fuentes" debajo de Descargar.

## 0.33 · Géneros de todas las épocas
- Filas por **género** en Descubrir (Superhéroes, Terror, Ciencia ficción, Fantasía, Policiales, Humor…) con series de **cualquier época**, según los géneros de Metron. Se llenan solas de a poco cada vez que abrís la app.
- Las categorías ahora son parte de Descubrir, y las editoriales dicen su nombre completo ("Image Comics").
- **Cuentas de Metron y Comic Vine** y **Revisar conexión** se mudaron a Perfil → Configuración.

## 0.32.1 · Prueba de géneros
- "Revisar conexión" → **Probar géneros y temas**: muestra qué temas tiene Comic Vine (zombis, vampiros, terror…) y qué géneros tienen las series en Metron, para decidir cómo armar las filas por género.

## 0.32 · Inicio más rápido
- Inicio guarda lo último que cargó (solo datos y links, no las portadas): al abrir la app se ve enseguida y después se actualiza.
- **Categorías** abajo de "Para vos": de tus series, series nuevas (#1) y por editorial.
- Barra de búsqueda nueva y textos sin "reales".

## 0.31 · Más formatos, ajustes por serie e historial
- Importa también **.cb7 (7-Zip) y .cbt (TAR)**, y paquetes .7z o .tar con cómics adentro. Se convierten a .cbz solos.
- **Ajustes por serie:** en el lector (⚙︎), "Recordar para esta serie" guarda la dirección y el tamaño de página de esa serie.
- **Manga de derecha a izquierda automático** cuando la editorial es de manga (se puede apagar).
- **Historial de lectura** en Perfil: cuándo leíste cada cómic, qué páginas y cuánto tiempo, con el resumen de los últimos 7 días.

## 0.30 · Perfiles
- Tu perfil en la comunidad: emoji o inicial, nombre, bio y "Compartir mis listas con mis amigos".
- Perfil de cada amigo: leídos, comentarios, puntajes y sus listas.
- Aviso para actualizar la base de datos sin borrar nada.

## 0.29 · Comunidad con amigos
- Base de datos propia y gratuita (Supabase), creada desde Safari con un texto que trae la app.
- Cuenta con mail y @usuario, amigos que se agregan los dos y código de invitación.
- "Tus amigos comentaron" y "Lo que dicen tus amigos" en cada ficha.
- Portadas que faltaban en comentarios y listas.

## 0.28 · Comentarios
- Al terminar un cómic: "¿Qué te pareció?" con estrellas, manitos y comentario.
- "Tu comentario" en cada ficha y "Mis comentarios" en Perfil y Comunidad.
- Metron: marcar como leído con tus estrellas y ver el promedio de su comunidad.
- **0.28.1:** "Siguiente número" abre bien el próximo cómic, el terminado sale de "Seguir leyendo" y "Volver a leer" en los terminados.

## 0.27 · Lector, parte 2
- "Siguiente número" al terminar, según el arco o la serie desde donde lo abriste.
- Marcadores, saltar a cada número dentro de un TPB y recortar bordes blancos (opcional).
- Próximos: ficha con datos de Metron cuando Comic Vine todavía no tiene el número.

## 0.26 · Lector, parte 1
- Dirección (izquierda a derecha, manga o vertical), tamaño de página, miniaturas, tocar bordes, pantalla encendida y modo nocturno.
- **0.26.1:** girar el teléfono para ver dos páginas juntas.
- **0.26.2:** zoom en vertical donde ponés los dedos, estrellas y manitos a la vez, y "Revisar conexión" más completa.

## 0.25 · TPB y Próximos
- TPB: qué números trae cada tomo; esos números se ven "En TPB" en arcos, series y órdenes de lectura.
- Próximos abre la ficha dentro de la app y no muestra manga.
- Menú en "Seguir leyendo": ver el cómic o quitarlo de la fila.

## 0.24 · Fichas al tocar
- Tocar un cómic abre su ficha; ficha simple para los que no tienen ficha de Comic Vine.
- Leer un cómic lo pasa solo a "Leyendo" y terminarlo, a "Leído".
- "Recién salidos" sin manga ni ediciones de otros países.

## 0.23 · Órdenes de lectura
- Orden de lectura de cada arco desde Metron y, en la **0.23.1**, búsqueda automática en la colección de listas .cbl.
- Mensaje claro cuando un .cbr no se puede abrir.

## 0.22 · Paquetes y fichas sin errores
- Paquetes .zip y .rar con muchos cómics adentro.
- **0.22.3:** mejor unión con Comic Vine, sin repetidos, "Revisar fichas" y "¿Ya lo tenés? Elegí el archivo".

## 0.21 · Descargar desde la ficha
- Botón "En biblioteca" / "Descargar" en cada cómic real; los números en gris dicen "Descargar".

## 0.20 · Tu página de WordPress
- Ver tus publicaciones y bajar sus archivos. Manitos al costado de las estrellas.

## 0.19 · Fuentes
- Catálogos que se agregan con un link JSON, con descarga a la Biblioteca.

## 0.18 · Inicio
- Inicio sin cómics de prueba; "De qué se trata" con el resumen y solo la historia.

## 0.17 · Personajes y traducción
- Personajes y arcos con imagen en la ficha; traducción automática de los textos.

## 0.16 · Arcos y editoriales
- Carpeta por arco, con los números que faltan en gris, y carpeta por editorial.

## 0.15 · Biblioteca en carpetas
- Todos, Series y Estado, con buscador y orden; "Tenés X de Y".

## 0.14 · Leer tus archivos
- Lector con zoom que guarda la página; nombre y ficha desde Comic Vine; .cbr en RAR.

## 0.13 · Importar
- Importar archivos a la Biblioteca y puntaje con manitos además de estrellas.

## 0.1 a 0.12 · La base
- Cinco pestañas, lector, Próximos con Comic Vine y Metron, buscador de cómics reales, listas y "Para vos".
