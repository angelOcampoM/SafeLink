# Plan: consumo 100 % real (front y backend)

Fecha del diagnóstico: 2026-11-24. Rama base: `develop` (`2d46f5b`).

Objetivo: que con `--dart-define=API_URL=...` **ninguna pantalla muestre ni produzca datos simulados**. Este documento es un **banco de tareas**: cada tarea es pequeña, se puede tomar por separado, tiene sus archivos, su criterio de aceptación y sus pruebas, y equivale a **un commit**.

> **Avance (2026-11-26).** Hechas: CR-F01, CR-F02, CR-F03 y CR-F05 (D54); CR-F04, CR-B01 y CR-B04, más el tiempo estimado de llegada en la navegación del guardia (G-06, D55); CR-D01. Pendientes: la verificación en el teléfono (sección 6), CR-D02, y las que dependen de una decisión (CR-B02, CR-F06, CR-F07, CR-B03, CR-F08). También sigue abierta la privacidad de la ubicación del guardia fuera de turno (D54).
>
> **Pendientes para cerrar el rol del guardia:** verificación en el teléfono (sección 6) · CR-D02 (casillas de G-01…G-07) · DA-5 / CR-B02 (turno de 24 h en la semilla) · DA-2 / CR-F06 (mapa real en G-04 y G-06; hoy es un dibujo) · DA-3 / CR-F07 + CR-B03 (push de G-02; hoy solo con la app abierta) · privacidad de la ubicación fuera de turno (D54).

---

## 1. De dónde sale este plan

Se probó la app en un teléfono físico (build debug, `adb reverse`) contra la API local. Resultado:

| Qué | Estado |
|---|---|
| Login, cambio de rol, cierre de sesión | Real ✅ |
| Usuario: disparo, foto, ubicación, confirmación | Real ✅ |
| Guardia: listado por SSE, detalle, foto, aceptar, historial | Real ✅ |
| Admin: guardias, alertas, usuarios, métricas, cobertura | Real ✅ |
| Escalamiento automático (5 min sin aceptar, 15 min sin confirmar) | Real ✅ (lo hace el servidor) |
| Geocerca de llegada | Validada en el servidor ✅, **pero con una ubicación del guardia simulada** ❌ |
| Ubicación del guardia | **Simulada** ❌ |
| Botones "Simular …" y cuentas de prueba | **Visibles con la API real** ❌ |
| Mapa del guardia y del admin | **Dibujo** (`MapPlaceholder`) ❌ |
| Abrir la ruta en Google Maps | **No existe** ❌ |
| Notificación push al guardia (G-02) | **No existe en el front**; backend con `PUSH_PROVIDER=none` ❌ |

Hallazgos que explican la tabla (verificados en el código):

- **H1. El guardia nunca lee su GPS.** `NavegacionViewModel.iniciar()` toma `perfil.ultimaUbicacion` del servidor, y la única forma de moverla es `simularAcercamiento()` (avanza 60 % hacia la alerta). La llegada de la prueba se logró con ese botón: los `PUT /guard/location` seguidos y los dos `429` del log fueron sus toques. El `Ubicacion` real ya existe en el teléfono (`main.dart`) y lo usa el usuario (`SeguimientoUbicacion`), pero no se le pasa al guardia. El código ya lo marca: `TODO(G-06)` en `navegacion_view_model.dart`.
- **H2. `Configuracion.modoDemo = true` es fijo** (`lib/dominio/configuracion.dart`) y no depende de `API_URL`. Controla: cuentas de prueba en el login, "Simular acercamiento (demo)" en la navegación del guardia y "Simular doble clic" en el inicio del usuario.
- **H3. Sin ubicación del guardia fuera de la navegación**, la distancia y el orden del listado (G-03) y el tiempo estimado que ve el usuario (U-08) se calculan con una posición vieja.
- **H4. Mapas simulados**: `TODO(G-06)` en `map_placeholder.dart`, `detalle_guardia.dart` y `navegacion_guardia.dart`; `TODO(A-03)` en `cobertura_guardia_page.dart`. `url_launcher` no está en `pubspec.yaml`.
- **H5. Push**: el front no tiene `firebase_messaging` ni llama a `PUT /users/me/device-token` (`TODO(G-02)` en `listado_alertas_view_model.dart`). El backend ya tiene notificador FCM (BE-04) pero corre con `PUSH_PROVIDER=none`.
- **H6. Configuración duplicada**: geocerca, tiempos de espera e intervalo de ubicación viven en `Configuracion.porDefecto` (front) y en `backend/src/config/env.ts` (backend). Hoy coinciden; nada lo garantiza.
- **H7. Fricción para probar en local**: la semilla ubica las zonas de cobertura en puntos fijos de Morelos, así que la alerta de un teléfono real casi siempre cae fuera de todas (en la prueba quedó a 7.3 km de la zona más cercana con turno). Además, la semilla calcula los turnos relativos a la hora en que se corre, y al volver a correrla restaura la cobertura original.

---

## 2. Reglas del banco

1. **Una tarea = un commit = una rama** `feat/CR-XX-descripcion` desde `develop`. Formato del mensaje: `tipo(CR-XX): descripción en español`.
2. **Cambios en `lib/` o `test/` (front) se confirman con el equipo antes de empezar.** El banco ya dice qué archivos toca cada tarea para que esa confirmación sea rápida.
3. **No se inventan rutas, campos ni códigos.** Ninguna tarea de este banco necesita una ruta nueva; si alguna termina necesitándola, se detiene y se registra en `docs/DECISIONES.md`.
4. **Ninguna tarea depende de una decisión abierta (sección 5) salvo las marcadas con 🔒.** Las demás se pueden tomar ya.
5. Cada tarea deja verde: front `flutter analyze` + `flutter test` (incluye `test/arquitectura_test.dart`); backend `npm run typecheck && npm run lint && npm test`.
6. Dependencias nuevas solo donde la tarea lo dice, con su justificación en el resumen del commit.
7. Lo que no se puede probar sin teléfono se verifica con la lista de la sección 6 y se anota en el PR.

Leyenda: **Tamaño** S (< 2 h), M (medio día), L (1 día o más). **Riesgo**: qué puede romperse.

---

## 3. Banco de tareas

### Front (Flutter)

#### CR-F01 · Apagar el modo demo cuando hay API real
- **Por qué:** H2. Es el cambio más chico y quita casi todo lo "simulado" visible.
- **Qué:** en `Dependencias.crear` (`lib/main.dart`), si `urlApi` no está vacía, usar una `Configuracion` con `modoDemo: false`. Sin `API_URL` (memoria o nube simulada) todo queda igual.
- **Archivos:** `lib/main.dart`. Si `Configuracion` no tiene forma de copiarse con un campo cambiado, agregar `copyWith` en `lib/dominio/configuracion.dart` (sin cambiar valores por defecto).
- **Acepta cuando:** con `API_URL` no aparecen las cuentas de prueba en el login, ni "Simular acercamiento", ni "Simular doble clic". Sin `API_URL` siguen apareciendo.
- **Pruebas:** unitaria de `Dependencias.crear(usarNube: true, urlApi: 'http://x')` → `config.modoDemo == false`; y `usarNube: false` → `true`. Revisar que las pruebas de widgets existentes que esperan los botones demo sigan usando modo memoria.
- **Depende de:** nada. **Tamaño:** S. **Riesgo:** bajo; pruebas que armen `Dependencias` con URL.

#### CR-F02 · Seguimiento de ubicación del guardia en turno
- **Por qué:** H1 y H3. Es la base para que distancia, prioridad, tiempo estimado y geocerca usen la posición real.
- **Qué:** una clase `SeguimientoGuardia`, gemela de `SeguimientoUbicacion` (vive con la sesión, no con una pantalla). Mientras haya un `guard` en sesión, lee `Ubicacion.seguir()` y manda `actualizarMiUbicacion` **como máximo una vez cada `config.segundosActualizacionUbicacion`** y con **un solo envío en vuelo a la vez** (evita los `429`: el backend acepta `RATE_LIMIT_LOCATIONS_PER_WINDOW = 3` por ventana). Expone la última posición leída (`ultimaPosicion`) para que la usen las pantallas. Se detiene al cerrar sesión o cambiar de rol.
- **Archivos:** nuevo `lib/presentacion/guardia/seguimiento_guardia.dart`; `lib/main.dart` (crearlo y arrancarlo junto a `seguimiento`).
- **Acepta cuando:** con el guardia en sesión y la app abierta, el log de la API muestra `PUT /guard/location` cada ~5 s, sin `429`; al cerrar sesión se detienen.
- **Pruebas:** unitarias con `UbicacionSimulada` y un repositorio falso: respeta el intervalo aunque el sensor emita más rápido; no hay dos envíos simultáneos; un error de red no detiene el seguimiento; se detiene con logout y con rol distinto de `guard`.
- **Depende de:** nada. **Tamaño:** M. **Riesgo:** medio; batería y permisos (si no hay permiso, `seguir()` no emite y no debe romper nada, como dice D52).

#### CR-F03 · La navegación usa la ubicación real
- **Por qué:** H1. Hoy la geocerca se pasa con un botón.
- **Qué:** `NavegacionViewModel` recibe `SeguimientoGuardia` (o el `Ubicacion`) y actualiza `miUbicacion` con cada posición real; `distancia`, `metrosRestantes` y `puedeMarcarLlegada` se recalculan solos. `simularAcercamiento` queda solo cuando `modoDemo` es `true`.
- **Archivos:** `lib/presentacion/guardia/navegacion_view_model.dart`, `lib/presentacion/comun/rutas/fabrica_view_models.dart`.
- **Acepta cuando:** con la API real, el botón "Llegué" se habilita solo al estar físicamente a ≤ 50 m del punto de la alerta, y la distancia restante cambia al caminar.
- **Pruebas:** unitarias del ViewModel con un stream de posiciones: fuera → dentro de la geocerca habilita el botón; sin posición, el botón queda deshabilitado; al hacer `dispose` se cancela la suscripción.
- **Depende de:** CR-F02 (y conviene después de CR-F01). **Tamaño:** M. **Riesgo:** medio; pruebas existentes de navegación que asumen `ultimaUbicacion`.

#### CR-F04 · Abrir la ruta en Google Maps
- **Por qué:** G-06, último criterio. No requiere cuentas ni llaves.
- **Qué:** botón "Abrir en Google Maps" en la navegación que abre `https://www.google.com/maps/dir/?api=1&destination=<lat>,<lng>`. Si no se puede abrir, mensaje en español, sin romper la pantalla.
- **Archivos:** `pubspec.yaml` (**dependencia nueva `url_launcher`**: es el paquete oficial de Flutter para abrir enlaces), `android/app/src/main/AndroidManifest.xml` (bloque `<queries>` para intents `https`, que Android 11+ exige), `lib/presentacion/guardia/navegacion_page.dart`. El lanzador va detrás de una interfaz en `lib/datos/` para poder probarlo, igual que los sensores (D52).
- **Acepta cuando:** en el teléfono, el botón abre Google Maps con el destino de la alerta.
- **Pruebas:** de widget con un lanzador falso: arma la URL correcta y muestra el error si falla.
- **Depende de:** nada. **Tamaño:** S. **Riesgo:** bajo.

#### CR-F05 · Ubicación del usuario sin ráfagas
- **Por qué:** los `429` también pueden darse en `POST /alerts/:id/locations` si el sensor emite rápido.
- **Qué:** aplicar a `SeguimientoUbicacion` la misma regla que CR-F02 (intervalo mínimo y un envío en vuelo). Si CR-F02 extrae un pequeño limitador reutilizable, usarlo aquí.
- **Archivos:** `lib/presentacion/usuario/seguimiento_ubicacion.dart`.
- **Acepta cuando:** con una alerta activa, el log muestra un `POST .../locations` cada ~5 s y ningún `429`.
- **Pruebas:** unitarias equivalentes a las de CR-F02.
- **Depende de:** idealmente después de CR-F02. **Tamaño:** S. **Riesgo:** bajo.

#### CR-F06 🔒 · Mapa real en detalle, navegación y cobertura
- **Por qué:** H4 (G-04, G-06, A-03).
- **Qué:** sustituir `MapPlaceholder` por un mapa real con el **mismo tamaño** (el widget ya se diseñó para eso), con marcadores de guardia y alerta, línea entre ambos y círculo de geocerca/cobertura. En A-03, mover el centro tocando el mapa.
- **Archivos:** `pubspec.yaml` (paquete de mapas), `lib/presentacion/comun/widgets/map_placeholder.dart` o un widget nuevo, `detalle_guardia.dart`, `navegacion_guardia.dart`, `cobertura_guardia_page.dart`, configuración nativa de Android.
- **Depende de:** **DA-2**. **Tamaño:** L. **Riesgo:** alto (llaves, build nativo, pruebas de widgets con mapas).

#### CR-F07 🔒 · Notificación push al guardia (G-02)
- **Qué:** `firebase_messaging`; tras el login de un `guard`, registrar el token con `PUT /users/me/device-token` (ya existe en el backend, D42); al tocar la notificación abrir el detalle; canal de alarma en Android. El logout ya borra los tokens en el servidor.
- **Archivos:** `pubspec.yaml`, configuración nativa de Firebase (**no se sube** `google-services.json`), `lib/datos/` (cliente del token), `lib/presentacion/guardia/` (abrir detalle).
- **Depende de:** **DA-3** y de CR-B03. **Tamaño:** L. **Riesgo:** alto (cuenta externa, credenciales, pruebas solo en dispositivo).

#### CR-F08 🔒 · Ubicación del usuario con la pantalla apagada
- **Qué:** permiso de ubicación en segundo plano (D52, punto 5) para que U-07 siga transmitiendo con el teléfono bloqueado.
- **Depende de:** **DA-4**. **Tamaño:** M. **Riesgo:** medio (políticas de Android y de la tienda).

### Backend

#### CR-B01 · Comando para reiniciar la demo
- **Por qué:** H7. Hoy, para probar "desde cero", hay que borrar alertas a mano en la base.
- **Qué:** script `npm run demo:reset` que borra todas las alertas (su historial y los "ignorar" caen en cascada) y conserva cuentas, perfiles y sesiones. Opcionalmente recibe `--center <lat>,<lng>` y `--radius <m>` para mover la cobertura de los guardias de turno a donde está el teléfono de la demo. Igual que la semilla, se niega a correr si `NODE_ENV` no es `development` o `test` (D28).
- **Archivos:** `backend/scripts/demo-reset.mjs` (o `.ts`), `backend/package.json`, `backend/README.md`.
- **Acepta cuando:** después de correrlo, el admin ve 0 alertas, los usuarios siguen pudiendo entrar sin volver a iniciar sesión y, con `--center`, una alerta disparada en ese punto le llega al guardia.
- **Pruebas:** de integración contra la base de pruebas: borra alertas e historial, conserva usuarios y perfiles, se niega con `NODE_ENV=production`, valida coordenadas fuera de rango.
- **Depende de:** nada. **Tamaño:** S. **Riesgo:** bajo (es destructivo por diseño; por eso el candado de `NODE_ENV`).

#### CR-B02 🔒 · `guardia@safelink.mx` siempre de turno en la semilla
- **Por qué:** H7. En la semilla del front, `grd-1` está de turno a cualquier hora; en la del backend su turno es una ventana de 8 h relativa a cuando se corrió la semilla. Si se presenta fuera de esa ventana, el guardia no recibe nada.
- **Qué:** turno que cubra las 24 h para `grd-1` en `backend/prisma/seed.ts`, igual que en la semilla del front.
- **Depende de:** **DA-5**. **Tamaño:** S. **Riesgo:** bajo; revisar pruebas que asuman ese turno.

#### CR-B03 🔒 · Push con FCM encendido
- **Qué:** documentar y probar `PUSH_PROVIDER=fcm` con `FCM_PROJECT_ID` y `FCM_SERVICE_ACCOUNT_FILE` (ruta fuera del repo). El código ya existe desde BE-04; falta la configuración y la verificación con un teléfono.
- **Depende de:** **DA-3**. **Tamaño:** S (más la verificación). **Riesgo:** credenciales: nunca en el repo.

#### CR-B04 · Prueba de paridad de configuración front ↔ backend
- **Por qué:** H6.
- **Qué:** prueba de contrato en `backend/tests/` que lee los valores por defecto de `lib/dominio/configuracion.dart` y los compara con los de `backend/src/config/env.ts`: `radioGeocercaMetros` ↔ `GEOFENCE_METERS`, `minutosAceptacion` ↔ `ACCEPT_TIMEOUT_SECONDS`, `minutosConfirmacion` ↔ `CONFIRM_TIMEOUT_SECONDS`, `segundosActualizacionUbicacion` ↔ `LOCATION_UPDATE_SECONDS`. Falla con un mensaje que diga qué valor se desfasó.
- **Archivos:** `backend/tests/contract/` (nuevo archivo).
- **Depende de:** nada. **Tamaño:** S. **Riesgo:** bajo; leer Dart con una expresión regular es frágil, así que la prueba debe fallar de forma clara si no encuentra un valor, en lugar de pasar.

### Documentación

#### CR-D01 · Tropiezos de la prueba en teléfono
- **Qué:** agregar a `docs/CONEXION_DISPOSITIVO.md` (o a la "sección 0" que ya está en un PR pendiente; coordinar para no duplicar):
  - Si existe un contenedor `backend-api-1` viejo, responde `404` en rutas nuevas: reconstruirlo (`docker compose up -d --build api`) o detenerlo y usar `npm run dev`. Ambos usan el puerto 3000.
  - Base sin semilla → el login da `INVALID_CREDENTIALS` aunque la contraseña sea correcta.
  - `API_URL` se compila dentro del APK: cerrar y abrir la app, o un hot restart, **no** la cambia; hay que volver a correr `flutter run`.
  - La alerta de un teléfono real suele caer fuera de las zonas de la semilla: ampliar la cobertura desde el admin (o `demo:reset --center`, CR-B01). Volver a correr la semilla restaura la cobertura original.
  - `adb` vive en `%LOCALAPPDATA%\Android\Sdk\platform-tools\` si no está en el PATH.
- **Depende de:** nada (actualizar cuando entre CR-B01). **Tamaño:** S. **Riesgo:** ninguno.

#### CR-D02 · Estado de G-02, G-03, G-06 y G-07
- **Qué:** al cerrar cada tarea, actualizar las casillas de `docs/HISTORIAS_DE_USUARIO.md` y la fila correspondiente de `docs/PLAN_DE_PRUEBAS.md`. Las decisiones que se tomen en la sección 5 se registran como `D54…` en `docs/DECISIONES.md`.

---

## 4. Orden recomendado y trabajo en paralelo

```
Ola 1 (la demo queda 100 % real, sin cuentas externas)
  Front:   CR-F01 ─┐
           CR-F02 ─┼─> CR-F03 ─> CR-F05
           CR-F04 ─┘
  Backend: CR-B01   CR-B04         (en paralelo con todo el front)
  Docs:    CR-D01                  (en paralelo)

Ola 2 (requiere decisión)
  CR-B02 (DA-5)

Ola 3 (requiere cuentas externas o permisos especiales)
  CR-F06 (DA-2) · CR-F07 + CR-B03 (DA-3) · CR-F08 (DA-4)
```

- Front y backend no comparten archivos: dos personas pueden trabajar a la vez sin conflictos.
- Dentro del front, CR-F01 y CR-F04 tocan archivos distintos de CR-F02, así que también van en paralelo. CR-F01 y CR-F02 tocan `main.dart` en zonas distintas: quien entre segundo hace un rebase corto.
- **Mínimo para presentar con todo real:** CR-F01, CR-F02, CR-F03 y CR-B01 (los cuatro son S o M).

---

## 5. Decisiones abiertas

| ID | Pregunta | Opciones | Recomendación |
|---|---|---|---|
| DA-1 | ¿El modo demo se apaga solo con `API_URL`, o con una bandera propia (`--dart-define=DEMO=false`)? | Automático / bandera | **Automático** (CR-F01). Con la API real los botones "Simular" mandan datos falsos al servidor, así que no tiene sentido dejarlos. |
| DA-2 | ¿Mapa real dentro de la app? | `google_maps_flutter` (API key de Google Cloud) / `flutter_map` + OpenStreetMap (sin llave, con política de uso de tiles) / dejar el dibujo + CR-F04 | **Dejar el dibujo + CR-F04** para el prototipo. El criterio de G-06 de "abrir en app externa" se cumple sin cuentas. |
| DA-3 | ¿Push con Firebase? | Sí (crear proyecto) / No en el prototipo | Lo decide el equipo: crear el proyecto va contra la regla de no abrir cuentas externas sin acuerdo. Sin push, el guardia solo recibe alertas con la app abierta (SSE). |
| DA-4 | ¿Ubicación en segundo plano para el usuario? | Sí / No en el prototipo | **No en el prototipo.** Agrega un permiso sensible y la demo se hace con la app abierta. |
| DA-5 | ¿`grd-1` de turno las 24 h en la semilla del backend? | Sí / Dejar la ventana relativa | **Sí.** Iguala la semilla del front y evita que la demo dependa de la hora. |

---

## 6. Verificación en el teléfono (al cerrar la Ola 1)

Con la API en `npm run dev`, `adb reverse tcp:3000 tcp:3000`, `npm run demo:reset -- --center <lat>,<lng>` y `flutter run --debug --dart-define=API_URL=http://127.0.0.1:3000/api/v1`:

1. El login **no** muestra cuentas de prueba.
2. Con `guardia@safelink.mx` en sesión, el log de la API muestra `PUT /guard/location` cada ~5 s y ningún `429`.
3. Con `usuario@safelink.mx`, disparar una alerta: aparece en la base en `searching`.
4. El guardia la ve en su listado, con la distancia real desde donde está.
5. Aceptar: no hay botón "Simular acercamiento". "Abrir en Google Maps" abre la ruta.
6. "Llegué" está deshabilitado lejos del punto y se habilita a ≤ 50 m.
7. El usuario confirma: la alerta queda `closed`, con los cuatro estados en `alert_status_history` y en el historial del guardia.
8. El admin ve la alerta cerrada y las métricas actualizadas.

Si un paso falla, se anota en el PR con el extracto del log de la API.
