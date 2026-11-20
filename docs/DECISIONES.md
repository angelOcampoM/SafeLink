# SafeLink — Registro de decisiones

**Historias que cubre:** U-01 a U-09, G-01 a G-07, A-01 a A-08 (decisiones transversales del backend).
**Tarjeta:** BE-01 (paso 2; actualizado en el paso 5: D25, D28 y D29); BE-03 (D30, D31); BE-04 (D32 a D47). Varias decisiones se implementan en BE-02 a BE-07; se indica en cada una.
**Fecha de todas las decisiones:** 2026-11-10. **Decidido por:** el equipo / la responsable del backend.

Formato de cada decisión: contexto, opciones, decisión, consecuencias. Las rutas de archivo del front son relativas a `lib/`. Si el código y este documento discrepan, se reporta; no se corrige a ciegas.

Fuentes de verdad, en orden: el código del front, `docs/HISTORIAS_DE_USUARIO.md` y `docs/PLAN_DE_PRUEBAS.md`, y por último `docs/context_desarrollo_actualizado.md`. Si hay choque, gana el front. El contrato completo está en `docs/API_CONTRATO.md`.

---

## D1 · Turnos del guardia

- **Contexto:** la tarjeta BE-01 pide "turnos" como tabla. El front modela **un turno por guardia**: `shiftStart` y `shiftEnd` dentro del perfil (`datos/nube_mapeadores.dart:89-90`, `dominio/guardia.dart:23-24`).
- **Opciones:** (a) tabla `shifts` con historial de turnos; (b) dos columnas en `guard_profiles`.
- **Decisión:** columnas `shift_start` y `shift_end` (texto `"HH:mm"`, con `CHECK` de formato) en `guard_profiles`. No hay tabla `shifts`. El turno puede cruzar medianoche; inicio = fin significa turno de 24 h; el turno es `[inicio, fin)` (`dominio/regla_turno.dart:19-27`). "Turnos" de la tarjeta = estas columnas del perfil.
- **Consecuencias:** no hay historial de turnos. Si se necesita más adelante, se agrega una tabla sin romper el contrato.

## D2 · Foto de la alerta

- **Contexto:** el front manda `photoPath`, una ruta local (`datos/nube_alerta_usuario_repository.dart:27`); no existe subida real.
- **Opciones:** guardar la ruta tal cual; subir el archivo por `multipart/form-data`; usar un bucket desde el inicio.
- **Decisión:** interfaz `PhotoStorage { save(stream, mime) → { key, url }; url(key) }` y columna `alerts.photo_key`. `photoUrl` es un campo **calculado** (`PhotoStorage.url(photo_key)`). En BE-03 la subida es multipart a **disco local**; un bucket queda para después, detrás de la misma interfaz.
- **Consecuencias:** `evidenceIncomplete = true` cuando `photo_key` es nulo. Hasta BE-03 el front sigue mandando `photoPath`; el backend lo acepta pero no puede guardar el archivo. Ver `docs/API_CONTRATO.md`, sección 8.
- **Implementación (BE-03):** la subida va en la **misma ruta** `POST /alerts` como `multipart/form-data` (campo `data` con el mismo JSON y archivo opcional `photo`), para no agregar rutas que el front no conoce. Con JSON (lo que manda hoy el front) la alerta se crea sin foto y con `evidenceIncomplete = true`: `photoPath` es una ruta del teléfono y nunca se usa. `PhotoStorage` quedó como `save(bytes) → key`, `read(key)`, `remove(key)` (`backend/src/storage/photo-storage.ts`); la URL la arma un firmador aparte (D30). Disco local en `PHOTO_DIR` (`storage/fotos`, ignorada por git; volumen `safelink_fotos` en Compose). JPEG, PNG o WebP por firma de bytes; máximo `PHOTO_MAX_BYTES` (5 MiB). Si la alerta no se crea (bloqueo, otra activa), la foto se borra.

## D3 · Tiempo real con SSE

- **Contexto:** el front escucha cuatro canales con `escuchar(canal)`; cada evento es `{ "data": ... }` (`datos/safelink_service.dart:76-91`).
- **Opciones:** WebSocket; SSE; polling.
- **Decisión:** SSE. Rutas `GET /events/alerts/active`, `/events/guard/alerts`, `/events/guard/alerts/:id` y `/events/admin/alerts/escalated`. `Content-Type: text/event-stream`. Cada evento es `data: {"data": ...}\n\n`. Al conectar se envía el **estado actual** (snapshot completo, no deltas). Comentario `: ping` periódico, con intervalo configurable. Errores como `data: {"error":{...}}` y cierre. Autenticación con `Authorization: Bearer`, **nunca** token en el query. Rol por canal. El bus de eventos es **en memoria**, detrás de una interfaz `EventBus`; `LISTEN/NOTIFY` de Postgres queda para después. Implementación: BE-03 (usuario), BE-04 (guardia), BE-05 (admin).
- **Consecuencias:** con un bus en memoria solo funciona con una instancia de la API. El cliente debe poder mandar el header (la app Flutter puede; un `EventSource` de navegador no). Detalle en `docs/API_CONTRATO.md`, sección 6.

## D4 · Conexión de la app a un dispositivo físico

- **Contexto:** el front no tiene cliente HTTP; `SafeLinkService` es simulado (`datos/safelink_service.dart:1-8`, `main.dart:44,117-127`).
- **Decisión:** el paso 8 de BE-01 agrega un **cliente HTTP mínimo** en la app (`lib/datos/http_safelink_service.dart`): login, `/auth/me`, refresh, logout y `/auth/session`, almacén de tokens (`almacen_tokens.dart`), refresh compartido (single-flight) ante un 401 y refresh antes de restaurar la sesión; activado con `--dart-define=API_URL` (en release/profile solo `https`). El tiempo real llega en BE-03/BE-04. El modo simulado sigue por defecto.
- **Consecuencias:** toca `lib/` y `pubspec.yaml`, por lo que **requiere confirmación explícita antes de tocar `lib/`**. El resto de la app se conecta en BE-02 en adelante.

## D5 · Tablas extra

- **Contexto:** el front sugiere datos que no caben en las tablas básicas: alertas ignoradas por guardia (`datos/memoria_base_datos.dart:47-48`), tiempo en el estado actual para escalar (`:101-102`), historial de cambios para A-05 y ubicaciones de la alerta.
- **Decisión:** entran `alert_ignores`, la columna `alerts.status_changed_at` y la tabla `alert_status_history`. `alert_locations` queda para BE-03.
- **Consecuencias:** el escalamiento (BE-05) se apoya en `status_changed_at`. Ver `docs/MODELO_DATOS.md`.

## D6 · Diferencias entre el front y `docs/context_desarrollo_actualizado.md`

Se leyó el documento completo y se comparó contra el código. Por defecto **gana el front**. Referencias `CTX:n` = línea de `context_desarrollo_actualizado.md`.

**Equivalencia de numeración** con la sección 12 de `context_desarrollo_actualizado.md` (`CTX:426-438`): D1 a D6 de ese documento coinciden con las nuestras (turnos, foto, tiempo real, conexión del front, tablas extra, diferencias). Su **D7** (token y sesión) corresponde a nuestras **D7 y D8**; su **D8** (zona horaria y fechas) a nuestras **D12 y D21**; su **D9** (códigos HTTP) a nuestra **D9**. Nuestras D10 en adelante no tienen equivalente allá.

### Aspectos **sin** diferencias

- **Rutas del front:** las 31 coinciden en método, ruta, cuerpo y respuesta (`CTX:265-314` contra `safelink_service.dart:124-296`).
- **Canales:** los cuatro coinciden en nombre y forma (`CTX:321-326`).
- **Envoltorio y códigos de error:** los nueve códigos y el envoltorio coinciden (`CTX:262,244-254`, `datos/nube_mapeadores.dart:242-275`).
- **Enums:** `role`, `status`, `triggerMethod`, `escalationReason` y `resolution` coinciden, incluido `shake` = doble clic de volumen y el ajuste `volumeDoubleClickEnabled` (`CTX:13,196`, `datos/nube_mapeadores.dart:12-46`).
- **Formas JSON:** `User`, `GuardProfile`, `Alert`, `PrioritizedAlert`, `GeneralMetrics`, `GuardMetrics` coinciden campo por campo (`CTX:81-131,212,331-335`).
- **Reglas de validación** (`CTX:233-241`) coinciden con `dominio/regla_registro.dart`, `regla_turno.dart` y `regla_geocerca.dart`.
- **Valores por defecto** de configuración (50 m, 3 falsas alarmas, 7 días, 100, 250, 500, 10000, 300) coinciden con `dominio/configuracion.dart` y `dominio/regla_alerta.dart:61`.

### Diferencias encontradas

| # | Tema | Documento de contexto | Front (verificado) | Resolución |
|---|---|---|---|---|
| 1 | Prefijo de la API | Base `/api/v1` (`CTX:49,262`) | Las rutas no tienen prefijo (`safelink_service.dart:125`); son relativas a la base | **Resuelto (D20):** el servidor monta todo bajo `/api/v1`; la app usa `API_URL=http://host:3000/api/v1`. `/health` queda fuera del prefijo |
| 2 | Rutas de "instantánea" | Recomienda `GET /alerts/active`, `GET /guard/alerts`, `GET /admin/alerts/escalated` (`CTX:283,297,316`) | No existen; el front usa los canales | **No se implementan.** El snapshot llega al conectar el canal SSE (D3) |
| 3 | Token del dispositivo | `PUT /users/me/device-token` (`CTX:273`) | No existe (ni FCM, `CTX:52`) | Fuera de las 31 rutas. **Resuelto en BE-04** como excepción de contrato solo para `guard` (D42) |
| 4 | Ruta de refresh | No existe | No existe | Se agrega `POST /auth/refresh` como **excepción aprobada** (D8) |
| 5 | Forma del login | Sugiere `data: { token, user }` (`CTX:436`) | `desdeJson` lee el `User` directo de `data` (`datos/nube_auth_repository.dart:20`) | D7: `data` es el `User` con `accessToken` y `refreshToken` como campos extra. No se rompe el mapeador |
| 6 | Restaurar sesión | `GET /auth/me` con el token guardado (`CTX:436`) | `POST /auth/session { userId }` (`datos/nube_auth_repository.dart:50-54`) | Se mantiene `/auth/session` (ruta del front) y exige Bearer (D7) |
| 7 | Código `FORBIDDEN` | No existe (`CTX:244-254`) | `ErrorJson.desdeJson` convierte códigos desconocidos en un error genérico con su `message` (`datos/nube_mapeadores.dart:262`) | D9: `FORBIDDEN` es código nuevo, **excepción aprobada** |
| 8 | `INVALID_STATE` en HTTP | Un solo estado: 409 (`CTX:256`) | El front no usa HTTP | D9: 409 para transición de estado, 400 para validación; además `SERVICE_UNAVAILABLE` 500 para error inesperado |
| 9 | Nombres de configuración y unidad | Claves `acceptanceTimeoutMinutes` y `confirmationTimeoutMinutes` en minutos, `tapCountdownSeconds`, etc. (`CTX:172-185`) | Nombres en español y en **minutos** (`dominio/configuracion.dart:8-18`) | D11: variables de entorno con nombre propio y los tiempos de escalamiento en **segundos** (`ACCEPT_TIMEOUT_SECONDS=300`, `CONFIRM_TIMEOUT_SECONDS=900`, ya en `backend/src/config/env.ts:25-26`). `tapCountdownSeconds` es solo del cliente y no entra al backend |
| 10 | Tiempos de escalamiento | Producción usa `acceptanceTimeoutMinutes`; la confirmación tiene su propio límite (`CTX:176-177,187`) | `minutosAceptacion` y `minutosConfirmacion` **no los usa ningún código**; la simulación escala con `segundosEscalamientoDemo = 90` para ambos casos (`datos/memoria_base_datos.dart:191`) | El backend usa cada límite por separado (BE-05). El comportamiento del front es solo demostración |
| 11 | Máquina de estados | "Transiciones válidas, idénticas en el front" (`CTX:157-166`) | La tabla existe (`dominio/regla_alerta.dart:12-21`) pero **no se usa**: `puedeTransicionar` no se llama en ningún lado; la simulación escala desde `searching` sin pasar por `no_response` | Ver D14 |
| 12 | `GET /admin/users` | No precisa qué usuarios devuelve (`CTX:312`) | Solo `protected_user` (`datos/memoria_admin_repository.dart:163`) | Solo `protected_user` |
| 13 | Desbloqueo de usuario | "El admin puede retirar el bloqueo" (`CTX:230,314`) | Además pone `falseAlarmCount` en 0 (`datos/memoria_admin_repository.dart:177`) | `DELETE /admin/users/:id/block` también pone `falseAlarmCount = 0` |
| 14 | Zona horaria y fechas | "Confirmar que el cliente mande UTC" (`CTX:59,437`) | `triggeredAt` sí va en UTC (`presentacion/usuario/inicio_view_model.dart:113`, `presentacion/usuario/disparo_rapido.dart:74`). Los filtros `from`/`to` **no**: son fechas locales sin `Z` (`presentacion/admin/historial_view_model.dart:74-75`, `datos/nube_mapeadores.dart:226-227`). Las métricas por hora usan la hora local del dispositivo (`dominio/regla_metricas.dart:22`) | **Resuelto (D21):** el backend acepta ISO con o sin offset; sin offset se interpreta en `TZ_SHIFTS`. Las horas de `alertsByHour` se calculan en `TZ_SHIFTS` (D12) |
| 15 | Semilla | 6 cuentas, 5 guardias, 4 usuarios, ≥30 alertas cerradas (`CTX:388-404`) | 11 cuentas con contraseña `SafeLink1`, 8 guardias (`grd-1`…`grd-8`), usuarios `usr-1`…`usr-35` y más de 80 alertas históricas (`datos/datos_semilla.dart:8-21,28-35,39-40,43`). Los ids son texto (`usr-1`), no UUID | D13 y D10: mismas cuentas del front, perfiles y alertas activas; **sin** historial sintético; UUID deterministas |
| 16 | Concurrencia al aceptar | "Control de concurrencia en la API" (`CTX:213`) | El mock no tiene (`datos/memoria_alerta_guardia_repository.dart:55-68`) | El backend lo implementa (`UPDATE ... WHERE status = 'searching'` o equivalente) |
| 17 | Una alerta activa por usuario | No lo dice | El mock no lo impone al crear (`datos/memoria_alerta_usuario_repository.dart:14-43`); la simulación lo asume: "nadie tiene dos a la vez" (`datos/memoria_base_datos.dart:116-117`) | D15: el backend lo impone con un índice único parcial |
| 18 | `docs/HISTORIAS_DE_USUARIO.md` G-03 | — | Ver abajo | Ver abajo |

### `HISTORIAS_DE_USUARIO.md` y "agitación"

G-03 **ya dice** "doble clic de volumen" (`docs/HISTORIAS_DE_USUARIO.md:167`). Lo desfasado es la **nota de U-05** (`docs/HISTORIAS_DE_USUARIO.md:78-83`), que afirma que G-03 sigue diciendo "agitación"; fuera de esa nota no queda ninguna mención. Este paso no modifica ese archivo.

### Otros hallazgos del front que el backend debe cuidar

- El cliente real debe tolerar el campo extra y los códigos nuevos (ver puntos 5 y 7); el front lo soporta.
- El mock revienta (excepción no controlada) con campos ausentes, enums desconocidos o ids inexistentes en desbloqueo (`datos/safelink_service.dart:129,165`, `datos/memoria_admin_repository.dart:177`); el backend responde errores con envoltorio (D9).
- `datos/nube_auth_repository.dart:53` decide por `datos == null`, no por el estado HTTP.

## D7 · Token en login, registro y restauración de sesión

- **Contexto:** hoy `POST /auth/login` devuelve solo el `User` y la sesión se restaura con `POST /auth/session { userId }`, sin token (`datos/nube_auth_repository.dart:50-54`). Un cliente que conoce un `userId` podría abrir la sesión de otro: **hueco de seguridad del mock** (`datos/nube_auth_repository.dart:51`, `datos/auth_repository.dart:29-31`).
- **Opciones:** (a) `data: { token, user }`; (b) `User` con campos extra.
- **Decisión:** (b). `data` de login, register y refresh = `User` + `accessToken` (+ `refreshToken`) como campos extra; el mapeador ignora claves desconocidas (`datos/nube_mapeadores.dart:59-70`). `POST /auth/session` **exige** `Authorization: Bearer`, verifica el `userId` del cuerpo contra el `sub` del token y devuelve `User` o `null`. Usa **verificación propia** (no el hook `authenticate` general): `401 UNAUTHORIZED` **solo** si falta el token, la firma o el algoritmo no son válidos, o el token venció. Responde **200 con `data: null`** si el `sid` está revocado, el usuario está inactivo o dado de baja, o `userId` es distinto del `sub` (el front lo maneja borrando la sesión guardada, `presentacion/sesion/sesion_view_model.dart:41-44`).
- **Consecuencias:** el front no necesita cambiar su mapeador. La app deberá guardar y enviar el token (BE-02). Como el access vence a los 15 min, en BE-02 la app debe llamar `POST /auth/refresh` **antes** de `POST /auth/session` (o manejar el `401` dentro de `restaurar()`, que hoy no maneja excepciones, `presentacion/sesion/sesion_view_model.dart:35-47`). Hasta entonces, el modo simulado conserva el hueco.

## D8 · Sesiones: access token y refresh token

- **Contexto:** hace falta cerrar sesión de verdad y expulsar a un guardia dado de baja.
- **Decisión:**
  - Access JWT de **15 min** (`JWT_ACCESS_EXPIRES_IN`).
  - Refresh token **opaco** de **30 días** (`JWT_REFRESH_EXPIRES_IN`), guardado **hasheado** en la tabla `refresh_tokens`, con **rotación** en cada uso, **detección de reutilización** (un token ya usado revoca toda la familia) y **revocación**.
  - `POST /auth/refresh` es una ruta **nueva** (**EXCEPCIÓN aprobada** a la regla "no inventar rutas").
  - `POST /auth/logout` revoca la sesión.
  - La baja de un guardia revoca **todas** sus sesiones.
  - El hook `authenticate` vuelve a leer `is_active` en cada petición y rechaza un `sid` revocado (detalle en D25).
  - El backend se implementa en BE-01; la app lo usa en BE-02.
- **Consecuencias:** una petición con un usuario dado de baja devuelve `401 UNAUTHORIZED`, salvo `POST /auth/session` (verificación propia: `200` con `data: null` para sesión revocada o usuario inactivo; `401` solo por token ausente, inválido o vencido), para no romper `SesionViewModel.restaurar()` (`presentacion/sesion/sesion_view_model.dart:41-44`). Decidido (ver D7).

## D9 · Códigos HTTP de error

- **Contexto:** el front decide por `error.code`, no por HTTP (`datos/nube_mapeadores.dart:270-274`); `CTX:256` propone una tabla.
- **Decisión:** 401 `INVALID_CREDENTIALS` y `UNAUTHORIZED`; 403 `USER_BLOCKED` y `FORBIDDEN` (nuevo); 404 `NOT_FOUND` (también para recursos ajenos, para no revelar que existen); 409 `EMAIL_TAKEN`, `ALERT_TAKEN` e `INVALID_STATE` de transición; 400 `INVALID_STATE` de validación; 422 `OUTSIDE_GEOFENCE`; 500 `SERVICE_UNAVAILABLE` para error inesperado; 503 `SERVICE_UNAVAILABLE` cuando el servicio no está disponible (por ejemplo, base de datos caída). `FORBIDDEN` con el mensaje "No tienes permiso para realizar esta acción." es una **EXCEPCIÓN aprobada** a "no inventar códigos".
- **Consecuencias:** el front muestra el `message` de los códigos desconocidos (`datos/nube_mapeadores.dart:262`), así que `FORBIDDEN` se ve bien sin cambios. Para los códigos conocidos el front usa su propio texto. Tabla completa en `docs/API_CONTRATO.md`, sección 2.

## D10 · UUID en todo

- **Decisión:** todos los identificadores son UUID (string en JSON). La semilla usa **UUID deterministas fijos** (para que las pruebas y los ejemplos sean estables). Los ids de texto del front (`usr-1`, `grd-1`, `alt-101`) no se conservan.

## D11 · Configuración por variables de entorno

- **Decisión:** toda la configuración sale de variables de entorno **validadas con zod** al arrancar (`backend/src/config/env.ts`). No hay tabla `settings`. `.env.example` se versiona; `.env` nunca. Los valores del front que son configuración (`dominio/configuracion.dart`) se leen de ahí, no del código.

## D12 · Zona horaria

- **Decisión:** `TZ_SHIFTS=America/Mexico_City` sirve para **evaluar turnos** y para agrupar `alertsByHour`. **Todas las fechas** se guardan y se devuelven en UTC.
- **Consecuencias:** ver también D6 punto 14 sobre `from`/`to` sin offset.

## D13 · Semilla de datos

- **Decisión:** la semilla crea usuarios, perfiles de guardia y las alertas de ejemplo del front (`datos_semilla.dart`): **activas en cada estado** más las no activas que el front siembra (`no_response`, `escalated`, `resolved_by_admin`), con las cuentas del front. **Sin historial sintético**: va junto con las métricas (BE-07). La semilla **solo corre con `NODE_ENV` `development` o `test`** y se niega con `production` (paso 3 de BE-01).
- **Consecuencias:** difiere de `CTX:404` ("al menos 30 alertas cerradas") y de la semilla del front (más de 80 históricas). Ver D6 punto 15.

## D14 · Máquina de estados de la alerta

- **Contexto:** hay dos fuentes del front que no coinciden.
- **Comportamiento real del código:**
  - **Tabla de transiciones** (`dominio/regla_alerta.dart:12-21`): `pending_location → searching`; `searching → in_progress | no_response`; `no_response → escalated`; `in_progress → guard_arrived`; `guard_arrived → closed | escalated`; `escalated → resolved_by_admin`; `closed` y `resolved_by_admin` son finales. `puedeTransicionar` (`:23`) **no se llama** en ningún punto del front.
  - **Escalamiento** (`dominio/regla_alerta.dart:42-54`): `razonParaEscalar` devuelve `no_response` para `searching` **y** `no_response`, y `no_confirmation` para `guard_arrived`.
  - **Simulación** (`datos/memoria_base_datos.dart:189-203`): al vencer el límite pasa la alerta **directo a `escalated`** y le pone la razón. Desde `searching` salta `no_response`, algo que la tabla no permite. Ningún código del front asigna el **estado** `no_response`.
  - **`no_response` como estado** solo aparece en la semilla (`datos/datos_semilla.dart:286`, alerta `alt-204`, sin guardia).
  - **`escalationReason = no_response` no equivale a `status = no_response`:** la métrica `noResponseRate` cuenta por la razón (`dominio/regla_metricas.dart:28`).
  - Desde `in_progress` nunca se escala.
- **Decisión:** documentar el comportamiento real y **resolver en BE-05**: definir cuándo entra `no_response` (si es un paso intermedio persistente o se omite) y alinear tabla y escalamiento. Mientras tanto el contrato admite los ocho estados y ambas razones.
- **Consecuencias:** `docs/MODELO_DATOS.md` marca la inconsistencia. No se debe implementar el escalamiento antes de cerrar esta decisión.
- **Resuelta en BE-05 (ver D48):** `no_response` **no** se guarda como estado intermedio. `searching` pasa directo a `escalated` con `escalationReason = no_response` (como la simulación del front y como cuentan las métricas); `guard_arrived` pasa a `escalated` con `no_confirmation`. Un `no_response` heredado (semilla) se escala igual que `searching`. `pending_location` e `in_progress` nunca escalan.

## D15 · Una alerta activa por usuario

- **Decisión:** índice único **parcial** sobre `alerts (user_id)` donde el estado es activo (`pending_location`, `searching`, `in_progress`, `guard_arrived`).
- **Consecuencias:** al crear una alerta con otra activa, el backend responde `409 INVALID_STATE` (D22). Refleja el supuesto "nadie tiene dos a la vez" (`datos/memoria_base_datos.dart:116-117`).

## D16 · CORS

- **Decisión:** lista blanca en `CORS_ORIGINS`, **vacía por defecto** (`backend/src/config/env.ts:14-22`). Una app móvil nativa no necesita CORS.

## D17 · Coordenadas y distancia

- **Decisión:** `lat` y `lng` como `double precision`; distancia con **Haversine en TypeScript** (radio de la Tierra 6 371 000 m, igual que `dominio/regla_geocerca.dart:11-20`). **Sin PostGIS.**
- **Consecuencias:** con pocos guardias basta; si crece el volumen se revisa.

## D18 · Correo normalizado

- **Decisión:** el correo se guarda en **minúsculas** y recortado, con índice único. Sin `citext`. Coincide con la comparación del front (`datos/memoria_auth_repository.dart:16-17`, `datos/memoria_admin_repository.dart:14-15`).

## D19 · Entorno de desarrollo

- **Decisión:** Postgres en Docker, publicado **solo en `127.0.0.1`**; la API corre en el host con `npm run dev`. El servicio `api` de Docker Compose es para demostraciones. `HOST` es `127.0.0.1` por defecto (`backend/src/config/env.ts:7`); `0.0.0.0` es opt-in, para probar con el teléfono en la misma red.

---

## D20 · Prefijo de la API

- **Contexto:** `CTX:49,262` propone `/api/v1`; las rutas del front no llevan prefijo (`datos/safelink_service.dart:125`) porque son relativas a una base.
- **Decisión:** el servidor monta **todas** las rutas bajo `/api/v1`. Los canales SSE viven en `/api/v1/events/<canal>`. `GET /health` queda **fuera** del prefijo (infraestructura). La app usará `API_URL=http://host:3000/api/v1` (D4).
- **Consecuencias:** las rutas de `docs/API_CONTRATO.md` son relativas a `/api/v1`. Resuelve D6 punto 1.

## D21 · Fechas de filtros `from` / `to`

- **Contexto:** el front manda `from`/`to` como fechas locales sin `Z` (`presentacion/admin/historial_view_model.dart:74-75`, `datos/nube_mapeadores.dart:226-227`).
- **Decisión:** se acepta ISO 8601 con o sin offset; sin offset se interpreta en `TZ_SHIFTS` (`America/Mexico_City`). Las respuestas siempre van en UTC con `Z`.
- **Consecuencias:** resuelve D6 punto 14. Complementa D12.

## D22 · Propuestas aceptadas, visibilidad del guardia y aceptación atómica

- **Decisión:**
  - Respuesta **201** en los POST que crean recurso: `POST /alerts`, `POST /admin/guards` y `POST /auth/register`.
  - **Visibilidad** de `GET /guard/alerts/:id` y del canal `guard/alerts/:id`: alertas asignadas al guardia, o disponibles para él: en `searching`, dentro de su cobertura (centro + radio), con turno vigente y no ignorada (`zone` es solo una etiqueta). Cualquier otra, `404 NOT_FOUND`.
  - **`accept`** evalúa la visibilidad **sin la condición de estado** (cobertura centro + radio, turno vigente, no ignorada). No visible: `404 NOT_FOUND`. Visible y ya no en `searching`: `409 ALERT_TAKEN` (cumple G-05, `docs/HISTORIAS_DE_USUARIO.md:188`, `dominio/regla_alerta.dart:31`). El `UPDATE … WHERE status = 'searching'` atómico se mantiene; si afecta 0 filas, `409 ALERT_TAKEN`. `GET /guard/alerts/:id` conserva su visibilidad (asignada a él, o `searching` + cobertura + turno + no ignorada).
  - **`arrive`**: orden de verificaciones: existencia y propiedad (`404 NOT_FOUND`) → estado (`409 INVALID_STATE` si no está en `in_progress`) → geocerca (`422 OUTSIDE_GEOFENCE` con `remainingMeters`). Un guardia ajeno nunca recibe `remainingMeters`.
  - Los canales `guard/alerts` y `guard/alerts/:id` reevalúan la visibilidad **en cada emisión y por guardia** (nunca un snapshot global). Si la alerta deja de ser visible, se emite `{"error":{"code":"NOT_FOUND",...}}` y se cierra el stream. Los errores de autenticación o rol se responden con HTTP 401/403 antes de abrir el stream.
  - `409 INVALID_STATE` al crear una alerta teniendo otra activa (D15), y al enviar ubicaciones a una alerta que ya no está activa.
- **Consecuencias:** ya no son propuestas en `docs/API_CONTRATO.md`. Cierra D6 punto 16.

## D23 · Minimización de datos personales

- **Contexto:** el guardia necesita ver la alerta antes de aceptarla (G-04), pero no necesita el teléfono del usuario hasta atenderla.
- **Decisión:** `userPhone` es `null` salvo para el guardia **asignado** mientras la alerta esté activa; en `/guard/history` va sin teléfono. `userName`, `location` y `photoUrl` sí se muestran antes de aceptar. **Ampliación:** para el rol `guard`, `location` también va `null` cuando la alerta ya no está activa (en `/guard/history` y en `GET /guard/alerts/:id` de alertas no activas, incluidas `no_response` y `escalated`); `photoUrl` **se conserva** como evidencia de las alertas que atendió (decisión de la responsable del backend, 2026-11-10). Aplica a REST y SSE (`guard/alerts` y `guard/alerts/:id`). El admin ve todo; el dueño ve su propia alerta completa. `evidenceIncomplete` conserva su valor real (no se deriva de `photoUrl`).
- **Consecuencias:** el mapeador del front admite los tres campos nulos (`datos/nube_mapeadores.dart:122,127,129`). Se implementa al armar el Alert calculado (BE-03 y BE-04).
- **Verificación contra el front (pantallas del guardia con alertas no activas):**
  - Historial del guardia y resumen en Inicio usan `AlertCard` y `AlertDetailSheet`. La hoja solo muestra la foto si `fotoUrl != null` (`presentacion/comun/widgets/alert_detail_sheet.dart:57`) y no usa la ubicación; tolera `null`. El banner de evidencia incompleta depende de `evidenceIncomplete` (`:75`), no de `photoUrl`.
  - `AlertaAtendidaView` y `AlertaEscaladaView` solo usan nombre y razón (`presentacion/guardia/widgets/navegacion_guardia.dart:92-125`); `NavegacionPage` las muestra al llegar `closed` o `escalated` (`presentacion/guardia/navegacion_page.dart:60-61`).
  - `DetalleAlertaPage` tolera `location` nula: la distancia es opcional (`presentacion/guardia/widgets/detalle_guardia.dart:78,87`).
- **Riesgos:**
  - La foto de evidencia sigue visible para el guardia en su historial (`alert_detail_sheet.dart:57-74`): riesgo aceptado, porque es evidencia de su propio servicio. Su acceso queda sujeto a las reglas de la foto (ruta autenticada, sección "Pendientes de seguridad").
  - `NavegacionPage` no maneja `no_response` ni `resolved_by_admin`: si el stream de una alerta del guardia emite `resolved_by_admin` tras escalarse, se pinta la vista de ruta con `location` nula y distancia 0 (`navegacion_page.dart:63`). El comportamiento del front ya existía; con ubicación nula se agrava.

## D24 · Prioridad y temporizadores con la hora del servidor

- **Contexto:** `triggeredAt` viene del dispositivo; un reloj adelantado o atrasado alteraría la prioridad (`dominio/regla_prioridad.dart:29`) y los tiempos de escalamiento.
- **Decisión:** se guarda `triggeredAt` (solo se guarda y se devuelve) y una columna nueva `alerts.received_at` (hora del servidor al recibir `POST /alerts`). `received_at` se usa en **todo lo calculado**: `waitingMinutes` y `score`, temporizadores de escalamiento con hora del servidor (`received_at` / `status_changed_at`; detalle en BE-05 junto con D14), `avgAcceptanceSeconds` = `acceptedAt − receivedAt`, `avgArrivalSeconds` = `arrivedAt − (acceptedAt ?? receivedAt)` (generales y por guardia), `alertsByHour`, los filtros `from`/`to` de las rutas del admin (historial, métricas generales y por guardia) y el orden de `admin/alerts/escalated`. Validación de `triggeredAt`: ISO válido y dentro de ±`TRIGGERED_AT_TOLERANCE_SECONDS` (configurable, 600 por defecto) respecto a la hora del servidor; fuera de la ventana se **recorta a `received_at`** (no se rechaza, para no perder una alerta real por un reloj desfasado).
- **Consecuencias:** el JSON `Alert` del front **no cambia**: `receivedAt` no se expone (es interna). Se agrega al modelo en el paso 3 de BE-01. Difiere del front, que calcula con `triggeredAt` (`dominio/regla_metricas.dart:22,33-34`, `dominio/filtro_historial.dart:20-21`). `TRIGGERED_AT_TOLERANCE_SECONDS` (600 por defecto) está en `backend/src/config/env.ts` y `backend/.env.example`.

## D25 · Revocación inmediata de sesiones

- **Contexto:** con solo `is_active` y un JWT de 15 min, un logout o una baja tardarían hasta 15 min en surtir efecto.
- **Decisión:** el access JWT lleva `sid` (id de la familia en `refresh_tokens`) además de `sub` y `role`, firmado con HS256. `authenticate`, en la **misma consulta** que relee `is_active`, rechaza un `sid` revocado con `401`. **Excepción:** `POST /auth/session` usa verificación propia: `401` solo si falta el token, la firma o el algoritmo no son válidos, o venció; con `sid` revocado, usuario inactivo o `userId ≠ sub` responde `200` con `data: null` (D7). `logout` revoca su familia; la baja de un guardia revoca todas las suyas; ambos cierran los streams SSE abiertos vía `EventBus`. Refresh token: CSPRNG de al menos 256 bits, hash **SHA-256 indexado** (no argon2: es un secreto aleatorio de alta entropía y se busca por hash), rotación con detección de reutilización (reutilizar un token rotado revoca la familia) y una **ventana de gracia corta y configurable** para dos refresh concurrentes legítimos (ver abajo, implementada en BE-01 paso 5).
- **Implementación (BE-01 paso 5, `backend/src/auth/tokens.ts`):**
  - **Refresh token:** 32 bytes de CSPRNG en base64url; en la base solo se guarda su SHA-256 en hexadecimal (`token_hash`).
  - **Forma del token:** un `refreshToken` que no sea base64url de 43 caracteres da `401` sin tocar la base.
  - **Vigencia deslizante con tope absoluto:** `expires_at = min(now + JWT_REFRESH_EXPIRES_IN, family_started_at + JWT_SESSION_MAX_AGE)` (`JWT_SESSION_MAX_AGE`, 90d por defecto). Un refresh vencido, o de una sesión que superó la vida máxima, da `401` **sin** revocar la familia.
  - **Serialización por familia:** toda operación que cambia una familia (rotar, revocar, revocar todas las de un usuario) toma primero `pg_advisory_xact_lock(hashtextextended(family_id, 0))`; la rotación después bloquea la fila con `SELECT … FOR UPDATE`. Esto corrige la carrera revocación contra rotación: ningún sucesor nace después de una revocación. `revokeAllUserFamilies` toma los locks de varias familias en orden estable (ordenadas) para evitar interbloqueos.
  - **Hermano de gracia:** al rotar normalmente una rama que tiene hermano de gracia (mismo `parent_id`), el hermano que no se haya usado se revoca.
  - **Gracia solo con sucesor intacto:** la reutilización dentro de la ventana se acepta solo si el sucesor original sigue sin usar ni revocar; si ya rotó, es reutilización y se revoca la familia.
  - **Token revocado presentado:** si se presenta un token ya revocado (p. ej. el hermano descartado) y la familia aún tiene tokens vivos, es reutilización: se revoca toda la familia. El cliente legítimo nunca vuelve a presentar la rama que descartó.
  - **Ventana de gracia (`REFRESH_GRACE_SECONDS`, 0–60, default 5; 0 la desactiva):** un token ya rotado, presentado dentro de la ventana contada desde su `used_at`, se acepta **una vez más** y emite un **sucesor nuevo** de la misma familia (`parent_id` = el token rotado), **sin revocar** la familia. No se reenvía el sucesor original porque solo se guarda el hash. La gracia consumida se detecta porque el token ya tiene 2 hijos.
  - **Reutilización:** fuera de la ventana, o con la gracia ya consumida, se revoca **toda la familia** y se responde `401`.
  - **JWT:** al verificar se exigen `exp`, `iat`, `sub` y `sid` y se aplica `maxAge` igual a `JWT_ACCESS_EXPIRES_IN`. La verificación es manual (`verifyAccessToken`, Bearer con formato estricto), no `request.jwtVerify`.
  - **Rol desde la base:** `request.user` (`id`, `role`, `sid`) lo asigna **solo** `authenticate` y toma el rol de la base de datos, no del claim del token. `POST /auth/session` tiene la política `custom` en el registro central (`backend/src/security/policies.ts`): no lleva el hook de autenticación general y verifica su token por su cuenta.
  - **argon2:** argon2id con parámetros fijados por entorno (`ARGON2_MEMORY_KIB` 65536, `ARGON2_TIME_COST` 3, `ARGON2_PARALLELISM` 4). En un login correcto, si `needsRehash` indica parámetros distintos, el hash se actualiza (un fallo no bloquea el login).
  - **Login con usuario inactivo:** se verifica la contraseña contra su hash real y después se rechaza con `INVALID_CREDENTIALS`, para igualar tiempos con los demás casos.
- **Consecuencias:** una consulta a la base por petición autenticada. Dentro de la ventana de gracia **pueden coexistir dos sucesores vivos** de la misma familia (el original y el de la gracia); ambos mueren al revocar la familia. Reemplaza la idea inicial de "devolver el mismo sucesor", que no es posible sin guardar el token en claro. Complementa D8.

## D26 · Streams SSE de larga vida

- **Decisión:** el servidor cierra el stream al llegar el `exp` del access token; el cliente reconecta con un token renovado. Antes de cerrar por `exp`, `logout` o baja, el servidor emite `{"error":{"code":"UNAUTHORIZED",...}}`. Hay un máximo de conexiones SSE por usuario, configurable; al superarlo se **cierra la conexión más antigua** (no se rechaza la nueva, para no dejar sin datos a la app que reconecta). El valor numérico queda abierto.
- **Consecuencias:** requisito del cliente (BE-02 / BE-04): el `escuchar()` real debe reconectar al cerrarse el stream, renovando antes el token con `POST /auth/refresh`; no debe exponer la reconexión a los view models como fin de stream, y emite error solo si no puede reconectar. Los view models solo manejan `onError` (`presentacion/usuario/estado_alerta_view_model.dart:34-42`, `presentacion/guardia/navegacion_view_model.dart:63-71`).

## D27 · `etaSeconds` se calcula en cada lectura

- **Contexto:** el contrato lo marcaba como calculado "al aceptar"; el guardia se mueve y el valor se desactualizaría.
- **Decisión (de la responsable del backend):** no hay columna. Mientras la alerta esté `in_progress`: distancia Haversine entre `guard_profiles.last_location_lat/lng` y la ubicación de la alerta, dividida entre `GUARD_METERS_PER_MINUTE` (convertido a segundos, entero). `null` si falta alguna de las dos ubicaciones o la alerta no está `in_progress`. Se usa solo `last_location`; ya no se cae al centro de cobertura. Nota: la variable real en `backend/src/config/env.ts` es `GUARD_METERS_PER_MINUTE`.
- **Consecuencias:** implementación en BE-04. Se refleja en `docs/API_CONTRATO.md` y `docs/MODELO_DATOS.md`. Misma fórmula que `ReglaEta.segundos` (`dominio/regla_eta.dart:10-13`): distancia / metros por minuto × 60, redondeada y nunca negativa. Diferencias con el mock, sin efecto en la interfaz (`presentacion/usuario/estado_alerta_page.dart:214,250` muestra "Calculando llegada…" con `null`): `_etaDe` (`datos/memoria_base_datos.dart:121-129`) usa el centro de cobertura si falta la última ubicación y devuelve 0 si falta algo, y el mock pone 0 al llegar (`:153`); el backend no usa el centro de cobertura y devuelve `null` en esos casos y desde `guard_arrived`.

## D28 · `NODE_ENV` por defecto `production`

- **Contexto:** `env.ts` tomaba `development` si `NODE_ENV` faltaba; los comportamientos solo de desarrollo (errores detallados, CORS laxo, logs verbosos) quedarían activos por descuido.
- **Decisión:** si `NODE_ENV` falta, vale `production` (`backend/src/config/env.ts`): falla del lado seguro. El modo desarrollo se pide de forma explícita (`NODE_ENV=development` en `.env`; `.env.example` ya lo trae). La semilla (`prisma/seed.ts`) exige por su cuenta `development` o `test` definido y se niega en cualquier otro caso, incluido no definido.
- **Consecuencias:** quien copie `.env.example` no nota diferencia; quien no defina la variable corre en modo producción (sin pila en el log, ver paso 4). Atiende el pendiente "`NODE_ENV` de la API".

## D29 · Rate limit y código `TOO_MANY_REQUESTS`

- **Contexto:** `POST /auth/login` y `/auth/refresh` son públicos y permiten adivinar contraseñas o tokens.
- **Decisión:** `@fastify/rate-limit` con almacén **en memoria**, **por IP**, solo en `POST /auth/login` (10 por 1 m) y `POST /auth/refresh` (30 por 1 m); topes y ventanas configurables (`RATE_LIMIT_LOGIN_MAX` / `RATE_LIMIT_LOGIN_WINDOW`, `RATE_LIMIT_REFRESH_MAX` / `RATE_LIMIT_REFRESH_WINDOW`). Cuenta **todos** los intentos, no solo los fallidos. Al excederse: `429` con `{ "error": { "code": "TOO_MANY_REQUESTS", "message": "Demasiados intentos. Espera un momento e intenta de nuevo." } }` y cabecera `Retry-After`; no se envían `X-RateLimit-*`. `TOO_MANY_REQUESTS` es un código nuevo, **EXCEPCIÓN aprobada por la responsable** a "no inventar códigos" (igual que `FORBIDDEN`, D9). También se mapea un 429 de Fastify no controlado (`error-handler.ts`).
- **Consecuencias:** el front trata los códigos desconocidos como error genérico y muestra el `message` (`datos/nube_mapeadores.dart:~262`). Con el almacén en memoria el límite es por proceso (una instancia). Detrás de un proxy hay que configurar `trustProxy`, o todas las peticiones compartirán la IP del proxy. **`POST /auth/register` (BE-02) debe sumarse** al límite.

---

## D30 · URL firmada para ver la foto (BE-03)

- **Contexto:** la app pinta la foto con `Image.network(fotoUrl)` (`presentacion/comun/widgets/alert_detail_sheet.dart:57`), que no manda el header `Authorization`. Una ruta autenticada con Bearer no le serviría, y el token nunca puede ir en el query (sección 6 del contrato).
- **Decisión:** `photoUrl` es una URL firmada de vida corta: `GET /api/v1/alerts/:id/photo?exp=<epoch>&sig=<hmac>`. La firma es HMAC-SHA256 de `id.photoKey.exp` con una llave derivada de `JWT_SECRET`; caduca a los `PHOTO_URL_TTL_SECONDS` (900). La URL la emite el servidor solo a quien ya puede ver la alerta (hoy, su dueño; BE-04 y BE-05 la reutilizan con sus reglas de D23). La base de la URL es `PUBLIC_API_URL` (la misma `API_URL` de la app); sin ella, `http://127.0.0.1:PORT/api/v1`.
- **Consecuencias:** **EXCEPCIÓN** de rutas: `GET /alerts/:id/photo` no existe en el front y su política es `public` (la autoriza la firma, no el token). Es la segunda ruta extra junto a `POST /auth/refresh`; `tests/unit/politicas-contrato.test.ts` la lista en `EXTRAS`. Cualquier fallo (sin firma, alterada, vencida, de otra alerta o foto inexistente) responde `404 NOT_FOUND`, sin distinguir. Respuesta con `Content-Type` detectado por bytes, `X-Content-Type-Options: nosniff` y `Cache-Control: no-store`. Como cada snapshot del canal trae una URL nueva, la app siempre tiene una vigente mientras la alerta esté abierta.

## D31 · Transporte SSE (BE-03)

- **Decisión:** `backend/src/realtime/sse.ts` (`SseHub`) es común a los cuatro canales; cada canal solo da su nombre, su snapshot, uno o varios temas del `EventBus` (`topic`/`topics`) y, opcionalmente, `refreshOnPing` (D34) (`backend/src/realtime/event-bus.ts`, en memoria). BE-03 implementa `alerts/active`; BE-04 y BE-05 agregan los suyos en `backend/src/modules/events/routes.ts`.
- **Ping y revocación:** cada `SSE_PING_SECONDS` (25) se manda `: ping` y se revisa en la base que la sesión siga viva (`findLiveSessionUser`). Así un `logout` o una baja cierran el stream con `UNAUTHORIZED` **a más tardar en el siguiente ping**, sin que el módulo de auth tenga que conocer los streams. Es una variante de D25 ("cierran los streams vía `EventBus`"): el retraso máximo es `SSE_PING_SECONDS`.
- **Vencimiento (D26):** el stream se cierra al llegar el `exp` del access token, avisando antes `UNAUTHORIZED`.
- **Máximo por (usuario, canal) (D26, D34):** `SSE_MAX_CONNECTIONS_PER_USER` (3) por cada canal; al pasarse se cierra la conexión **más antigua de ese canal**. Hasta BE-03 se contaba por usuario.
- **Snapshots:** un aviso del bus vuelve a leer el snapshot de la base; varios avisos seguidos producen a lo más una lectura extra. Quien cambie una alerta debe publicar `alertsTopicForUser(userId)` (BE-03 lo hace al crear, mover y confirmar; **BE-04 y BE-05 deben hacerlo** al aceptar, marcar llegada, escalar y resolver, o el usuario no verá el cambio; `PUT /guard/location` también lo hace si el guardia tiene una alerta `in_progress`, para refrescar el ETA).
- **Apagado:** un hook `preClose` cierra todos los streams para que la API no se quede esperando.

---

## D32 · Alcance de BE-04

- **Estado:** implementada (pasos 1 a 11); documentada en el paso 12.
- **Decisión:** BE-04 cubre todo lo que `docs/API_CONTRATO.md` le asigna: las 8 rutas `/guard/*` (`me`, `history`, `metrics`, `location`, `alerts/:id`, `accept`, `ignore`, `arrive`), los canales `GET /events/guard/alerts` y `GET /events/guard/alerts/:id`, `PUT /users/me/device-token` y la notificación push.
- **Consecuencias:** la documentación de rutas, permisos, modelo y pruebas se actualizó en el paso 12 (`docs/API_CONTRATO.md` secciones 5.1, 5.3, 6 y 10; `docs/PERMISOS.md`; `docs/MODELO_DATOS.md` secciones 3.7 y 10; `docs/PLAN_DE_PRUEBAS.md`; `docs/CONEXION_DISPOSITIVO.md` sección 10).

## D33 · Equivalencia de historias del issue #54

- **Estado:** aprobada (solo documental).
- **Decisión:** HU-11 = G-02 (recepción), HU-12 = G-03 (listado), HU-24 = G-05 (aceptación); G-04, G-06 y G-07 entran como soporte.
- **Consecuencias:** con numeración consecutiva HU-24 sería A-08, que no encaja con el issue; la numeración del Project es otra. Los documentos citan las historias como `G-0X`.

## D34 · Tiempo real del guardia

- **Estado:** implementada (BE-04 pasos 3 a 7; BE-05 completa solo la salida por escalada). Detalle por paso: paso 3 (varios temas, `refreshOnPing`, límite por (usuario, canal), log `info` de `AppError`, canal `guard/alerts` y temas `dispatchTopic`/`guardTopic`/`alertTopic`; paso 4: canal `guard/alerts/:id` con `alertTopic` + `guardTopic` y `refreshOnPing`, para cerrarse si una alerta solo disponible deja de serlo por turno o cobertura). Paso 5: `accept` publica `alertsTopicForUser(dueño)`, `alertTopic` y `dispatchTopic` (la alerta desaparece al instante del listado de los demás). Paso 6: `ignore` publica solo `guardTopic` (D39). Paso 7: `arrive` publica `alertsTopicForUser(dueño)` y `alertTopic` (sin `dispatchTopic`: la alerta no estaba en `searching`). Pendiente solo la salida de `searching` por escalada, que llega en BE-05 y mientras tanto la cubre el ping.
- **Contexto:** a diferencia de `alerts/active` (un tema por dueño, D31), lo que ve cada guardia depende de su cobertura, turno e ignoradas, y cambia con el paso del tiempo.
- **Decisión:**
  - `SseChannel` admite **varios topics** (compatible con el `topic` actual). Temas nuevos: `dispatchTopic` (global: una alerta entra o sale de `searching`, o cambia su ubicación estando en `searching`), `guardTopic(guardId)` (su ubicación e ignorar; BE-06 agrega cobertura y baja) y `alertTopic(alertId)` (cualquier cambio de esa alerta).
  - El snapshot se **recalcula por guardia** desde la base en cada emisión (D22), nunca uno global. El listado se refresca además en cada ping (`SSE_PING_SECONDS`) para reflejar el paso del tiempo (espera, turnos).
  - Si `guard/alerts/:id` deja de ser visible: evento `NOT_FOUND` y cierre. Un `:id` que no sea UUID también se responde con evento `NOT_FOUND`; los `401`/`403` siguen respondiéndose por HTTP antes de abrir el stream.
  - Los `AppError` esperados del snapshot se registran en nivel `info`.
  - El límite de streams (D26) pasa a ser por **(usuario, canal)** y no por usuario, para que abrir el listado y el detalle a la vez no se expulsen entre sí.
  - `accept` y `arrive` publican también `alertsTopicForUser(dueño)` (D31), para que el usuario vea el cambio. `ignore` no, porque el dueño no observa nada distinto (D39).
- **Detalle:** el nombre del canal es obligatorio y fijo (no uno por alerta), para que el límite no se multiplique. Un guardia sin perfil recibe una lista vacía, no un error (un error cerraría el stream y el cliente reconectaría en bucle).
- **Consecuencias:** cada evento de `dispatchTopic` provoca una lectura por guardia conectado; con pocos guardias es aceptable (misma lógica que D17). Complementa D3, D26 y D31.
- **Riesgo aceptado para el prototipo (revisión de seguridad, paso 3):** el costo crece como avisos × streams abiertos × alertas en `searching` (la consulta trae todas y filtra en memoria), y `refreshOnPing` hace unas 3 consultas por stream en cada ping aunque nada cambie; con el límite por canal un usuario puede tener más streams que antes y no hay tope total. Antes de un despliegue real: intervalo mínimo entre snapshots por stream, una sola consulta de `searching` por ventana compartida entre guardias, recorte por *bounding box* de la cobertura con `take` configurable, y tope total de streams por usuario y global.

## D35 · Aceptación atómica

- **Estado:** implementada (paso 5; migración `20261118170000_guard_assignment` con `alerts_guard_absent_chk`, y `accept` en `backend/src/modules/guard/service.ts`). Una alerta ya tomada dentro de mi cobertura (o la mía propia) responde `409 ALERT_TAKEN`; solo lo no visible es `404`.
- **Decisión:** `updateMany` con `where { id, status: 'searching', guardId: null }`, dentro de una transacción que escribe también el historial (`alert_status_history`, actor = el guardia). Si afecta 0 filas: `409 ALERT_TAKEN`. Antes se evalúa la visibilidad con `skipStatusCheck` (D22): no visible, `404`. Migración nueva con el `CHECK` `alerts_guard_absent_chk`: `guard_id IS NULL` en `pending_location`, `searching` y `no_response`. Las pruebas de concurrencia se repiten varias veces con Postgres real.
- **Consecuencias:** cierra en la base el pendiente "`guard_id` en estados sin guardia" (hoy solo lo cuida la API). Concreta D22 y D6 punto 16.
- **Baja concurrente:** dentro de la transacción se bloquea la fila del guardia (`FOR SHARE`) y se revisa `is_active`; una baja que llegue durante la aceptación espera al commit (ver pendiente de BE-06).
- **Riesgo aceptado (revisión de seguridad, paso 5):** como la visibilidad se evalúa sin la condición de estado, una alerta histórica (cerrada, escalada, resuelta) **dentro de la cobertura y el turno** del guardia responde `409 ALERT_TAKEN` y no `404`. Revela que ese UUID existe en su zona, sin ningún dato; los UUID v4 no se pueden adivinar y el guardia solo los conoce si ya vio la alerta. Lo mismo para el canal lateral de tiempo (1 consulta si no existe, 3 si existe).

## D36 · Un guardia, una alerta en atención

- **Estado:** implementada (paso 5; índice `alerts_one_active_per_guard_idx`; la regla se revisa después de la visibilidad para no distinguir ajena de inexistente, y un `P2002` del índice en una carrera se traduce al mismo `409`). Además, el guardia asignado solo ve `userPhone` en `in_progress` y `guard_arrived`.
- **Contexto:** desde `in_progress` no se escala (D14); una alerta acaparada por un guardia que ya atiende otra quedaría atascada.
- **Decisión:** un guardia con una alerta `in_progress` o `guard_arrived` no puede aceptar otra: `409 INVALID_STATE` con el mensaje «Ya estás atendiendo otra alerta». Se garantiza con un índice único parcial `alerts (guard_id) WHERE status IN ('in_progress', 'guard_arrived')`.
- **Consecuencias:** el front lo muestra vía `EstadoInvalidoError(mensaje)`. Si el índice falla en una carrera, la API lo traduce al mismo `409`.

## D37 · Guardia sin última ubicación

- **Estado:** implementada (paso 3: listado; paso 7: `arrive` responde `422` con `remainingMeters: null` sin última ubicación; `backend/src/modules/guard/service.ts`).
- **Decisión:** en el listado, `distanceMeters` usa `lastLocation ?? centro de cobertura` (`docs/API_CONTRATO.md:301`); `etaSeconds` queda `null` (D27, que no usa el centro de cobertura). `arrive` responde `422 OUTSIDE_GEOFENCE` con `remainingMeters: null` si no hay última ubicación.
- **Consecuencias:** una `lastLocation` vieja o falsificada que permita marcar llegada se **acepta como riesgo documentado**: la reporta el cliente y el backend no puede verificarla.

## D38 · `PUT /guard/location`

- **Estado:** implementada (paso 2; `backend/src/modules/guard/routes.ts` y `service.ts`).
- **Decisión:** límite por usuario, en `preHandler` (después de autenticar), con ventana `LOCATION_UPDATE_SECONDS` y tope `RATE_LIMIT_LOCATIONS_PER_WINDOW` (los mismos de `POST /alerts/:id/locations`, D29 y pendientes de seguridad). Validación: `lat` −90..90 y `lng` −180..180, finitos, `.strict()`. **No exige turno vigente**: el guardia puede reportar su posición fuera de turno.
- **Consecuencias:** cierra el pendiente de rate limit de `PUT /guard/location`. Como en `POST /alerts/:id/locations`, una petición rechazada con `400` consume cupo (el límite corre antes de validar el cuerpo); un `401` no. Si el guardia tiene una alerta `in_progress`, se publica `alertsTopicForUser(dueño)` una vez por dueño para refrescar el ETA (D31).

## D39 · Ignorar es idempotente

- **Estado:** implementada (paso 6; `POST /guard/alerts/:id/ignore` en `backend/src/modules/guard/`, responde `{ "data": null }`).
- **Decisión:** la visibilidad se evalúa **sin** el filtro de "ignorada"; la inserción en `alert_ignores` usa `skipDuplicates`. Un segundo `ignore` responde `200`. Si la alerta está asignada al guardia, el registro no cambia su visibilidad (la asignación manda, D22).
- **Alerta propia en curso:** responde `200` **sin guardar** el registro ni publicar (el contrato no define un error). Si se guardara, una liberación o escalada posterior la dejaría oculta para ese guardia sin que lo pidiera.
- **Tiempo real:** solo publica `guardTopic(guardId)`: su listado la quita y su `guard/alerts/:id` emite `NOT_FOUND`. **No** publica `alertsTopicForUser(dueño)` ni `dispatchTopic` (corrige D34): el dueño no ve las ignoradas y a los demás guardias no les cambia nada.
- **Consecuencias:** reintentos de red del cliente no producen error ni duplicados.

## D40 · Mensajes y respuestas del guardia

- **Estado:** implementada (404 en el paso 1, mensaje de D36 en el paso 5 y `409` de `arrive` en el paso 7).
- **Decisión:**
  - `404 NOT_FOUND` «La alerta ya no existe», con **cuerpo idéntico** para alerta inexistente, no visible, ajena, UUID mal formado y guardia sin perfil. No hay `403` ni `409` que permitan enumerar (pendiente "Recurso ajeno = 404").
  - `409 INVALID_STATE` de `arrive` fuera de `in_progress`: «Esta alerta ya no está en atención».
  - `409 INVALID_STATE` de D36: «Ya estás atendiendo otra alerta».
- **Consecuencias:** el front usa su propio texto para los códigos conocidos (D9); estos mensajes sirven al cliente HTTP y a las pruebas.

## D41 · Historial y métricas del guardia

- **Estado:** implementada (paso 1; `backend/src/domain/metrics.ts` y `backend/src/modules/guard/`).
- **Decisión:**
  - `/guard/history`: alertas **no activas** con `guard_id` propio, orden `received_at` descendente y luego `id` ascendente, **sin paginación** (el front no la manda; el crecimiento queda como riesgo).
  - `/guard/metrics` se calcula sobre la misma lista con `received_at` (D24). Cada duración se **trunca a segundos enteros antes de promediar** (como `Duration.inSeconds` del front); la llegada se mide desde `acceptedAt ?? receivedAt`; sin datos, `0`.
  - Función pura en `backend/src/domain/metrics.ts`, reutilizable por BE-07.
  - El guardia recibe `adminNote` tal cual (decisión del usuario).
- **Consecuencias:** `adminNote` es visible para el guardia en su historial; no se aplica la minimización de D23 a ese campo. Se aplican igual `userPhone` y `location` nulos de D23.

## D42 · Token de dispositivo

- **Estado:** implementada (paso 9; migración `20261118180000_device_tokens`, `backend/src/modules/devices/` y borrado en `backend/src/auth/tokens.ts`).
- **Detalle de implementación:** el token se valida sin recortar (1–512 caracteres del alfabeto de FCM/APNs, `[A-Za-z0-9_:.-]`; si no, `400`), para no guardar algo distinto de lo que mandó el cliente y para que un carácter de control no llegue a Postgres como un `500`. El registro toma el lock de la familia y exige sesión viva (si no, `401`), para que un `PUT` justo después del `logout` no deje un token huérfano. El borrado vive en la revocación de familia, así que lo cubren `logout`, la reutilización de un refresh, el refresh de un usuario inactivo y la gracia no disponible; `revokeAllUserFamilies` borra todos los del usuario. Para enviar (paso 11) solo cuentan tokens de usuarios activos con un refresh de su familia no revocado **y no vencido**. Rate limit por usuario con `RATE_LIMIT_REFRESH_MAX` / `RATE_LIMIT_REFRESH_WINDOW`.
- **Riesgos aceptados y pendientes (revisión de seguridad, paso 9):**
  - **Reasignación entre cuentas:** si un guardia conociera el token push de otro (no son públicos ni adivinables), al registrarlo le quitaría el push a ese otro guardia (FCM entrega al teléfono dueño del token, no al que lo registra). Se acepta: el caso legítimo (el teléfono cambia de cuenta) es más común y el SSE sigue siendo el canal principal. Mitigación futura: no reasignar si la sesión del dueño actual sigue viva.
  - **Sin tope por sesión:** varios tokens pueden convivir en una misma familia hasta el `logout` (FCM rota tokens). Mitigación futura: una familia = un dispositivo, reemplazar el anterior.
  - **Retención:** los tokens de familias que vencen sin revocarse no se borran (no se usan: `findLiveTokens` los excluye). Pendiente una limpieza periódica.
  - **Baja de guardia (BE-06):** `deactivateGuard` (BE-02) pone `isActive = false` pero no llama a `revokeAllUserFamilies`; sus tokens quedan guardados aunque no se usen. Ya está en los pendientes de asignación de BE-06.
- **Contexto:** `PUT /users/me/device-token` existe en `CTX:273` pero no en el front (D6 punto 3).
- **Decisión:** **EXCEPCIÓN de contrato aprobada**, solo para el rol `guard` (minimización; agregar `protected_user` después no rompe nada). Tabla `device_tokens`: `id`, `user_id` (FK con cascada), `token` (texto único, máximo 512), `family_id` (el `sid` de la sesión que lo registró), `created_at`, `last_seen_at`; sin `platform` (CTX solo manda `{token}`). Upsert idempotente por `token`; si era de otro usuario se **reasigna**. Responde `null`. `logout` borra los tokens con `family_id = sid`; la baja (BE-06, pendiente) borrará todos; solo se envía a tokens cuya familia sigue viva.
- **Consecuencias:** es la tercera ruta extra (junto a `POST /auth/refresh` y la foto, D30); `tests/unit/politicas-contrato.test.ts` la lista en `EXTRAS`. Atiende el pendiente "`PUT /users/me/device-token`: no permitido para `admin`".

## D43 · `PushNotifier` y adaptador FCM

- **Estado:** implementada (paso 10; `backend/src/notifications/`: interfaz, no-op y `fcm-notifier`; doble en `backend/tests/helpers/recording-notifier.ts`). **No verificado contra FCM real:** solo con un `fetch` falso y llaves RSA efímeras. El disparo existe desde el paso 11 (D44), pero sigue sin verificarse contra FCM real.
- **Detalle de implementación:** con `PUSH_PROVIDER=fcm` la API no arranca si falta la variable o el JSON de la cuenta es inválido, y el error nunca muestra el contenido del archivo. `FCM_PROJECT_ID` y `FCM_SERVICE_ACCOUNT_FILE` vacías cuentan como ausentes. Un `401` renueva el access token una vez sin gastar intento; `Retry-After` se respeta con un tope de 10 s; 5 envíos en paralelo y tokens deduplicados; timeout de 10 s por petición. Nunca se registra el cuerpo de las respuestas de Google. `backend/.gitignore` ignora `*service-account*.json`, `*-firebase-adminsdk-*.json` y `firebase-*.json`.
- **Tokens inválidos (endurecido tras la revisión de seguridad):** FCM responde `400 INVALID_ARGUMENT` tanto a un token inválido como a un mensaje mal formado. Por eso un token solo se marca para borrar con `404` + `UNREGISTERED` o con un `400` cuyo detalle `google.rpc.BadRequest` señala `message.token`; cualquier otro `400`, o un `404` sin `UNREGISTERED`, cuenta como fallido. Salvaguarda: si en un envío con 2 o más destinatarios **todos** salen inválidos, no se borra ninguno y se registra un `warn` (probable error del mensaje).
- **Endurecimiento (revisión de seguridad):** `token_uri` solo `https` en `oauth2.googleapis.com` o `www.googleapis.com` (si no, la API no arranca); la llave debe ser RSA; `redirect: 'error'` en OAuth y FCM; los cuerpos no leídos se cancelan para liberar conexiones; `warn` con solo conteos cuando hay fallos o falla OAuth. El doble de pruebas vive en `backend/tests/helpers/` y no llega a la imagen. Los patrones de credenciales están también en el `.gitignore` de la raíz y en `backend/.dockerignore`; el nombre por defecto de GCP (`<proyecto>-<hex>.json`) no se puede ignorar con un patrón seguro: guardar el JSON fuera del repo.
- **Decisión:** interfaz `PushNotifier` con una implementación **no-op** (solo log, sin datos personales), un doble para pruebas y un adaptador **FCM HTTP v1 sin dependencias nuevas** (`fetch` nativo y `node:crypto` con RS256 para el JWT de la cuenta de servicio; caché del access token hasta `exp − 60 s`). Apagado por defecto. Variables: `PUSH_PROVIDER` (`none` | `fcm`, por defecto `none`), `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_FILE` (ruta a un JSON **fuera del repo**) y `PUSH_MAX_ATTEMPTS` (2).
  - **Payload** solo de datos: `{ "type": "alert", "alertId": "...", "urgent": ... }`. Android: prioridad `HIGH` y `ttl = ACCEPT_TIMEOUT_SECONDS` (la app arma la notificación con canal de alarma y pantalla completa). iOS: `apns-priority 10` con `aps.alert` genérico.
  - **Errores:** un token solo se borra con `404` + `UNREGISTERED` o con un `400` cuyo detalle `google.rpc.BadRequest` trae un `fieldViolation` en `message.token`; cualquier otro `400` (incluido `INVALID_ARGUMENT` sin esa señal) o un `404` sin `UNREGISTERED` cuenta como fallido y no borra nada. Salvaguarda: si en un envío con 2 o más destinatarios todos salen inválidos, no se borra ninguno y se registra un `warn`. `429`/`5xx`/red: reintentos hasta `PUSH_MAX_ATTEMPTS` respetando `Retry-After` con tope de 10 s; `401` renueva el OAuth una vez sin gastar intento.
  - **Entrega:** mejor esfuerzo y asíncrona, después del commit; **un envío por alerta** (una llamada al notificador con todos los tokens, sin repetidos) y, en el adaptador FCM, **un mensaje por token** (FCM v1 no tiene multicast). Un guardia con varios dispositivos recibe un mensaje por token.
  - **Mensaje exacto** (`fcm-notifier.ts`): `data` = `{type:'alert', alertId, urgent:'true'|'false'}` (todos texto); `android` = `{priority:'HIGH', ttl:'<ACCEPT_TIMEOUT_SECONDS>s'}` sin bloque de notificación; `apns` = `headers {apns-priority:'10'}` y `aps {alert:{title:'SafeLink', body:'Nueva alerta cerca de ti'}, sound:'default'}`. Documentado en `docs/API_CONTRATO.md`, sección 10.
- **Consecuencias:** el payload no lleva nombre, teléfono ni ubicación (D23). Sin credenciales reales no se puede probar la entrega; las pruebas usan el doble y un `fetch` simulado. La llave de la cuenta de servicio nunca se versiona.

## D44 · Quién y cuándo se notifica

- **Estado:** implementada (paso 11; `backend/src/notifications/dispatcher.ts`, evento `AlertChange.published`, `findLiveDevices` y `deleteTokensOf` en devices). Detalles:
  - Solo se dispara al **publicar**: creación con ubicación o paso `pending_location` → `searching`; no por movimiento.
  - Es fire-and-forget **tras el commit**: la respuesta HTTP no espera al push y un fallo no la afecta.
  - Se relee la alerta antes de enviar: si ya no está en `searching`, tiene guardia o no tiene ubicación, no se envía.
  - Destinatarios: los que cumplen `isAlertAvailableToGuard` y además tienen una sesión viva (D42). Un solo envío por alerta (una llamada al notificador), tokens sin repetidos; el adaptador FCM manda un mensaje por token (D43).
  - `urgent` = `isUrgent(triggerMethod)` (verdadero con disparo `shake`).
  - Tope `PUSH_MAX_TOKENS_PER_ALERT` (500 por defecto, rango 1..500): si se rebasa, se prioriza a los guardias más cercanos (distancia como en D37) y se registra un `warn`.
  - Los tokens inválidos se borran solo si pertenecen a este envío y a sus destinatarios.
  - Los logs llevan solo ids y conteos.
  - Con `PUSH_PROVIDER=none` no se consulta nada (el despachador queda deshabilitado).
  - `dispatchAlert` se exporta para que BE-06 lo reutilice.
- **Decisión:** se notifica cuando una alerta **nace** con ubicación (entra en `searching`) y cuando una `pending_location` recibe coordenadas y pasa a `searching`. Destinatarios: los que devuelve **la misma función** que arma el snapshot de `guard/alerts` (activo, con cobertura, en radio, en turno, sin ignorar) y que además tienen un token de sesión viva (D42). **No** se renotifica por movimiento en `searching`. Un guardia que entra en turno con alertas ya en `searching` no recibe push: las ve por el canal (al conectar o en el refresco del ping, D34).
- **Consecuencias:** BE-06 debe llamar al mismo despachador cuando una alerta vuelva a `searching` (baja de un guardia con alerta `in_progress`).
- **Riesgos aceptados (prototipo):** la entrega es de mejor esfuerzo. Entre leer los tokens y enviar, un guardia que cierra sesión, es dado de baja o ignora la alerta puede recibir un último aviso; solo lleva el `alertId` y la autorización real ocurre al abrir la alerta (`GET /guard/alerts/:id` y `accept` revalidan). No hay límite global de despachos simultáneos ni se esperan los pendientes al cerrar la app: lo acotan el límite de alertas por usuario y D15. El abuso (un usuario que publica y cancela para avisar a todos los guardias de su zona) depende del límite de falsas alarmas de BE-06.

## D45 · Parte del front

- **Estado:** aprobada; fuera de BE-04. **Pendiente** (tarjeta del front aún sin hacer); la guía ya está escrita en el paso 12.
- **Decisión:** el cliente HTTP de `/guard/*`, el `escuchar()` real con reconexión (D26), Firebase/FCM, el canal de alarma con pantalla completa en Android y los permisos van en **una tarjeta aparte del front**. En BE-04 solo se documentan en `docs/CONEXION_DISPOSITIVO.md` (sección 10); lo que esa guía marca como recomendación no está verificado en este repo.
- **Consecuencias:** hasta esa tarjeta, el guardia solo se prueba con el backend vía pruebas y herramientas HTTP. No se toca `lib/` en BE-04.

## D46 · Migración de las pruebas de BE-03

- **Estado:** implementada (paso 8; helper `backend/tests/integration/flujo/guardia-flujo.ts`, migrados `alertas-usuario.test.ts` y `canal-alerta-activa.test.ts`, y caso de extremo a extremo en `flujo-completo.test.ts`). Ninguna aserción se relajó; la de ETA de U-08 se volvió más estricta (valor exacto según D47). Los fixtures que preparan un estado concreto para probar otra cosa (restricciones de base, visibilidad, historial) siguen escribiendo directo en la base.
- **Decisión:** las pruebas de BE-03 que simulaban al guardia escribiendo directo en la base (`alertas-usuario.test.ts`) se migran a las **rutas reales** del guardia, **sin debilitar ninguna aserción**.
- **Consecuencias:** si alguna aserción no se puede conservar con la ruta real, se reporta en lugar de relajarla.

## D47 · ETA redondeado en la vista del dueño

- **Estado:** implementada (paso 7; `snapToGrid` en `backend/src/domain/geo.ts` y `roundEtaUp` en `backend/src/domain/alert-rules.ts`, aplicados en `serializeOwnAlert`).
- **Contexto:** la revisión de seguridad del paso 2 encontró que, con una alerta `in_progress`, el usuario podía mandar ubicaciones inventadas (`POST /alerts/:id/locations`) y leer `etaSeconds` (≈ 4 m por segundo de ETA) para triangular la posición exacta del guardia, ahora en tiempo real. Contradice "el usuario ve el ETA, no la ubicación del guardia".
- **Decisión (aprobada por el usuario):** en la vista del **dueño** (REST y `alerts/active`):
  1. La última ubicación del guardia se ajusta al **centro de una celda** de `ETA_GUARD_GRID_METERS` (250 por defecto, mínimo 100; `snapToGrid` en `backend/src/domain/geo.ts`) antes de calcular el ETA.
  2. El resultado se redondea **hacia arriba** a un múltiplo de `ETA_ROUNDING_SECONDS` (60 por defecto, mínimo 30). `0` sigue en `0` y `null` en `null`; sigue siendo entero.
  Las vistas del guardia y del admin conservan el valor exacto. Los dos campos son obligatorios en `SerializeOptions`, para que ningún servicio nuevo entregue el ETA exacto al dueño por olvido.
- **Por qué los dos:** la revisión de seguridad mostró que redondear solo la salida no basta: con una búsqueda binaria sobre el punto donde cambia el escalón (~25-30 ubicaciones falsas, ~1 min con el límite actual) se recupera la posición exacta. Con la celda, esa búsqueda solo revela el centro de la celda.
- **Consecuencias:** el contrato no cambia (el campo sigue siendo entero). Riesgo residual aceptado: el dueño puede saber en qué celda de ~250 m está el guardia, y el abuso es visible para el guardia (ve "saltar" la ubicación de la alerta). Además, como la cuadrícula es fija y cada `PUT /guard/location` empuja `alerts/active`, un dueño que deja fija su ubicación puede notar el momento en que el guardia cruza el borde de una celda y fijar esa coordenada con un margen de ~20 m (o la que marque el jitter del GPS si el guardia está quieto junto a un borde). Mitigación futura si hiciera falta: histéresis al cambiar de celda, o publicar el ETA del dueño solo cuando cambie el valor ya redondeado. Se descartaron rechazar ubicaciones en `in_progress` (rompe U-07) y congelar el ETA del dueño hasta la siguiente ubicación del guardia (más invasivo).

## D48 · Alcance de BE-05: seguimiento, escalamiento y resolución

- **Estado:** implementada (BE-05, issue #55).
- **Alcance:** los 7 pasos del issue #55 (ubicación en vivo, compartirla con el guardia, ETA sin revelar al guardia, llegada por geocerca, cierre solo con confirmación y guardia, fin de la transmisión al cerrar) ya los cumplían BE-03 y BE-04; BE-05 los demuestra en `backend/tests/integration/seguimiento/criterios-be05.test.ts`. Además, lo que el contrato (5.5) asigna a BE-05: escalamiento automático, `POST /admin/alerts/:id/resolve`, canal `admin/alerts/escalated` y bloqueo por falsas alarmas. Quedan para BE-07: `DELETE /admin/users/:id/block`, `GET /admin/users/blocked` y las métricas.
- **Escalamiento (D14 resuelta):** `backend/src/modules/escalation/service.ts`. Cada `ESCALATION_SWEEP_SECONDS` (15; 0 lo apaga) se revisan las alertas vencidas: `searching` (o `no_response` heredado) con más de `ACCEPT_TIMEOUT_SECONDS` en su estado → `escalated` / `no_response`, sin guardia; `guard_arrived` con más de `CONFIRM_TIMEOUT_SECONDS` → `escalated` / `no_confirmation`, **conservando** al guardia (evidencia; el índice de D36 lo libera). El tiempo se mide desde `status_changed_at` con la hora del servidor (D24). Cada alerta se escala con un `updateMany` condicionado al estado y al `status_changed_at` leídos: si un guardia acepta o el usuario confirma en el mismo instante, gana esa acción. Historial con `actorId = null` (lo hace el sistema). Retraso máximo sobre el límite: `ESCALATION_SWEEP_SECONDS`. Una alerta que falla no detiene la revisión de las demás.
- **Avisos al escalar (D31, D34):** `alertsTopicForUser(dueño)` (alerts/active emite `null`), `alertTopic`, `dispatchTopic` si salió de `searching` (desaparece del listado de los guardias), `guardTopic` del guardia que atendía y el tema nuevo `escalatedTopic` (bandeja del admin).
- **Resolver (A-04, A-08):** `POST /admin/alerts/:id/resolve`. Orden del front: estado (409 `Esta alerta ya no está escalada`) y después nota (400). Pone `resolved_by_admin`, `resolution`, `adminNote` recortada y `closedAt`; conserva `escalationReason`. Condicionado a `escalated`, así dos admins no la resuelven dos veces. Con `false_alarm`, en la misma transacción y con la fila del usuario bloqueada (`FOR UPDATE`): suma 1 a `falseAlarmCount` y, al llegar a `FALSE_ALARM_LIMIT`, `blockedUntil = ahora + BLOCK_DAYS` (renovado en cada falsa alarma posterior). Por debajo del límite el bloqueo existente **no** se toca (contrato 5.4; el mock lo borraba). Publica `escalatedTopic` y `alertTopic`.
- **Canal `admin/alerts/escalated`:** lista completa de escaladas, la más antigua primero por `received_at` (D24), con la vista del admin (`serializeAdminAlert`: todo, ETA exacto). Se refresca con `escalatedTopic`.
- **Consecuencias:** **BE-06 y BE-07** deben publicar `escalatedTopic` si cambian el estado de una escalada por otra vía. La baja de un guardia (BE-06) con una alerta `guard_arrived` puede escalarla reutilizando el mismo servicio.

## Pendientes de seguridad para tarjetas siguientes

Cosas que no se cierran en el paso 2 pero que el backend **debe** resolver. Cada una se atiende en la tarjeta indicada.

**Asignación de guardias (de BE-04 paso 5 para BE-05 y BE-06)**

- **Baja de un guardia (BE-06):** en este orden, `is_active = false` y después liberar o reasignar sus alertas `in_progress`/`guard_arrived` (con `guard_id = null` si vuelven a `searching`, o el `CHECK` de D35 falla). Así una aceptación que gane la carrera (ver D35, "Baja concurrente") queda cubierta. Al liberar una alerta (baja, escalada o reasignación), borrar el registro de `alert_ignores` del guardia que la tenía: una carrera entre `ignore` y `accept` del mismo guardia puede haberlo dejado (D39) y la ocultaría si vuelve a `searching`. Debe llamar al mismo despachador del push (D44) y publicar `guardTopic`.
- **Reasignar desde admin (BE-06):** si el guardia destino ya atiende otra, el índice de D36 lanza `P2002`; dar un mensaje claro en vez del `INVALID_STATE` genérico.
- **Atendido en BE-05 (D48).** **Escalar o resolver (BE-05):** escalar desde `guard_arrived` deja `guard_id` (el índice libera al guardia); comprobar que `escalated` y `resolved_by_admin` no le muestran `userPhone` ni `location` (D23). Cualquier vuelta a `searching` o paso a `no_response` pone `guard_id = null` en la misma sentencia. Revisar que un `23514` (violación de `CHECK`) caiga en un 4xx o 5xx genérico sin mensaje interno.

**Plataforma (BE-01, paso 4 en adelante)**

- **Manejador global de errores**: **atendido** en BE-01 paso 4. Ningún error inesperado filtra la traza ni detalles internos; siempre `500 SERVICE_UNAVAILABLE` con el mensaje fijo. El 404 de ruta inexistente refleja solo el path, sin query string y truncado a 100 caracteres. Fuera de production el log incluye solo los marcos de la pila (sin el mensaje original).
- **`@fastify/helmet`** con encabezados de seguridad.
- **`bodyLimit`** explícito: **atendido** en BE-01 paso 4 con `BODY_LIMIT_BYTES` (1 MiB por defecto, máximo 10 MiB). Con la subida de foto en BE-03 se sube solo en esa ruta, nunca el global.
- **Recurso ajeno = 404, no 403** (BE-02 en adelante): `forbidden()` solo cuando el rol no tiene permiso para la ruta. La propiedad se valida antes de escribir (`where: { id, ownerId }`); no depender de que una violación de FK (400) o de unicidad (409) dé la respuesta, porque 400/409 frente a 404 permite enumerar.
- **Errores de plugins**: traducción de `FST_JWT_*` (y `FAST_JWT_*`) a `UNAUTHORIZED` con mensaje fijo: **atendido en BE-01 paso 5** (`backend/src/http/error-handler.ts`). El 429 con su propio error: **atendido** (D29).
- **`Cache-Control: no-store`** en todas las respuestas bajo `/api/v1`: **atendido en BE-01 paso 5** (`backend/src/app.ts`).
- **Rate limit**: `POST /auth/login` y `/auth/refresh`: **atendido** (D29). **Sigue pendiente en BE-02:** `POST /auth/register`. **Atendido en BE-03**, por usuario (no por IP) y después de autenticar: `POST /alerts` (`RATE_LIMIT_ALERTS_PER_MINUTE`, 5 por minuto) y `POST /alerts/:id/locations` (`RATE_LIMIT_LOCATIONS_PER_WINDOW`, 3 por ventana de `LOCATION_UPDATE_SECONDS`). `PUT /guard/location`: **atendido en BE-04 paso 2** (D38), por usuario y después de autenticar, con el mismo límite.
- **Deny-by-default**: **atendido en BE-01 paso 6**. Registro central único `ROUTE_POLICIES` (`backend/src/security/policies.ts`) con las 38 entradas (36 de BE-01, más la foto de BE-03, D30, y `PUT /users/me/device-token` de BE-04, D42); un hook `onRoute` aborta el arranque si una ruta bajo `/api/v1` no tiene política, si su `config` (opcional) contradice la central o si está fuera del prefijo (solo `GET /health` exento). Detalle y matriz en `docs/PERMISOS.md`; pruebas en `backend/tests/integration/seguridad/` y `backend/tests/unit/politicas-contrato.test.ts`.
- **Límites de entrada** (BE-01 paso 4 en adelante): `password` ≤ 128; largos máximos de `name`, `email`, `phone`, `zone`, `search` y `photoPath`; `heading` entero 0–359; `radiusMeters` entero; `:id` validado como UUID (inválido → `404 NOT_FOUND`); `.strict()` también en el query.
- **Semilla** (paso 3 de BE-01): solo corre con `NODE_ENV` `development` o `test`; se niega con `production`.
- **Logs** (BE-01 paso 4 en adelante): prohibido registrar cuerpos, coordenadas, teléfonos, `password`, `accessToken` o `refreshToken`.
- **`passwordHash` fuera de las respuestas**: **atendido en BE-01 paso 5.** El cliente Prisma lo omite por defecto (`backend/src/db/prisma.ts`). Regla de ESLint (`backend/eslint.config.mjs`, `no-restricted-syntax`) que prohíbe `passwordHash` dentro de `select`/`omit` fuera de `src/modules/auth/`, y `new PrismaClient` fuera de `src/db/` (exentos `tests/**`). Serializador `User` explícito, campo por campo, sin spread (`src/modules/auth/serializers.ts`). **Sigue pendiente (BE-02 en adelante):** el SQL crudo (`SELECT *` / `RETURNING *` sobre `users`) no lo cubre la regla; pruebas del `omit` en relaciones (`include: { user: true }`) y en lo que devuelven `create`/`update`/`upsert`.
- **`NODE_ENV` de la API**: **atendido** (D28): `production` por defecto.
- **Rate limit solo por IP** (antes de cualquier despliegue): (a) detrás de Docker con puertos publicados, docker-proxy puede hacer que todos los clientes compartan la IP del gateway y un solo cubo; verificarlo con `API_BIND=0.0.0.0`. Si algún día se configura `trustProxy`, que sea una lista de IP concretas, nunca `true` (X-Forwarded-For se puede falsificar). (b) No hay límite por cuenta (correo normalizado) contra ataques distribuidos a una sola cuenta. (c) En IPv6 cada /128 es una clave distinta.
- **`JWT_SECRET` de baja entropía** (antes de cualquier despliegue): hoy solo se exigen 32 caracteres. En `production`, rechazar valores de ejemplo o triviales y exigir al menos 32 bytes aleatorios (43+ caracteres base64url) con el comando del README.
- **Regla ESLint de `passwordHash`**: es una capa extra que se puede saltar (clave computada `{[k]: false}`, `$queryRaw` que seleccione `password_hash`, o desde `tests/**`). El control real es el `omit` global de `backend/src/db/prisma.ts` y la prueba "ninguna respuesta contiene passwordHash"; mantener esa prueba en cada tarjeta nueva.
- **Baja de usuarios** (BE-06): poner primero `is_active=false` y después `revokeAllUserFamilies`; así una familia creada por un login concurrente entre la lectura y el bloqueo ya no sirve (`authenticate` y la rotación rechazan inactivos).
- **`guard_id` en estados sin guardia** (BE-04): la base acepta una alerta `searching` con `guard_id`; la API debe dejarlo en `null` en `pending_location`, `searching` y `no_response` para que la visibilidad por `guard_id` no se abra de más. **Atendido en BE-04 paso 5** con el `CHECK` de D35 (`alerts_guard_absent_chk`).
- **JWT con algoritmo fijo `HS256`** en firma y verificación: **atendido en BE-01 paso 5** (`backend/src/plugins/auth.ts`: `sign.algorithm` y `verify.algorithms` = `HS256`).
- Contraseñas con **argon2** (argon2id con parámetros por entorno `ARGON2_*`, por defecto los de la librería, y `needsRehash` en el login, `backend/src/auth/password.ts`): **atendido en BE-01 paso 5**; el mock las guarda en claro (`datos/memoria_base_datos.dart:43`, `datos/memoria_auth_repository.dart:23`).
- **Login**: hash ficticio para igualar tiempos con correo inexistente: **atendido en BE-01 paso 5** (se precalienta en `onReady`). Con usuario inactivo se verifica contra su hash real (D25).
- **`EMAIL_TAKEN` en register**: riesgo de enumeración de correos **aceptado**, mitigado con rate limit (BE-02).
- **Esquemas zod `.strict()`** en todos los cuerpos y queries: una clave extra (`role`, `isActive`, `falseAlarmCount`…) devuelve `400 INVALID_STATE`.
- **Validaciones de entrada**: `lat` −90..90 y `lng` −180..180, finitos.
- **`GET /health`** solo responde `status`.
- **`PUT /users/me/device-token`** (contexto, BE-04): no permitido para `admin` (ver D42: solo `guard`).

**Foto (BE-03)** — **atendido en BE-03** (D2, D30)

- Se sirve por URL firmada de vida corta (D30); nunca como archivo estático público ni con token en el query.
- `photo_key` es un UUID generado por el servidor (`randomUUID`); el `photoPath` del cliente nunca se usa como ruta.
- MIME validado por firma de bytes y tamaño máximo (`PHOTO_MAX_BYTES`).
- El `photoPath` del cliente nunca se usa como ruta del sistema de archivos.

**Rutas de administración (BE-06)**

- `GET`, `PATCH`, `DELETE` de `/admin/guards/:id` y `PUT …/coverage`: `NOT_FOUND` "No encontramos a ese guardia" si el id no existe **o no es rol `guard`**.
- **Bloqueante para BE-06 (y BE-05, por D14):** la baja de un guardia con una alerta `in_progress` debe, en la misma transacción, devolverla a `searching` o escalarla.

**Huecos de propiedad y de estado del mock que el backend debe cerrar**

| Dónde en el mock | Qué falta | Qué debe hacer el backend |
|---|---|---|
| `datos/memoria_alerta_usuario_repository.dart:52-60` (`enviarUbicacion`) | No verifica que la alerta sea del usuario ni que esté activa | Solo el dueño; alerta ajena = `404 NOT_FOUND`; alerta no activa = `409 INVALID_STATE` (BE-03) |
| `datos/memoria_alerta_usuario_repository.dart:62-71` (`confirmarAtencion`) | Solo valida el estado, no el dueño | Solo el dueño de la alerta (BE-03) |
| `datos/memoria_alerta_guardia_repository.dart:46-49` (`obtenerAlerta`) | Cualquier guardia ve cualquier alerta | Visibilidad de D22; las demás `404 NOT_FOUND` (BE-04) |
| `datos/memoria_alerta_guardia_repository.dart:55-68` (`aceptarAlerta`) | No revisa disponibilidad, cobertura ni alertas ignoradas; no hay concurrencia | Visibilidad de D22 **sin** la condición de estado (no visible → `404 NOT_FOUND`; visible y no `searching` → `409 ALERT_TAKEN`); `UPDATE … WHERE status = 'searching'` atómico, 0 filas → `409 ALERT_TAKEN` (D22; BE-04) |
| `datos/memoria_alerta_guardia_repository.dart:84-98` (`marcarLlegada`) | No revisa que el guardia sea el asignado ni que la alerta esté en `in_progress` | Solo el asignado (`404` si no); `409 INVALID_STATE` si no está en `in_progress` (BE-04) |
| `datos/memoria_alerta_guardia_repository.dart:70-74` (`ignorarAlerta`) | No valida que la alerta exista ni sea visible para el guardia | Validar existencia y visibilidad (BE-04) |
| `datos/memoria_admin_repository.dart:174-178` (`desbloquearUsuario`) | Opera sobre cualquier id; revienta si no existe | Solo `protected_user`; si no, `404 NOT_FOUND` (BE-07) |
| `datos/nube_auth_repository.dart:50-54` (`/auth/session`) | Sin token (D7) | Exigir Bearer (BE-01) |

**Validaciones que la base no puede imponer (paso 3 de BE-01)**

- La API debe validar que `alerts.guard_id` y `alert_ignores.guard_id` sean usuarios con rol `guard` (no se puede con CHECK).

## D49 · Alcance de BE-07: historial, métricas y desbloqueo del administrador

**Contexto.** BE-07 cierra las seis rutas de administración que quedaban: `GET /admin/alerts`
(A-05), `GET /admin/metrics` (A-06), `GET /admin/metrics/guards/:id` (A-07), `GET /admin/users`,
`GET /admin/users/blocked` y `DELETE /admin/users/:id/block` (A-08). Con eso quedan 37 de las 38
rutas de la política implementadas; la única pendiente es `PUT /admin/guards/:id/coverage` (A-03,
BE-06).

**Decisiones.**

1. **Las fechas del filtro sin zona son hora de pared de `TZ_SHIFTS`.** El front manda
   `DateTime.toIso8601String()` sobre una fecha local, así que el texto llega sin zona
   (`2026-11-18T00:00:00.000`). Leerlo como UTC correría el rango seis horas: el "día 18" del
   administrador dejaría fuera la tarde del 18 y metería la madrugada del 19. Si el texto trae
   zona explícita se respeta la que trae. La conversión vive en `src/domain/timezone.ts`, con
   `Intl` (nada que instalar) y en dos pasadas, para que en una zona con horario de verano se
   use el desplazamiento de esa fecha y no uno fijo.

2. **Una fecha imposible es 400, no un rango distinto.** `Date.parse` acepta un 31 de febrero
   y lo corre al 3 de marzo en silencio. El esquema revisa el día del calendario aparte: un
   filtro con una fecha que no existe se rechaza en lugar de responder un periodo que nadie
   pidió.

3. **Los códigos de `status` del filtro salen del enum de la base**, no de una lista escrita a
   mano en el esquema: un estado nuevo en el modelo queda filtrable sin tocar el esquema y no
   pueden desalinearse. Un estado desconocido es `400 INVALID_STATE` (en el mock del front
   revienta).

4. **`alertsByHour` agrupa por la hora de `TZ_SHIFTS`.** El front usa la hora local del
   dispositivo (`regla_metricas.dart:22`), que en el servidor no existe; la referencia es la
   zona de los turnos, no la del proceso (en CI es UTC). Queda configurable y hay una prueba
   que lo levanta con `TZ_SHIFTS=UTC` para demostrar que la zona es lo que decide.

5. **Las métricas por guardia solo exigen que el id sea de un guardia**, no que tenga perfil:
   exigir el perfil haría que un guardia al que le falte esa fila (dato inconsistente)
   pareciera no existir. Un id que no es de un guardia es `NOT_FOUND` y no un guardia con
   ceros, que se leería como "guardia sin actividad".

6. **El desbloqueo a mano reinicia `falseAlarmCount`.** Si solo quitara `blockedUntil`, la
   siguiente falsa alarma volvería a pasar el límite y el desbloqueo duraría un solo
   incidente. Desbloquear a quien no está bloqueado no es error: deja el mismo estado final.

7. **Un bloqueo vencido no se borra de la base.** Es historial; simplemente deja de salir en
   `GET /admin/users/blocked`, que filtra por `blockedUntil` en el futuro.

**Pendiente heredado (no es de BE-07).** El enum `TriggerMethod` de la base guarda el doble clic
de volumen como `shake` (`CodigosJson.metodo`, `nube_mapeadores.dart:31`), nombre que quedó del
texto antiguo "agitación". Funciona de punta a punta, pero el nombre engaña a quien lea la base.
Renombrarlo es una migración que toca el front y el backend a la vez, así que se deja anotado
para acordarlo en equipo y no se cambia aquí.

---

**Decisiones de diseño aún abiertas**

- **Ventana de gracia del refresh (D25):** **cerrada en BE-01 paso 5.** Se eligió aceptar el token ya rotado una vez más y emitir un sucesor nuevo de la misma familia; `REFRESH_GRACE_SECONDS` vale 5 por defecto.
- Nombre de la variable del intervalo de `: ping` del SSE (BE-03).
- Valor por defecto del máximo de conexiones SSE por usuario (D26; al superarlo se cierra la más antigua).
