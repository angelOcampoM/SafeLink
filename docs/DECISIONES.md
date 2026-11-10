# SafeLink — Registro de decisiones

**Historias que cubre:** U-01 a U-09, G-01 a G-07, A-01 a A-08 (decisiones transversales del backend).
**Tarjeta:** BE-01 (paso 2). Varias decisiones se implementan en BE-02 a BE-07; se indica en cada una.
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

## D3 · Tiempo real con SSE

- **Contexto:** el front escucha cuatro canales con `escuchar(canal)`; cada evento es `{ "data": ... }` (`datos/safelink_service.dart:76-91`).
- **Opciones:** WebSocket; SSE; polling.
- **Decisión:** SSE. Rutas `GET /events/alerts/active`, `/events/guard/alerts`, `/events/guard/alerts/:id` y `/events/admin/alerts/escalated`. `Content-Type: text/event-stream`. Cada evento es `data: {"data": ...}\n\n`. Al conectar se envía el **estado actual** (snapshot completo, no deltas). Comentario `: ping` periódico, con intervalo configurable. Errores como `data: {"error":{...}}` y cierre. Autenticación con `Authorization: Bearer`, **nunca** token en el query. Rol por canal. El bus de eventos es **en memoria**, detrás de una interfaz `EventBus`; `LISTEN/NOTIFY` de Postgres queda para después. Implementación: BE-03 (usuario), BE-04 (guardia), BE-05 (admin).
- **Consecuencias:** con un bus en memoria solo funciona con una instancia de la API. El cliente debe poder mandar el header (la app Flutter puede; un `EventSource` de navegador no). Detalle en `docs/API_CONTRATO.md`, sección 6.

## D4 · Conexión de la app a un dispositivo físico

- **Contexto:** el front no tiene cliente HTTP; `SafeLinkService` es simulado (`datos/safelink_service.dart:1-8`, `main.dart:44,117-127`).
- **Decisión:** el paso 8 de BE-01 agrega un **cliente HTTP mínimo** en la app (solo login y `GET /auth/me`), activado con `--dart-define=API_URL`. El modo simulado sigue por defecto.
- **Consecuencias:** toca `lib/` y `pubspec.yaml`, por lo que **requiere confirmación explícita antes de tocar `lib/`**. El resto de la app se conecta en BE-02 en adelante.

## D5 · Tablas extra

- **Contexto:** el front sugiere datos que no caben en las tablas básicas: alertas ignoradas por guardia (`datos/memoria_base_datos.dart:47-48`), tiempo en el estado actual para escalar (`:101-102`), historial de cambios para A-05 y ubicaciones de la alerta.
- **Decisión:** entran `alert_ignores`, la columna `alerts.status_changed_at` y la tabla `alert_status_history`. `alert_locations` queda para BE-03.
- **Consecuencias:** el escalamiento (BE-05) se apoya en `status_changed_at`. Ver `docs/MODELO_DATOS.md` (se crea en el paso 3 de BE-01).

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
| 3 | Token del dispositivo | `PUT /users/me/device-token` (`CTX:273`) | No existe (ni FCM, `CTX:52`) | Fuera de las 31 rutas. Se evalúa en BE-04 junto con las notificaciones |
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

- **Decisión:** la semilla crea usuarios, perfiles de guardia y alertas **activas en cada estado**, con las cuentas del front. **Sin historial sintético**: va junto con las métricas (BE-07). La semilla **solo corre con `NODE_ENV` `development` o `test`** y se niega con `production` (paso 3 de BE-01).
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
- **Consecuencias:** `docs/MODELO_DATOS.md` (se crea en el paso 3 de BE-01) marca la inconsistencia. No se debe implementar el escalamiento antes de cerrar esta decisión.

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
- **Consecuencias:** el JSON `Alert` del front **no cambia**: `receivedAt` no se expone (es interna). Se agrega al modelo en el paso 3 de BE-01. Difiere del front, que calcula con `triggeredAt` (`dominio/regla_metricas.dart:22,33-34`, `dominio/filtro_historial.dart:20-21`). `TRIGGERED_AT_TOLERANCE_SECONDS` es una variable nueva que falta en `backend/src/config/env.ts`.

## D25 · Revocación inmediata de sesiones

- **Contexto:** con solo `is_active` y un JWT de 15 min, un logout o una baja tardarían hasta 15 min en surtir efecto.
- **Decisión:** el access JWT lleva `sid` (id de la familia en `refresh_tokens`) además de `sub` y `role`, firmado con HS256. `authenticate`, en la **misma consulta** que relee `is_active`, rechaza un `sid` revocado con `401`. **Excepción:** `POST /auth/session` usa verificación propia: `401` solo si falta el token, la firma o el algoritmo no son válidos, o venció; con `sid` revocado, usuario inactivo o `userId ≠ sub` responde `200` con `data: null` (D7). `logout` revoca su familia; la baja de un guardia revoca todas las suyas; ambos cierran los streams SSE abiertos vía `EventBus`. Refresh token: CSPRNG de al menos 256 bits, hash **SHA-256 indexado** (no argon2: es un secreto aleatorio de alta entropía y se busca por hash), rotación con detección de reutilización (reutilizar un token rotado revoca la familia) y una **ventana de gracia corta y configurable** para dos refresh concurrentes legítimos: dentro de ella se devuelve el **mismo sucesor ya emitido** (no se crea otra rama de la familia).
- **Consecuencias:** una consulta a la base por petición autenticada. Complementa D8.

## D26 · Streams SSE de larga vida

- **Decisión:** el servidor cierra el stream al llegar el `exp` del access token; el cliente reconecta con un token renovado. Antes de cerrar por `exp`, `logout` o baja, el servidor emite `{"error":{"code":"UNAUTHORIZED",...}}`. Hay un máximo de conexiones SSE por usuario, configurable; al superarlo se **cierra la conexión más antigua** (no se rechaza la nueva, para no dejar sin datos a la app que reconecta). El valor numérico queda abierto.
- **Consecuencias:** requisito del cliente (BE-02 / BE-04): el `escuchar()` real debe reconectar al cerrarse el stream, renovando antes el token con `POST /auth/refresh`; no debe exponer la reconexión a los view models como fin de stream, y emite error solo si no puede reconectar. Los view models solo manejan `onError` (`presentacion/usuario/estado_alerta_view_model.dart:34-42`, `presentacion/guardia/navegacion_view_model.dart:63-71`).

---

## Pendientes de seguridad para tarjetas siguientes

Cosas que no se cierran en el paso 2 pero que el backend **debe** resolver. Cada una se atiende en la tarjeta indicada.

**Plataforma (BE-01, paso 4 en adelante)**

- **Manejador global de errores** (paso 4): ningún error inesperado filtra la traza ni detalles internos; siempre `500 SERVICE_UNAVAILABLE` con el mensaje fijo. El 404 de ruta inexistente refleja solo el path, sin query string.
- **`@fastify/helmet`** con encabezados de seguridad.
- **`bodyLimit`** explícito (con la subida de foto en BE-03 se sube solo en esa ruta).
- **Rate limit** en `POST /auth/login`, `/auth/refresh` (BE-01) y `POST /alerts` (BE-03); en `POST /auth/register` (BE-02); además, por usuario y acorde a `LOCATION_UPDATE_SECONDS`, en `PUT /guard/location` (BE-04) y `POST /alerts/:id/locations` (BE-03).
- **Deny-by-default** (BE-01, paso 6): toda ruta declara `roles` o `public: true` en su configuración; un hook `onRoute` hace fallar el arranque si falta; una prueba recorre todas las rutas registradas.
- **Límites de entrada** (BE-01 paso 4 en adelante): `password` ≤ 128; largos máximos de `name`, `email`, `phone`, `zone`, `search` y `photoPath`; `heading` entero 0–359; `radiusMeters` entero; `:id` validado como UUID (inválido → `404 NOT_FOUND`); `.strict()` también en el query.
- **Semilla** (paso 3 de BE-01): solo corre con `NODE_ENV` `development` o `test`; se niega con `production`.
- **Logs** (BE-01 paso 4 en adelante): prohibido registrar cuerpos, coordenadas, teléfonos, `password`, `accessToken` o `refreshToken`.
- **JWT con algoritmo fijo `HS256`** en firma y verificación (rechazar `none` y otros).
- Contraseñas con **argon2**; el mock las guarda en claro (`datos/memoria_base_datos.dart:43`, `datos/memoria_auth_repository.dart:23`).
- **Login**: con correo inexistente, verificar contra un hash ficticio para igualar tiempos (BE-01).
- **`EMAIL_TAKEN` en register**: riesgo de enumeración de correos **aceptado**, mitigado con rate limit (BE-02).
- **Esquemas zod `.strict()`** en todos los cuerpos y queries: una clave extra (`role`, `isActive`, `falseAlarmCount`…) devuelve `400 INVALID_STATE`.
- **Validaciones de entrada**: `lat` −90..90 y `lng` −180..180, finitos.
- **`GET /health`** solo responde `status`.
- **`PUT /users/me/device-token`** (contexto, BE-04): no permitido para `admin`.

**Foto (BE-03)**

- Se sirve por ruta autenticada con la misma autorización que la alerta (o URL firmada de vida corta); nunca como archivo estático público ni con token en el query.
- `photo_key` es un UUID generado por el servidor.
- MIME validado por firma de bytes y tamaño máximo.
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

**Decisiones de diseño aún abiertas**

- Nombre de la variable del intervalo de `: ping` del SSE (BE-03).
- Valores por defecto de la ventana de gracia del refresh (D25) y del máximo de conexiones SSE por usuario (D26; al superarlo se cierra la más antigua).
- Agregar `TRIGGERED_AT_TOLERANCE_SECONDS` (600) a `backend/src/config/env.ts` (D24).
