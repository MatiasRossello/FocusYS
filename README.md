# FocusYS — Focus Your Self

App iOS personal que reúne **Instagram**, **YouTube** y **X** en un solo lugar y filtra sus experiencias de video corto e infinito. Swift + SwiftUI + WebKit, sin dependencias externas, servidores ni analytics.

## Estructura

```
FocusYS/
├── FocusYSApp.swift            Punto de entrada
├── Platform/Platform.swift     Datos de cada plataforma (URL inicial, dominios, store persistente)
├── Blocking/BlockStore.swift   Bloqueos por tiempo (guardados en el dispositivo)
├── Screens/
│   ├── RootView.swift          Portada ↔ plataforma, transiciones, Reduce Motion
│   ├── HomeView.swift          Portada: "Choose a platform" + 3 filas, estado de bloqueo
│   ├── BlocksView.swift        Hoja "Blocks": nuevo bloqueo, activos y programados
│   └── PlatformScreen.swift    Pantalla completa, botón Home flotante, error, aviso "… blocked"
├── Web/
│   ├── WebSession.swift        Un WKWebView por plataforma + filtro nativo
│   ├── WebSessionStore.swift   Crea la sesión al elegir la plataforma y la mantiene en memoria
│   └── WebViewContainer.swift  Reutiliza el mismo WKWebView (sin recargas ni parpadeo)
├── Filters/                    Capa nativa: reglas de URL por plataforma
│   ├── PlatformRules.swift
│   ├── InstagramRules.swift
│   ├── YouTubeRules.swift
│   └── XRules.swift
└── Scripts/                    Capa web: JS local por plataforma
    ├── focusys-core.js         Núcleo compartido (toques, MutationObserver agrupado, CSS)
    ├── instagram-filter.js
    ├── youtube-filter.js
    └── x-filter.js
```

## Bloquear una red por un tiempo

Para casos como "mañana no quiero usar X":

- **Desde la portada:** mantené presionada una fila y elegí **1 hour**, **Rest of today**, **Tomorrow** o **Custom…**.
- **Desde el reloj de arena** (arriba a la derecha): elegís la red y el período. **Custom** permite un rango con fecha y hora de inicio y fin.

Comportamiento:

- **Bloqueo activo:** la fila aparece atenuada con un candado y el texto "Blocked until …", y la red no se abre. Si la estás usando cuando empieza el bloqueo, FocusYS pausa el video, vuelve sola a la portada y te avisa.
- **Compromiso:** un bloqueo que ya empezó no se puede desactivar hasta que termine. Los programados se pueden borrar antes de que empiecen (deslizando a la izquierda en la hoja Blocks). Antes de activar un bloqueo que empieza en el momento, se pide confirmación.
- **Encadenado:** si dos bloqueos se superponen o van uno detrás del otro, la red queda bloqueada hasta el final del último.
- **Tope:** cada bloqueo dura como máximo 30 días.
- **Límite:** esto bloquea las redes dentro de FocusYS. Bloquear las apps oficiales instaladas en el iPhone requiere el permiso de Tiempo de pantalla de Apple (Family Controls), que no está disponible con un Personal Team gratuito. Para esas apps usá **Ajustes › Tiempo de pantalla**.

## Aspecto de app nativa

- Cada red ocupa toda la pantalla, sin barra de navegador. La zona de la hora toma el color de fondo de la página (o su `theme-color`), y abajo la página llega hasta el borde.
- **Volver:** deslizá desde el borde izquierdo para ir atrás dentro de la red. Si ya no hay historial, el mismo gesto vuelve a la portada de FocusYS.
- **Botón Home flotante:** un círculo de vidrio con una casita. Se puede arrastrar a cualquier altura y se acomoda al lado más cercano; la posición se recuerda. Mientras carga una página muestra un aro de progreso. Con VoiceOver incluye la acción "Go back".
- Sin zoom con pellizco ni doble toque, sin vista previa de enlaces al mantener presionado, sin selección de texto fuera de los campos para escribir, sin el resaltado gris al tocar, y sin enlaces a "descargar la app" (App Store, `intent:`).

## Cómo filtra

1. **Navegación nativa** (`WKNavigationDelegate`): corta en el frame principal las URL bloqueadas, incluidas las de ventanas nuevas (`target=_blank`, `window.open`). Compara el host por etiquetas completas (`notinstagram.com` ≠ `instagram.com`) y la ruta por segmentos (`/@shortsguy` no se bloquea; `/@canal/shorts` sí).
   - Además observa `webView.url` (KVO) para detectar cambios de ruta sin recarga (`pushState`). Si la ruta resulta bloqueada, vuelve atrás; si no hay historial permitido, va a la página inicial. Hay un límite de 3 bloqueos en 3 s, así que no puede entrar en bucle.
   - Los deep links a las apps nativas (`instagram://`, `x-safari-https://`…) se cancelan. Los enlaces que tocás hacia otros sitios se abren en Safari, y las redirecciones del login se permiten.
2. **Interfaz web** (JS local): corre sólo en el documento principal, en un mundo JS aislado (`WKContentWorld.defaultClient`), así la página no puede ver ni falsificar los mensajes. Además, se desactiva por sí solo fuera del dominio de la plataforma.
   - Intercepta toques sobre enlaces bloqueados antes que el sitio.
   - Oculta pestañas y estantes con CSS desde el primer render y con un `MutationObserver` que procesa sólo los nodos agregados, en lotes de 150 ms.
   - Usa rutas (`href`) y nombres de componentes semánticos (`ytm-reel-shelf-renderer`…), nunca clases generadas ni textos en inglés.
   - No actúa si hay un campo de contraseña o de código, ni en rutas de login (`/accounts/`, `/i/flow/`…).

| Plataforma | Bloquea | Conserva |
|---|---|---|
| Instagram | `/reels/`, `/reel/<id>`, `/<usuario>/reels/`, `/<usuario>/reel/<id>`. Pestaña Reels oculta, miniaturas de Reels atenuadas fuera de DMs. En DMs el Reel compartido queda visible y sólo se bloquea al tocarlo. | DMs, perfiles, `/p/` |
| YouTube | `/shorts`, `/shorts/<id>`, `/@canal/shorts`, `/channel/<id>/shorts`, `/hashtag/<tag>/shorts`. Pestaña Shorts, estantes e ítems de Shorts ocultos. | Búsqueda, canales, playlists, suscripciones, `/watch` |
| X | `/<usuario>/status/<id>/video/<n>` (visor a pantalla completa, el que en la web móvil encadena videos al deslizar) | Inicio, búsqueda, perfiles, DMs, videos inline dentro de posts, `/photo/<n>` |

La sesión de cada plataforma se guarda en su propio `WKWebsiteDataStore` persistente. FocusYS no lee ni exporta contraseñas, cookies, DMs ni otros datos de cuenta.

## Qué se probó en el simulador (iPhone 18 Pro, iOS 27.2)

- ✅ Compila sin advertencias (Debug simulador y Release `generic/platform=iOS`).
- ✅ Reglas de URL: 34 casos, con el mismo resultado en Swift y en JS (incluidos falsos positivos como `/reelsfan/`, `/@shortsguy` y `?search_query=shorts`).
- ✅ Los tres accesos abren su sitio dentro de la app y la pantalla aparece al instante con indicador de carga.
- ✅ Home → portada y reapertura: el log no muestra ninguna navegación nueva. La página se conserva sin recargarse ni parpadear.
- ✅ Transiciones (verificadas cuadro a cuadro en una grabación):
  - Normal: fundido de 0,28 s con desplazamiento de 16 pt al abrir y la inversa al volver.
  - Reduce Motion: fundido de 0,15 s sin desplazamiento.
- ✅ Instagram (sin cuenta):
  - Pestaña Reels oculta.
  - `/reel/<id>` abierto con historial: se cancela, se conserva la página y aparece **Reel blocked**.
  - `/reels/` abierto sin historial: lleva a la página inicial una sola vez, sin bucle.
- ✅ YouTube (sin cuenta):
  - Pestaña Shorts oculta.
  - En una búsqueda real se ocultaron los estantes `grid-shelf-view-model` y los ítems `ytm-shorts-lockup-view-model`, y los videos normales siguen visibles.
  - `/shorts/<id>` sin historial lleva al inicio, y `/@YouTube/shorts` queda bloqueado.
  - `/watch` reproduce normalmente.
- ✅ X (sin cuenta): `/status/<id>/video/1` bloqueado con **Immersive video blocked**.
- ✅ Modo oscuro, Dynamic Type hasta AX5 (las filas pasan a disposición vertical) y contraste del acento: ≈5,6:1 en claro y ≈8,5:1 en oscuro.
- ✅ Modo pantalla completa: color de la zona de la hora tomado del sitio, `viewport` con zoom bloqueado (`user-scalable=no`) en YouTube e Instagram, e inicio de YouTube con feed visible y Shorts ocultos.
- ✅ Bloqueos: lógica probada con un ejecutable de pruebas (encadenado, no se puede borrar uno activo, validación, persistencia, presets "Tomorrow" y "Rest of today").
- ✅ Bloqueos en el simulador: una red bloqueada no se abre, un bloqueo programado aparece en su fila, y si un bloqueo empieza con la red abierta se vuelve a la portada con el aviso.
- ⚠️ El gesto desde el borde y el arrastre del botón Home no se pudieron probar en el simulador (sin herramienta de toques); quedan en la lista para el iPhone.
- ⚠️ VoiceOver no se ejecutó en el simulador. Las etiquetas, pistas, encabezados y anuncios del aviso están en el código.

## Requiere sesión real (no comprobable sin cuenta)

- **Instagram:** el feed, Explorar y los perfiles logueados, y sobre todo los **Reels compartidos en DMs**. Si Instagram abre ese Reel como superposición sin cambiar la URL ni usar un enlace `/reel/`, el filtro no lo puede identificar.
- **YouTube:** el login con Google. Google a veces rechaza `WKWebView` con el mensaje "This browser or app may not be secure"; la app envía un User-Agent tipo Safari para reducirlo. Si falla, YouTube sigue funcionando sin sesión.
- **X:** casi todo exige login. La web de X no expone una marca semántica fiable que distinga "video inline" de "visor inmersivo" salvo la ruta `/video/<n>`. Por eso se bloquea esa ruta y la reproducción inline queda intacta. Si en tu cuenta tocar un video siempre abre esa ruta, vas a ver el aviso en lugar del visor, pero el video sigue reproduciéndose dentro del post.

## Lista para probar en tu iPhone

1. [ ] Abrir **Instagram** e iniciar sesión (incluida la verificación en dos pasos si la pide).
2. [ ] Abrir **YouTube** e iniciar sesión con Google.
3. [ ] Abrir **X** e iniciar sesión.
4. [ ] Cerrar la app por completo (deslizar en el selector de apps), volver a abrirla y confirmar que las tres siguen con sesión.
5. [ ] Instagram: confirmar que no está la pestaña Reels, y que tocar un Reel en Inicio, Explorar o un perfil muestra **Reel blocked** sin salir de la página.
6. [ ] Instagram: abrir **DMs**, leer una conversación y tocar un Reel que te hayan mandado. El mensaje tiene que seguir visible y el reproductor no tiene que abrirse.
7. [ ] Instagram: abrir un enlace directo a un Reel (por ejemplo, pegado en la barra de búsqueda o tocado desde un DM).
8. [ ] YouTube: buscar algo y confirmar que no aparecen estantes de Shorts. Abrir un video normal, reproducirlo y ver que **Back** vuelve a los resultados.
9. [ ] YouTube: abrir tus **Suscripciones** y un **canal**, y confirmar que su pestaña Shorts no aparece o queda bloqueada.
10. [ ] X: reproducir un video dentro de un post del timeline, y tocar el video o "expandir" para ver si aparece **Immersive video blocked**.
11. [ ] En cada plataforma: el botón **Home** flotante vuelve a la portada y, al reabrirla, la página sigue donde estaba. Arrastrá el botón a otra posición y comprobá que se queda ahí.
    - Deslizar desde el borde izquierdo va atrás y, al llegar al principio, vuelve a la portada.
    - El pellizco no hace zoom.
12. [ ] Mantener presionada la fila de **X** › **1 hour** › confirmar. Comprobar que X no abre y que en la hoja Blocks no se puede borrar ese bloqueo.
13. [ ] Programar un bloqueo **Tomorrow** para una red y borrarlo deslizando a la izquierda.
14. [ ] Activar Ajustes › Accesibilidad › Movimiento › **Reducir movimiento** y comprobar que las transiciones pasan a ser un fundido simple.

Si algo de la lista falla, anotá la URL que muestra la plataforma; con eso se ajusta la regla.

## Instalar en tu iPhone con Personal Team (gratis)

1. Conectá el iPhone por cable (o en la misma red Wi-Fi si ya lo emparejaste) y desbloquealo. Si pregunta **¿Confiar en esta computadora?**, tocá **Confiar**.
2. En el iPhone activá **Modo de desarrollador**: Ajustes › Privacidad y seguridad › Modo de desarrollador. Se reinicia; después confirmá **Activar**.
3. En Xcode abrí `FocusYS.xcodeproj` y, en el navegador de la izquierda, seleccioná el proyecto **FocusYS**, el target **FocusYS** y la pestaña **Signing & Capabilities**.
4. Dejá marcado **Automatically manage signing**. En **Team** elegí **"Tu nombre (Personal Team)"**. Si no aparece, usá **Add an Account…** e iniciá sesión con tu Apple ID.
5. Si Xcode dice que el **Bundle Identifier** no está disponible, cambialo por uno único, por ejemplo `com.tunombre.FocusYS`.
6. En la barra superior de Xcode, en el selector de destino (junto a "FocusYS"), elegí **tu iPhone** en lugar de un simulador.
7. Presioná **Run** (▶ o ⌘R).
8. La primera vez, en el iPhone: Ajustes › General › **VPN y gestión de dispositivos** › tu Apple ID › **Confiar**. Después volvé a presionar Run o abrí la app.

Con Personal Team la instalación dura **7 días**; después hay que volver a pulsar Run desde Xcode.

> **Versión de iOS:** el proyecto tiene como mínimo **iOS 27.2** (el valor por defecto de tu Xcode). Si tu iPhone tiene una versión anterior, bajá **Minimum Deployments** en la pestaña *General* del target. El código funciona desde **iOS 17**.

## Hooks de prueba (sólo Debug)

En Xcode › Scheme › Run › Arguments, o con `simctl launch`:

- `-FocusYSOpen instagram|youtube|x` abre la plataforma al iniciar.
- `-FocusYSURL <url>` y `-FocusYSURLDelay <s>` cargan una URL, que pasa por el filtro.
- `-FocusYSHomeAfter <s>` y `-FocusYSReopenAfter <s>` vuelven a Home y reabren la plataforma.
- `-FocusYSResetBlocks 1` borra todos los bloqueos al iniciar.
- `-FocusYSDebugBlock "x:<inicio s>:<duración s>"` agrega un bloqueo relativo al arranque.
- `-FocusYSShowBlocks 1` abre la hoja Blocks.

En Debug, la consola muestra `[FocusYS] nav/url/filter …` con cada navegación y lo que ocultó el filtro. Nada de esto existe en Release.
