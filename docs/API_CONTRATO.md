# SafeLink — Contrato de la API

**Historias que cubre:** U-01 a U-09, G-01 a G-07, A-01 a A-08.
**Tarjeta:** BE-01 (paso 2, definición del contrato). Cada ruta indica la tarjeta que la implementa (BE-01 a BE-07).
**Fecha:** 2026-11-10.

Este documento se extrajo del **código del front** (fuente de verdad) y se verificó leyendo cada archivo. Cada elemento lleva su evidencia `archivo:línea`. Las rutas de archivo son relativas a `lib/` (`datos/…`, `dominio/…`). Los ejemplos de JSON se construyeron con los campos reales de `datos/nube_mapeadores.dart` y con valores de `datos/datos_semilla.dart`; en el backend los IDs serán UUID (ver D10 en `docs/DECISIONES.md`).

Si algo de aquí contradice a `docs/context_desarrollo_actualizado.md`, gana el front. Las diferencias están en `docs/DECISIONES.md` (D6).

Marcas usadas: **(front)** = existe tal cual en el código del front. **(decidido)** = decisión del equipo registrada en `docs/DECISIONES.md`. Todo lo que el front no define y se documenta aquí ya fue decidido; no queda nada marcado como propuesto. **(EXCEPCIÓN)** = se aparta a propósito de la regla "no inventar rutas ni códigos".

---

## 1. Convenciones

| Tema | Regla | Evidencia |
|---|---|---|
| Formato | JSON en `camelCase` | `nube_mapeadores.dart:58-240` |
| Base URL | **(decidido, D20)** El servidor monta todas las rutas bajo `/api/v1`. Las rutas de este documento (y las del front, p. ej. `/auth/login`) son **relativas a esa base**; la app usará `API_URL=http://host:3000/api/v1` (D4). Los canales SSE viven en `/api/v1/events/<canal>` | `safelink_service.dart:125` |
| Ruta de infraestructura | `GET /health` → `{ "data": { "status": "ok" } }`, pública, **fuera del prefijo** (no es `/api/v1/health`); no pertenece al front (BE-01, ya existe) | `backend/src/routes/health.ts:4` |
| Autenticación | Header `Authorization: Bearer <accessToken>`. Todas las rutas lo exigen, excepto `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh` y `GET /health` | decidido (D7, D8) |
| Fechas | ISO 8601 en UTC con `Z` en respuestas (`2026-11-10T18:17:00.000Z`) | `nube_mapeadores.dart:48-49` |
| Fechas que envía el front | `triggeredAt` va en UTC (`toUtc()`). Los filtros `from`/`to` **no**: son `DateTime` locales sin `Z`. **(decidido, D21)** El backend acepta ISO 8601 con o sin offset; sin offset se interpreta en `TZ_SHIFTS` (`America/Mexico_City`). Las respuestas siempre van en UTC con `Z` | `presentacion/usuario/inicio_view_model.dart:113`, `presentacion/usuario/disparo_rapido.dart:74`, `presentacion/admin/historial_view_model.dart:74-75`, `nube_mapeadores.dart:226-227` |
| IDs | UUID como string | decidido (D10) |
| Unidades | Distancias en metros, tiempos en segundos, rumbo (`heading`) entero 0–359 (0 = norte) | `regla_geocerca.dart:59` |
| Enteros | El front castea con `as int?`: estos campos deben viajar como entero JSON (sin `.0`): `heading`, `etaSeconds`, `coverageRadiusMeters`, `radiusMeters`, `falseAlarmCount`, `totalAlerts`, `alertsByHour[]`, `alertsByZone[].count`, `attendedCount`, `escalatedCount`. Cuidado con `COUNT(*)` de Postgres/Prisma (`bigint`): convertir a número | `nube_mapeadores.dart:67,92,130,138,185-192,209-212` |
| Coordenadas | `{ "lat": number, "lng": number }` (acepta entero o decimal) | `nube_mapeadores.dart:52-53` |
| Claves desconocidas | Los mapeadores del front ignoran claves que no conocen. Por eso se pueden agregar campos extra (p. ej. `accessToken`) sin romperlos | `nube_mapeadores.dart:59-70` |
| Valores de enum desconocidos | El front **falla** (excepción) si recibe un código de enum que no conoce. El backend solo debe emitir los códigos de la sección 3 | `nube_mapeadores.dart:43` |
| Decisión por código HTTP | El front **no** usa el estado HTTP; decide por `error.code`. Aun así el backend usa los estados de la sección 2 | `nube_mapeadores.dart:270-274` |
| Éxito | 200 en general. **201** en los POST que crean recurso: `POST /auth/register`, `POST /alerts`, `POST /admin/guards` **(decidido, D22)** | — |
| Idioma | `message` en español (México). Campos, rutas y códigos en inglés | — |

### Cuerpos mal formados

En el mock, un campo obligatorio ausente (`c['email']!`) o un código de enum desconocido (`CodigosJson.desde`) revienta con una excepción que **no** es un `ErrorDominio` (`safelink_service.dart:129,165`, `nube_mapeadores.dart:43`). En el backend eso se responde con `400 INVALID_STATE` y un mensaje en español (D9). También responden `400 INVALID_STATE` el JSON malformado, el `content-type` no soportado y un cuerpo mayor a `BODY_LIMIT_BYTES` (1 MiB por defecto, máximo 10 MiB; **no** 413). Una violación de unicidad que no capture la lógica de negocio responde `409 INVALID_STATE` genérico; los servicios deben lanzar el código específico (p. ej. `EMAIL_TAKEN`) antes de llegar ahí. Una URL mal codificada o un parámetro de ruta demasiado largo responden `404 NOT_FOUND`. Los mensajes de validación nunca repiten valores ni claves arbitrarias enviadas por el cliente.

---

## 2. Envoltorio y errores

Toda respuesta es `{ "data": ... }` o `{ "error": { ... } }` (`nube_mapeadores.dart:267-275`, `safelink_service.dart:110-112`).

```json
{ "data": { "id": "usr-1", "name": "Fernanda Morales Gil" } }
```

```json
{ "data": null }
```

Las acciones sin resultado devuelven `{ "data": null }` (`safelink_service.dart:146,177,197`). `POST /auth/session` también puede devolver `data: null` (ver 5.1).

```json
{ "error": { "code": "INVALID_CREDENTIALS", "message": "Correo o contraseña incorrectos" } }
```

### remainingMeters

Solo aparece en `OUTSIDE_GEOFENCE`. Es la distancia que falta para entrar a la geocerca (`distancia − GEOFENCE_METERS`, mínimo 0, redondeada a 1 decimal). Es **`null`** cuando no se puede calcular (el guardia no tiene última ubicación o la alerta no tiene ubicación): el front lo envía como infinito y el mapeador lo serializa `null`, y al leerlo `null` vuelve a infinito (`nube_mapeadores.dart:247,257`, `memoria_alerta_guardia_repository.dart:90-92`).

```json
{ "error": { "code": "OUTSIDE_GEOFENCE", "message": "Aún no estás en el punto de la alerta", "remainingMeters": 132.4 } }
```

El `message` de `OUTSIDE_GEOFENCE` es siempre ese (aunque falte la ubicación): el mensaje alterno `Aún no tenemos tu ubicación` de `regla_geocerca.dart:32` se descarta en `memoria_alerta_guardia_repository.dart:89-93`.

### Tabla de códigos de error

| Código | HTTP | Mensaje exacto (español) | Cuándo | Evidencia |
|---|---|---|---|---|
| `INVALID_CREDENTIALS` | 401 | `Correo o contraseña incorrectos` | Login con correo inexistente, contraseña incorrecta o usuario con `isActive = false` | `errores.dart:18`, `memoria_auth_repository.dart:23` |
| `UNAUTHORIZED` | 401 | `Tu sesión terminó. Vuelve a iniciar sesión.` | Sin token, token inválido o vencido, sesión revocada (`sid`, D25), refresh inválido, usuario dado de baja. **Excepción:** en `POST /auth/session` solo falta de token, firma o algoritmo inválidos o token vencido dan 401; sesión revocada, usuario inactivo o `userId ≠ sub` dan `200` con `data: null` (D7, D25) | `errores.dart:47` |
| `USER_BLOCKED` | 403 | `Tu cuenta está bloqueada temporalmente` | **Crear una alerta** estando bloqueado (no al iniciar sesión) | `errores.dart:26`, `memoria_alerta_usuario_repository.dart:23` |
| `FORBIDDEN` **(EXCEPCIÓN, código nuevo)** | 403 | `No tienes permiso para realizar esta acción.` | Rol no permitido para la ruta o canal | decidido (D9) |
| `TOO_MANY_REQUESTS` **(EXCEPCIÓN, código nuevo)** | 429 | `Demasiados intentos. Espera un momento e intenta de nuevo.` | Demasiados intentos por IP en `POST /auth/login` o `/auth/refresh`; incluye cabecera `Retry-After` | decidido (D29) |
| `NOT_FOUND` | 404 | Ver abajo | Recurso inexistente **o ajeno** (no se revela que existe); ruta inexistente | `errores.dart:43` |
| `EMAIL_TAKEN` | 409 | `Ese correo ya está registrado` | Registro, alta de guardia o edición de guardia con correo ya usado | `errores.dart:22`, `memoria_admin_repository.dart:40,67` |
| `ALERT_TAKEN` | 409 | `Otro guardia ya aceptó esta alerta` | Aceptar una alerta que ya no está en `searching` | `errores.dart:30`, `regla_alerta.dart:31` |
| `INVALID_STATE` (transición) | 409 | Ver abajo | La acción no es válida para el estado actual de la alerta | `errores.dart:39` |
| `INVALID_STATE` (validación) | 400 | Ver abajo | Cuerpo o query inválidos; rechazos de validación del admin | `memoria_admin_repository.dart:42,98,121` |
| `OUTSIDE_GEOFENCE` | 422 | `Aún no estás en el punto de la alerta` (+ `remainingMeters`) | Marcar llegada fuera del radio | `errores.dart:34` |
| `SERVICE_UNAVAILABLE` | 503 | `No pudimos conectar con el servidor. Intenta de nuevo.` | Servicio no disponible (base de datos caída, etc.) | `errores.dart:52` |
| `SERVICE_UNAVAILABLE` | 500 | `No pudimos conectar con el servidor. Intenta de nuevo.` | Error inesperado del servidor (sin filtrar detalles) | decidido (D9) |

**Mensajes de `INVALID_STATE` que ya existen en el front** (el front muestra el `message` que llegue):

| Caso | Mensaje | HTTP | Evidencia |
|---|---|---|---|
| Confirmar sin que el guardia haya llegado | `Solo puedes confirmar cuando el guardia ya llegó` | 409 | `regla_alerta.dart:37` |
| Resolver una alerta que no está escalada | `Esta alerta ya no está escalada` | 409 | `regla_alerta.dart:58` |
| Nota vacía al resolver | `Escribe una nota administrativa para resolver la alerta` | 400 | `regla_alerta.dart:65` |
| Nota de más de 300 caracteres | `La nota no puede pasar de 300 caracteres` | 400 | `regla_alerta.dart:66` |
| Contraseña vacía / corta / sin número (alta de guardia) | `Escribe tu contraseña` / `Mínimo 8 caracteres` / `Incluye al menos un número` | 400 | `regla_registro.dart:33-36`, `memoria_admin_repository.dart:41-42` |
| Turno con formato inválido | `Usa el formato HH:mm` | 400 | `regla_turno.dart:31` |
| Radio de cobertura fuera de rango | `El radio mínimo es de 500 m` / `El radio máximo es de 10000 m` | 400 | `regla_geocerca.dart:43-44` |
| Zona vacía | `Escribe la zona de cobertura` | 400 | `regla_geocerca.dart:50` |

Los valores 300, 500 y 10000 salen de configuración, no del código (`ADMIN_NOTE_MAX_LENGTH`, `COVERAGE_RADIUS_MIN_METERS`, `COVERAGE_RADIUS_MAX_METERS`).

Para el registro y la edición de guardia (nombre, correo, teléfono) el mock no valida nada (lo hace el formulario, `presentacion/admin/editar_guardia_view_model.dart:46-48`); el backend debe repetir las reglas de `regla_registro.dart` con sus mismos mensajes (`Escribe tu nombre`, `Escribe tu nombre completo`, `Correo no válido`, `Debe tener 10 dígitos`, líneas 14-29) y responder `400 INVALID_STATE`.

**Mensajes de `NOT_FOUND`:** `La alerta ya no existe` (`memoria_base_datos.dart:79`), `No encontramos a ese guardia` (`memoria_base_datos.dart:92`), `No encontramos lo que buscabas` (por defecto, `errores.dart:43`) y, para una ruta que no existe, `<MÉTODO> <ruta> no existe` (p. ej. `GET /foo no existe`, `safelink_service.dart:115`). El mensaje refleja **solo el path**, sin query string y truncado a 100 caracteres con `…` (no se devuelven datos del cliente). Canal en tiempo real desconocido: `Canal desconocido` (`safelink_service.dart:88`).

### Cómo interpreta el front cada código

Para `INVALID_CREDENTIALS`, `EMAIL_TAKEN`, `USER_BLOCKED`, `ALERT_TAKEN`, `OUTSIDE_GEOFENCE`, `UNAUTHORIZED` y `SERVICE_UNAVAILABLE` el front **ignora el `message` del servidor** y usa el suyo. Solo `INVALID_STATE` y `NOT_FOUND` muestran el `message` recibido. Un código desconocido (como `FORBIDDEN` o `TOO_MANY_REQUESTS`) se convierte en un `ErrorDominio` genérico que muestra el `message` tal cual (`nube_mapeadores.dart:250-263`). Si falta `message`, el front usa `Ocurrió un error` (línea 251).

---

## 3. Enums

Todos en `nube_mapeadores.dart:12-46`.

| Enum | Valores (código en la API) | Evidencia |
|---|---|---|
| `role` | `protected_user`, `guard`, `admin` | `:13-17` |
| `status` (`AlertStatus`) | `pending_location`, `searching`, `in_progress`, `guard_arrived`, `closed`, `no_response`, `escalated`, `resolved_by_admin` | `:18-27` |
| `triggerMethod` | `tap`, `hold`, `shake` | `:28-32` |
| `escalationReason` | `no_response`, `no_confirmation` | `:33-36` |
| `resolution` | `resolved`, `false_alarm`, `service_incident` | `:37-41` |

**`shake` = doble clic de volumen.** El código de la API sigue siendo `shake`, pero en la app el método se llama "Doble clic de volumen" (`enums.dart:41`) y el ajuste del usuario es `volumeDoubleClickEnabled` (`nube_mapeadores.dart:66,79`), **no** `shakeEnabled`. Una alerta con `shake` es **urgente** (`alerta.dart:58`).

**Estados activos:** `pending_location`, `searching`, `in_progress`, `guard_arrived` (`enums.dart:32`). **Terminales:** `closed`, `resolved_by_admin` (`enums.dart:35`). `no_response` y `escalated` no son ni activos ni terminales: por eso, cuando una alerta se escala, deja de ser la "alerta activa" del usuario y el canal `alerts/active` emite `null`.

Estados y transiciones: ver `docs/MODELO_DATOS.md` y la decisión D14 (hay una inconsistencia documentada).

---

## 4. Formas JSON

### 4.1 User

`nube_mapeadores.dart:58-84`. Campos obligatorios al leer: `id`, `name`, `email`, `phone`, `role`, `createdAt`. Los demás tienen valor por defecto.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | string (UUID) | |
| `name` | string | |
| `email` | string | Único, guardado en minúsculas |
| `phone` | string | 10 dígitos |
| `role` | enum `role` | |
| `isActive` | boolean | `false` = guardia dado de baja. Defecto al leer: `true` |
| `volumeDoubleClickEnabled` | boolean | Solo relevante para `protected_user`. Defecto: `false` |
| `falseAlarmCount` | integer | Solo `protected_user`. Defecto: `0` |
| `blockedUntil` | string ISO o `null` | `null` = no bloqueado |
| `createdAt` | string ISO | |

```json
{
  "id": "usr-1",
  "name": "Fernanda Morales Gil",
  "email": "usuario@safelink.mx",
  "phone": "7771234567",
  "role": "protected_user",
  "isActive": true,
  "volumeDoubleClickEnabled": true,
  "falseAlarmCount": 0,
  "blockedUntil": null,
  "createdAt": "2026-08-12T15:00:00.000Z"
}
```

**User con tokens (solo en `POST /auth/login`, `POST /auth/register` y `POST /auth/refresh`)** (decidido, D7/D8). Se agregan dos campos extra al mismo objeto, que el mapeador del front ignora:

```json
{
  "data": {
    "id": "usr-1",
    "name": "Fernanda Morales Gil",
    "email": "usuario@safelink.mx",
    "phone": "7771234567",
    "role": "protected_user",
    "isActive": true,
    "volumeDoubleClickEnabled": true,
    "falseAlarmCount": 0,
    "blockedUntil": null,
    "createdAt": "2026-08-12T15:00:00.000Z",
    "accessToken": "<jwt>",
    "refreshToken": "<token opaco>"
  }
}
```

Ninguna otra ruta devuelve `accessToken` ni `refreshToken`. Nunca se devuelve la contraseña ni su hash.

### 4.2 GuardProfile

`nube_mapeadores.dart:86-108`. Obligatorios al leer: `userId`, `shiftStart`, `shiftEnd`.

| Campo | Tipo | Notas |
|---|---|---|
| `userId` | string | |
| `shiftStart`, `shiftEnd` | string `"HH:mm"` | Regex `^([01]\d\|2[0-3]):[0-5]\d$` (`regla_turno.dart:8`). Puede cruzar medianoche; inicio = fin significa turno de 24 h; el turno es `[inicio, fin)` (`regla_turno.dart:19-27`) |
| `coverageCenter` | `{lat,lng}` o `null` | `null` hasta que el admin define la cobertura |
| `coverageRadiusMeters` | integer o `null` | Idem |
| `zone` | string o `null` | Nombre de la zona |
| `lastLocation` | `{lat,lng}` o `null` | Última ubicación enviada con `PUT /guard/location` |
| `lastLocationAt` | string ISO o `null` | La asigna el servidor |

### 4.3 Guard

`nube_mapeadores.dart:110-115`. Un guardia viaja siempre como `{ "user": User, "profile": GuardProfile }`.

```json
{
  "user": {
    "id": "grd-1",
    "name": "Carlos Hernández López",
    "email": "guardia@safelink.mx",
    "phone": "7772345610",
    "role": "guard",
    "isActive": true,
    "volumeDoubleClickEnabled": false,
    "falseAlarmCount": 0,
    "blockedUntil": null,
    "createdAt": "2026-08-12T15:00:00.000Z"
  },
  "profile": {
    "userId": "grd-1",
    "shiftStart": "08:00",
    "shiftEnd": "16:00",
    "coverageCenter": { "lat": 18.84, "lng": -99.18 },
    "coverageRadiusMeters": 4000,
    "zone": "Emiliano Zapata",
    "lastLocation": { "lat": 18.8385, "lng": -99.1835 },
    "lastLocationAt": "2026-11-10T17:55:00.000Z"
  }
}
```

(Centro, radio, zona y última ubicación: `datos_semilla.dart:57,76,185`.)

**Disponible** = `isActive` + cobertura definida (centro y radio > 0) + turno vigente a la hora actual (`guardia.dart:66`, `guardia.dart:35`). La hora se evalúa en `TZ_SHIFTS` (D12).

### 4.4 Alert

`nube_mapeadores.dart:117-165`. Obligatorios al leer: `id`, `userId`, `status`, `triggerMethod`, `triggeredAt`. El backend siempre envía **todas** las claves (con `null` si no aplican), como hace `aJson` (líneas 141-162).

| Campo | Tipo | Calculado | Notas |
|---|---|---|---|
| `id` | string | | |
| `userId` | string | | Dueño de la alerta |
| `userName` | string o `null` | **sí** | `users.name` del dueño |
| `userPhone` | string o `null` | **sí** | `users.phone` del dueño. **Minimización (D23):** para el rol `guard` es `null` salvo para el guardia **asignado** mientras la alerta esté activa; en `/guard/history` siempre `null`; en `guard/alerts` (aún sin asignar) siempre `null`. El dueño y el admin lo ven completo |
| `guardId` | string o `null` | | Guardia asignado |
| `guardName` | string o `null` | **sí** | `users.name` del guardia |
| `status` | enum `status` | | |
| `triggerMethod` | enum `triggerMethod` | | |
| `photoUrl` | string o `null` | **sí** | Se calcula desde `alerts.photo_key` con `PhotoStorage.url(key)` (D2); `null` si no hay foto. El guardia asignado la conserva aunque la alerta ya no esté activa (D23); el admin la ve siempre |
| `evidenceIncomplete` | boolean | | `true` si no hay foto (`memoria_alerta_usuario_repository.dart:37`) |
| `location` | `{lat,lng}` o `null` | | GPS del disparo; se actualiza con `POST /alerts/:id/locations`. Para el rol `guard` es `null` cuando la alerta ya no está activa (D23); el admin la ve siempre |
| `heading` | integer o `null` | | 0–359 |
| `triggeredAt` | string ISO | | La manda el dispositivo; solo se guarda y se devuelve (D24). Se valida: ISO válido y dentro de ±`TRIGGERED_AT_TOLERANCE_SECONDS` (600 por defecto) respecto a la hora del servidor; fuera de la ventana se **recorta a `received_at`** (no se rechaza, para no perder una alerta real por un reloj desfasado). El servidor guarda además `received_at` (hora al recibir `POST /alerts`), **interna y no expuesta** en el JSON: `waitingMinutes`, `score`, temporizadores, métricas, `alertsByHour`, filtros `from`/`to` y el orden de escaladas la usan |
| `acceptedAt` | string ISO o `null` | | Lo asigna el servidor al aceptar |
| `arrivedAt` | string ISO o `null` | | Lo asigna el servidor al marcar llegada |
| `closedAt` | string ISO o `null` | | Se asigna al confirmar el usuario **y** al resolver el admin (`memoria_alerta_usuario_repository.dart:68`, `memoria_admin_repository.dart:123`). Escalar **no** la asigna |
| `escalationReason` | enum o `null` | | Se conserva después de resolver (`alt-304` en `datos_semilla.dart:291`) |
| `resolution` | enum o `null` | | |
| `adminNote` | string o `null` | | Se guarda recortada (`trim`) |
| `etaSeconds` | integer o `null` | **sí** | **Calculado en cada lectura, sin columna (D27, BE-04).** Solo con la alerta `in_progress`: distancia Haversine entre `guardia.lastLocation` y `alerta.location`, entre `GUARD_METERS_PER_MINUTE`, en segundos enteros, nunca negativo (`regla_eta.dart:10-13`). `null` si falta alguna de las dos ubicaciones o la alerta no está `in_progress`. En el mock `aceptarAlerta` no lo llena (`memoria_alerta_guardia_repository.dart:60-65`): solo la simulación lo pone y lo baja hasta 0 al llegar (`memoria_base_datos.dart:121-129,148,153`) |

**Calculados** (no son columnas de `alerts`): `userName`, `userPhone`, `guardName`, `etaSeconds`, `photoUrl` (`alerta.dart:3-4`, aunque ese comentario solo menciona tres).

```json
{
  "id": "alt-101",
  "userId": "usr-1",
  "userName": "Fernanda Morales Gil",
  "userPhone": "7771234567",
  "guardId": "grd-1",
  "guardName": "Carlos Hernández López",
  "status": "in_progress",
  "triggerMethod": "shake",
  "photoUrl": "https://picsum.photos/seed/sl101/640/420",
  "evidenceIncomplete": false,
  "location": { "lat": 18.8452, "lng": -99.1771 },
  "heading": 75,
  "triggeredAt": "2026-11-10T17:50:00.000Z",
  "acceptedAt": "2026-11-10T17:51:10.000Z",
  "arrivedAt": null,
  "closedAt": null,
  "escalationReason": null,
  "resolution": null,
  "adminNote": null,
  "etaSeconds": 240
}
```

(Ilustrativo: ubicación `datos_semilla.dart:83`, formato de `photoUrl` `datos_semilla.dart:201`. En el backend `photoUrl` será una URL de este servidor; ver sección 8.)

### 4.5 PrioritizedAlert

`nube_mapeadores.dart:167-181`. Es cada elemento del canal `guard/alerts`.

| Campo | Tipo | Notas |
|---|---|---|
| `alert` | Alert | |
| `distanceMeters` | number | Haversine entre la última ubicación del guardia (o el centro de su cobertura) y la alerta (`memoria_alerta_guardia_repository.dart:38`, `regla_prioridad.dart:28`) |
| `waitingMinutes` | number | Segundos transcurridos / 60. El front usa `triggeredAt` (`regla_prioridad.dart:29`); el backend usa `received_at`, la hora del servidor (D24), para que el reloj del teléfono no altere la prioridad |
| `score` | number | `distanceMeters − waitingMinutes × WAIT_METERS_PER_MINUTE` (`regla_prioridad.dart:30`) |

Orden de la lista: primero las urgentes (`shake`), luego `score` ascendente (`regla_prioridad.dart:33-36`).

```json
{
  "alert": { "id": "alt-101", "status": "searching", "triggerMethod": "shake", "...": "(Alert completa)" },
  "distanceMeters": 850.0,
  "waitingMinutes": 2.5,
  "score": 600.0
}
```

### 4.6 GeneralMetrics

`nube_mapeadores.dart:183-205`, cálculo en `regla_metricas.dart:16-40`.

| Campo | Tipo | Cálculo |
|---|---|---|
| `totalAlerts` | integer | Alertas del periodo |
| `avgAcceptanceSeconds` | number | Promedio de `acceptedAt − receivedAt` (solo alertas con `acceptedAt`). El front usa `triggeredAt` (`regla_metricas.dart:33`); el backend usa `receivedAt` (D24) |
| `avgArrivalSeconds` | number | Promedio de `arrivedAt − (acceptedAt ?? receivedAt)` (solo alertas con `arrivedAt`; `regla_metricas.dart:34`) |
| `noResponseRate` | number 0–1 | Alertas con `escalationReason = no_response` ÷ total |
| `confirmedCloseRate` | number 0–1 | Alertas con `status = closed` ÷ total |
| `alertsByHour` | integer[24] | Por hora de `receivedAt` en `TZ_SHIFTS` (el front usa la hora local de `triggeredAt` en el dispositivo, `regla_metricas.dart:22`; ver D12, D24) |
| `alertsByZone` | `[{ "zone": string, "count": integer }]` | Zona del guardia asignado; sin guardia o sin zona: `Sin zona asignada` (`regla_metricas.dart:13`); orden: más alertas primero, luego por nombre |

Con cero alertas todo vale 0 y las listas van vacías en `alertsByZone`; `alertsByHour` sigue siendo 24 ceros (`metricas.dart:37-45`).

```json
{
  "totalAlerts": 12,
  "avgAcceptanceSeconds": 95.5,
  "avgArrivalSeconds": 410.0,
  "noResponseRate": 0.0833,
  "confirmedCloseRate": 0.75,
  "alertsByHour": [0,0,0,0,0,0,0,0,1,2,1,0,0,1,2,1,0,0,1,1,1,1,0,0],
  "alertsByZone": [ { "zone": "Emiliano Zapata", "count": 7 }, { "zone": "Sin zona asignada", "count": 1 } ]
}
```

### 4.7 GuardMetrics

`nube_mapeadores.dart:207-221`, cálculo en `regla_metricas.dart:42-50`.

| Campo | Tipo | Cálculo |
|---|---|---|
| `attendedCount` | integer | Alertas del guardia con `arrivedAt` |
| `avgAcceptanceSeconds` | number | `acceptedAt − receivedAt`, solo alertas del guardia (D24) |
| `avgArrivalSeconds` | number | `arrivedAt − (acceptedAt ?? receivedAt)`, solo alertas del guardia (D24) |
| `escalatedCount` | integer | Alertas del guardia con `escalationReason` |

```json
{ "attendedCount": 9, "avgAcceptanceSeconds": 80.0, "avgArrivalSeconds": 395.5, "escalatedCount": 1 }
```

### 4.8 Filtro de historial (query string)

`nube_mapeadores.dart:223-240`, regla en `filtro_historial.dart:10-29`. Todos opcionales y combinables:

| Parámetro | Valor | Regla |
|---|---|---|
| `from` | ISO 8601 | `receivedAt >= from` (inclusivo); el front compara `triggeredAt` (`filtro_historial.dart:20`), el backend `receivedAt` (D24). Solo en rutas del admin (historial, métricas generales y por guardia) |
| `to` | ISO 8601 | `receivedAt < to` (exclusivo). El front manda el día siguiente a la fecha elegida (`presentacion/admin/historial_view_model.dart:38`) |
| `guardId` | id | |
| `userId` | id | |
| `status` | código de `status` | |

Resultado siempre ordenado por fecha de recepción (`receivedAt`) descendente (el front ordena por `triggeredAt`, `filtro_historial.dart:28`). Un `status` desconocido en el mock revienta; en el backend es `400 INVALID_STATE`.

---

## 5. Rutas (31 del front + 1 excepción)

Todas las rutas son relativas a `/api/v1` (D20).

Columnas: **Rol** = quién puede llamarla (el resto recibe `403 FORBIDDEN`). **Req.** = cuerpo o query que manda el front. **Tarjeta** = quién la implementa (BE-06/BE-07 son **tentativas**).

**Errores comunes a todas las rutas autenticadas** (no se repiten en cada fila): `401 UNAUTHORIZED` (sin token, vencido, sesión revocada o usuario dado de baja; `authenticate` relee `is_active` y rechaza un `sid` revocado en la misma consulta, D25; **excepción:** `POST /auth/session` usa verificación propia y devuelve `200` con `data: null` para sesión revocada o usuario inactivo), `403 FORBIDDEN` (rol no permitido), `400 INVALID_STATE` (cuerpo o query inválidos), `500`/`503 SERVICE_UNAVAILABLE`.

### 5.1 Sesión y cuenta

Evidencia de las rutas: `safelink_service.dart:124-157`. Cliente: `nube_auth_repository.dart`.

| Método | Ruta | Rol | Req. | `data` | Errores propios | Historia | Tarjeta |
|---|---|---|---|---|---|---|---|
| POST | `/auth/login` (`:125-131`) | público | `{ "email", "password" }` (`.strict()`; `email` recortado, en minúsculas, 1–254 caracteres; `password` 1–128) | User + `accessToken` + `refreshToken` | `INVALID_CREDENTIALS` (correo inexistente, contraseña mala o `isActive=false`; el correo se compara sin mayúsculas ni espacios, `memoria_auth_repository.dart:16-17`); `TOO_MANY_REQUESTS` (429) | U-02, G-01 | BE-01 (implementado) |
| POST | `/auth/register` (`:132-143`) | público | `{ "name", "email", "phone", "password" }` | User + tokens (queda con sesión abierta) | `EMAIL_TAKEN`; `INVALID_STATE` (validación). Siempre crea `protected_user` (`auth_repository.dart:16`) | U-01 | BE-02 |
| POST | `/auth/refresh` **(EXCEPCIÓN: no existe en el front)** | público (usa el refresh token) | `{ "refreshToken" }` (`.strict()`; hasta 512 caracteres) | User + `accessToken` + `refreshToken` nuevos (rotación) | `UNAUTHORIZED` (forma inválida, desconocido, vencido, sesión sobre su vida máxima, reutilizado, revocado, usuario inactivo); `TOO_MANY_REQUESTS` (429) | U-02, G-01 | BE-01 (implementado; la app lo usa desde BE-02) |
| POST | `/auth/logout` (`:144-147`) | autenticado (cualquier rol) | sin cuerpo | `null` | — | U-02 | BE-01 (implementado) |
| GET | `/auth/me` (`:148`) | autenticado (cualquier rol) | — | User actualizado (bloqueo, falsas alarmas) | — | U-02, G-01 | BE-01 (implementado) |
| POST | `/auth/session` (`:149-152`) | Bearer, con **verificación propia** (no el hook general) | `{ "userId" }` (`.strict()`; texto de hasta 100 caracteres) | User, o `null` | `401 UNAUTHORIZED` solo si falta el token, la firma o el algoritmo no son válidos, o venció. `200` con `data: null` si el `sid` está revocado, el usuario está inactivo o `userId ≠ sub` (también si `userId` no es un UUID) | U-02 | BE-01 (implementado) |
| PATCH | `/users/me/settings` (`:153-157`) | `protected_user` | `{ "volumeDoubleClickEnabled": boolean }` | User actualizado | — | U-05 | BE-02 |

Notas:

- `POST /auth/logout`: el front no manda cuerpo (`nube_auth_repository.dart:42`). El backend identifica la sesión por el claim `sid` del access token, revoca esa familia de refresh tokens y cierra sus streams SSE abiertos (D8, D25).
- El access JWT lleva `sub`, `role` y `sid` (id de la familia en `refresh_tokens`), firmado con HS256 (D25). Un `sid` revocado devuelve `401` de inmediato, sin esperar a que venza el token.
- `POST /auth/refresh` (implementado, D25): el refresh es opaco (32 bytes de CSPRNG en base64url); en la base solo se guarda su SHA-256. Rotación en cada uso: el token presentado queda usado y se emite un sucesor. **Ventana de gracia** (`REFRESH_GRACE_SECONDS`, 0–60, default 5; 0 la desactiva): un token ya rotado, presentado dentro de la ventana, se acepta **una vez más** y emite un sucesor **nuevo** de la misma familia, sin revocarla (dentro de la gracia pueden coexistir dos sucesores vivos). Fuera de la ventana, o con la gracia ya consumida, es reutilización: se revoca **toda la familia** y se responde `401 UNAUTHORIZED`. Si el token rotado tenía un hermano de gracia sin usar, ese hermano se revoca. Cada sucesor vence a `min(now + JWT_REFRESH_EXPIRES_IN, inicio de la sesión + JWT_SESSION_MAX_AGE)` (vigencia deslizante con vida máxima absoluta, 90d por defecto); un refresh vencido o de una sesión que superó la vida máxima da `401` sin revocar la familia. Un `refreshToken` con forma inválida (no es base64url de 43 caracteres) da `401` sin consultar la base.
- **Rate limit (D29):** `POST /auth/login` (10 por minuto) y `POST /auth/refresh` (30 por minuto), por IP, configurables; cuenta todos los intentos. Al excederse: `429` con `TOO_MANY_REQUESTS` y cabecera `Retry-After` (sin `X-RateLimit-*`). `POST /auth/register` se suma en BE-02.
- **Cache-Control:** todas las respuestas bajo `/api/v1` llevan `Cache-Control: no-store`.
- `POST /auth/login` (implementado): el `email` se normaliza (recorte y minúsculas) antes de buscarlo. Con correo inexistente verifica la contraseña contra un hash ficticio, y con usuario inactivo contra su hash real, para igualar tiempos; los tres casos de fallo (correo, contraseña, inactivo) dan el mismo `INVALID_CREDENTIALS`. Cualquier clave extra en el cuerpo da `400 INVALID_STATE`.
- Respuesta de login y refresh: el `User` del front (4.1) más `accessToken` y `refreshToken`, serializado campo por campo (nunca incluye el hash de la contraseña).
- Tras `authenticate` (`logout`, `me`), el rol de la petición sale de la base, no del claim del token.
- `POST /auth/register` con `EMAIL_TAKEN` permite enumerar correos: **riesgo aceptado**, mitigado con rate limit (BE-02).
- `POST /auth/session`: el front lo usa al abrir la app con el `userId` guardado en el dispositivo (`sesion_view_model.dart:37-39`, `sesion_guardada.dart:9`). Hoy no manda token: **hueco de seguridad del mock** (`nube_auth_repository.dart:51`, D7). Con el backend exige `Authorization: Bearer` y usa **verificación propia** del token (no el hook `authenticate` general): `401 UNAUTHORIZED` solo si falta el token, la firma o el algoritmo no son válidos, o venció. Si el `sid` está revocado, el usuario está inactivo o `userId ≠ sub`, devuelve `200` con `data: null`, porque `restaurar()` maneja `null` borrando la sesión guardada (`sesion_view_model.dart:41-44`) y no maneja excepciones **(decidido, D7, D25)**.
- Un usuario bloqueado **sí** puede iniciar sesión; solo no puede crear alertas (`memoria_auth_repository.dart:20-28`).

### 5.2 Alertas del usuario protegido

Evidencia: `safelink_service.dart:159-180`. Cliente: `nube_alerta_usuario_repository.dart`. Rol de todas: `protected_user`. En las rutas con `:id`, la alerta debe ser **del dueño**; si es de otro usuario o no existe, `404 NOT_FOUND` (`La alerta ya no existe`).

| Método | Ruta | Req. | `data` | Errores propios | Historia | Tarjeta |
|---|---|---|---|---|---|---|
| POST | `/alerts` (`:160-172`) | `{ "triggerMethod", "triggeredAt", "location": {lat,lng}\|null, "heading": int\|null, "photoPath": string\|null }` (`nube_alerta_usuario_repository.dart:22-28`) | Alert | `USER_BLOCKED` (403); `INVALID_STATE` 400 (validación); `INVALID_STATE` 409 si el usuario ya tiene otra alerta activa (D15, D22). Respuesta 201 | U-03, U-04, U-05, U-06 | BE-03 |
| GET | `/alerts/mine` (`:173-174`) | — | Alert[] (todas las del usuario, también las activas, más recientes primero) | — | historial del usuario (extra del front) | BE-03 |
| POST | `/alerts/:id/locations` (`:175-178`) | `{ "location": {lat,lng} }` | `null` | `NOT_FOUND`; `INVALID_STATE` 409 (la alerta ya no está activa). Con rate limit por usuario acorde a `LOCATION_UPDATE_SECONDS` | U-07 | BE-03 |
| POST | `/alerts/:id/confirm` (`:179-180`) | — | Alert (`status=closed`, `closedAt`) | `NOT_FOUND`; `INVALID_STATE` 409 `Solo puedes confirmar cuando el guardia ya llegó` (solo en `guard_arrived` con guardia asignado, `regla_alerta.dart:34-37`) | U-09 | BE-03 |

Comportamiento (front):

- `POST /alerts` con `location: null` crea la alerta en `pending_location`; con ubicación, en `searching` (`memoria_alerta_usuario_repository.dart:31`). `evidenceIncomplete = (photoPath == null)` (`:37`). Hoy `photoPath` es una ruta local del teléfono; ver sección 8 (D2).
- `POST /alerts/:id/locations` sobre una alerta en `pending_location` la pasa a `searching` y le pone esa ubicación; en otros estados solo actualiza `location` (`memoria_alerta_usuario_repository.dart:52-60`). El servidor asigna la hora (`recordedAt`).
- `GET /alerts/mine`: no admite filtros; el front filtra en el cliente (`dominio/filtro_mi_historial.dart:21`). Evidencia del orden: `memoria_alerta_usuario_repository.dart:76`.

### 5.3 Guardia

Evidencia: `safelink_service.dart:182-200`. Cliente: `nube_alerta_guardia_repository.dart`. Rol de todas: `guard`.

| Método | Ruta | Req. | `data` | Errores propios | Historia | Tarjeta |
|---|---|---|---|---|---|---|
| GET | `/guard/me` (`:183`) | — | Guard (`{user, profile}`) | — | G-01 (extra del front) | BE-04 |
| GET | `/guard/history` (`:184-185`) | — | Alert[] con `guardId` del guardia y estado **no activo** (incluye `no_response`; una escalada que nadie aceptó no aparece), más recientes primero (`memoria_alerta_guardia_repository.dart:107`). `userPhone` y `location` siempre `null`; `photoUrl` se conserva (D23) | — | extra del front | BE-04 |
| GET | `/guard/metrics` (`:186-187`) | — | GuardMetrics calculadas sobre la misma lista que `/guard/history` (`memoria_alerta_guardia_repository.dart:109-114`) | — | extra del front | BE-04 |
| PUT | `/guard/location` (`:188-191`) | `{ "location": {lat,lng} }` | `null` (guarda `lastLocation` y `lastLocationAt` = hora del servidor, `memoria_alerta_guardia_repository.dart:77-81`). Rate limit por usuario acorde a `LOCATION_UPDATE_SECONDS`; `lat` −90..90 y `lng` −180..180, finitos | `INVALID_STATE` 400 (coordenadas inválidas) | G-06, G-07 | BE-04 |
| GET | `/guard/alerts/:id` (`:192`) | — | Alert | `NOT_FOUND` si no existe, el `:id` no es un UUID válido **o el guardia no puede verla**. En alertas no activas `location` va `null`; `photoUrl` se conserva (D23) | G-04 | BE-04 |
| POST | `/guard/alerts/:id/accept` (`:193-194`) | — | Alert (`in_progress`, `guardId`, `guardName`, `acceptedAt`, `etaSeconds`) | `NOT_FOUND` 404 si la alerta no es visible para el guardia (visibilidad **sin** la condición de estado); `ALERT_TAKEN` 409 si es visible pero ya no está en `searching`, o si el `UPDATE … WHERE status = 'searching'` afecta 0 filas | G-05 | BE-04 |
| POST | `/guard/alerts/:id/ignore` (`:195-198`) | — | `null` (la alerta deja de aparecer solo para ese guardia) | `NOT_FOUND` | G-03 (extra del front) | BE-04 |
| POST | `/guard/alerts/:id/arrive` (`:199-200`) | — | Alert (`guard_arrived`, `arrivedAt`) | Orden de verificaciones: (1) existencia y propiedad: `NOT_FOUND` 404 si no existe o no es el guardia asignado; (2) estado: `INVALID_STATE` 409 si no está en `in_progress`; (3) geocerca: `OUTSIDE_GEOFENCE` 422 con `remainingMeters`. Un guardia ajeno nunca recibe `remainingMeters` | G-07 | BE-04 |

**Requisitos de propiedad y visibilidad** (el mock no los cumple; ver `docs/DECISIONES.md`, "Pendientes de seguridad"):

- `arrive`: solo el **guardia asignado**. Orden: existencia y propiedad (404) → estado (409 `INVALID_STATE` si no está en `in_progress`) → geocerca (422 con `remainingMeters`). Un guardia ajeno nunca recibe `remainingMeters` **(decidido, D22)**.
- **Visibilidad** (`GET /guard/alerts/:id` y canal `guard/alerts/:id`): el guardia ve una alerta si está **asignada a él**, o si está **disponible para él**: en `searching`, dentro de su cobertura (centro + radio), con turno vigente y no ignorada (`zone` es solo una etiqueta, no filtra). Cualquier otra: `404 NOT_FOUND` **(decidido, D22)**.
- `accept`: evalúa la visibilidad **sin la condición de estado** (cobertura centro + radio, turno vigente, no ignorada). No visible: `404 NOT_FOUND`. Visible y ya no en `searching`: `409 ALERT_TAKEN` (G-05, `docs/HISTORIAS_DE_USUARIO.md:188`, `regla_alerta.dart:31`). La asignación es un solo `UPDATE … WHERE status = 'searching'` atómico; si afecta 0 filas, `409 ALERT_TAKEN` **(decidido, D22)**.
- **Minimización de datos (D23):** antes de aceptar el guardia ve `userName`, `location` y `photoUrl` (G-04), pero `userPhone` es `null`; solo el guardia asignado lo recibe, mientras la alerta esté activa. Cuando la alerta ya no está activa, para el rol `guard` también `location` va `null`, pero `photoUrl` se conserva como evidencia (en `/guard/history` y en `GET /guard/alerts/:id` de alertas no activas, incluidas `no_response` y `escalated`). Aplica a REST y SSE; el admin ve todo.
- La geocerca: `arrive` solo procede si `distancia(lastLocation del guardia, alerta.location) <= GEOFENCE_METERS` (`regla_geocerca.dart:23-24`), con Haversine y radio de la Tierra 6 371 000 m (`regla_geocerca.dart:11`).

### 5.4 Administración

Evidencia: `safelink_service.dart:202-296`. Cliente: `nube_admin_repository.dart`. Rol de todas: `admin`.

| Método | Ruta | Req. | `data` | Errores propios | Historia | Tarjeta (tentativa) |
|---|---|---|---|---|---|---|
| GET | `/admin/guards` (`:203-208`) | query `search` (el front lo manda siempre, aunque vacío, `nube_admin_repository.dart:23`) | Guard[] | — | A-02 | BE-06 |
| POST | `/admin/guards` (`:209-220`) | `{ "name", "email", "phone", "password" }` | Guard (turno `08:00`–`16:00`, sin cobertura, `isActive=true`, `memoria_admin_repository.dart:53-59`) | `EMAIL_TAKEN`; `INVALID_STATE` (contraseña y demás validaciones) | A-01 | BE-06 |
| GET | `/admin/guards/:id` (`:221`) | — | Guard | `NOT_FOUND` `No encontramos a ese guardia` (si el id no existe **o no es rol `guard`**; igual en PATCH, DELETE y `coverage`) | A-02 (extra del front) | BE-06 |
| PATCH | `/admin/guards/:id` (`:222-233`) | `{ "name"?, "email"?, "phone"? }` (solo manda los que cambian, `nube_admin_repository.dart:36-40`; **no** cambia contraseña ni turno) | Guard | `EMAIL_TAKEN`; `NOT_FOUND` | A-02 | BE-06 |
| DELETE | `/admin/guards/:id` (`:234-237`) | — | `null`. **Baja lógica**: `isActive=false`, no borra el registro (`memoria_admin_repository.dart:75-78`) | `NOT_FOUND` | A-02 | BE-06 |
| PUT | `/admin/guards/:id/coverage` (`:238-251`) | `{ "shiftStart", "shiftEnd", "center": {lat,lng}, "radiusMeters": int, "zone": string }` | Guard | `INVALID_STATE` 400 (formato de turno, radio fuera de rango, zona vacía; ver sección 2); `NOT_FOUND` | A-03 | BE-06 |
| POST | `/admin/alerts/:id/resolve` (`:252-262`) | `{ "resolution", "adminNote" }` (nota obligatoria, 1–300 caracteres) | Alert (`resolved_by_admin`, `resolution`, `adminNote`, `closedAt`) | `INVALID_STATE` 409 `Esta alerta ya no está escalada`; `INVALID_STATE` 400 por nota; `NOT_FOUND` | A-04 | BE-05 |
| GET | `/admin/alerts` (`:263-268`) | query de la sección 4.8 | Alert[] (todas, también activas) | `INVALID_STATE` 400 (filtro inválido) | A-05 | BE-07 |
| GET | `/admin/metrics` (`:269-275`) | query `from`, `to` | GeneralMetrics | — | A-06 | BE-07 |
| GET | `/admin/metrics/guards/:id` (`:276-282`) | query `from`, `to` | GuardMetrics | `NOT_FOUND` | A-07 | BE-07 |
| GET | `/admin/users` (`:283-287`) | — | User[] **solo `protected_user`**, ordenados por nombre (`memoria_admin_repository.dart:161-165`) | — | A-08 (extra del front) | BE-07 |
| GET | `/admin/users/blocked` (`:288-292`) | — | User[] con `blockedUntil` en el futuro (`memoria_admin_repository.dart:168-172`) | — | A-08 | BE-07 |
| DELETE | `/admin/users/:id/block` (`:293-296`) | — | `null`. Quita el bloqueo **y pone `falseAlarmCount` en 0** (`memoria_admin_repository.dart:177`) | `NOT_FOUND` (también si el id no es de un `protected_user`) | A-08 | BE-07 |

Comportamiento (front):

- `GET /admin/guards`: busca **solo por nombre**, sin distinguir mayúsculas ni acentos (`memoria_admin_repository.dart:20`, `dominio/texto_busqueda.dart`). Orden: activos primero, luego por nombre (`:25-28`). Incluye guardias dados de baja.
- `resolve`: orden de validación: primero el estado, luego la nota (`memoria_admin_repository.dart:120`). Si `resolution = false_alarm`, el usuario suma 1 a `falseAlarmCount`; si el total ya es `>= FALSE_ALARM_LIMIT`, `blockedUntil = ahora + BLOCK_DAYS` días. Esto se repite en cada falsa alarma posterior, renovando el bloqueo (`regla_alerta.dart:71-82`). Con el total por debajo del límite, el bloqueo existente no se toca. Al resolver se asigna `closedAt` (`memoria_admin_repository.dart:123`).
- Los guardias dados de baja pierden todas sus sesiones y se cierran sus streams SSE (D8, D25).
- **Bloqueante para BE-06 (y BE-05, por D14):** la baja de un guardia con una alerta `in_progress` debe, **en la misma transacción**, devolver la alerta a `searching` o escalarla. El front no define este caso.

### 5.5 Resumen por tarjeta (tentativo)

| Tarjeta | Rutas |
|---|---|
| BE-01 | `/auth/login`, `/auth/me`, `/auth/refresh`, `/auth/logout`, `/auth/session`, `/health` |
| BE-02 | `/auth/register`, `/users/me/settings`, cliente de la app para sesión y registro |
| BE-03 | `/alerts`, `/alerts/mine`, `/alerts/:id/locations`, `/alerts/:id/confirm`, foto, canal `alerts/active` |
| BE-04 | `/guard/*` (8 rutas), canales `guard/alerts` y `guard/alerts/:id` |
| BE-05 | Escalamiento automático, `/admin/alerts/:id/resolve`, canal `admin/alerts/escalated`, bloqueo por falsas alarmas |
| BE-06 (tentativa) | `/admin/guards` (6 rutas) |
| BE-07 (tentativa) | `/admin/alerts`, `/admin/metrics`, `/admin/metrics/guards/:id`, `/admin/users`, `/admin/users/blocked`, `DELETE /admin/users/:id/block` |

Total: 6 (sesión y cuenta del front) + 4 (usuario) + 8 (guardia) + 13 (admin) = **31 rutas** del front, más `POST /auth/refresh`.

---

## 6. Tiempo real

Decisión D3. El front escucha cuatro canales (`safelink_service.dart:76-91`). En el backend cada canal es una ruta SSE bajo `/api/v1/events/` (D20); en la tabla se muestran relativas a `/api/v1`.

| Canal del front | Ruta SSE | Rol | `data` de cada evento | Evidencia | Tarjeta |
|---|---|---|---|---|---|
| `alerts/active` | `GET /events/alerts/active` | `protected_user` | La alerta activa del usuario (a lo más una, D15), o `null` si no tiene (estados `pending_location`, `searching`, `in_progress`, `guard_arrived`) | `safelink_service.dart:79-80`, `memoria_alerta_usuario_repository.dart:46-49` | BE-03 |
| `guard/alerts` | `GET /events/guard/alerts` | `guard` | Lista **completa** de PrioritizedAlert: solo `searching`, con ubicación, dentro de la cobertura del guardia, no ignoradas; **lista vacía** si el guardia no está disponible (fuera de turno, sin cobertura o dado de baja). `userPhone` siempre `null` (D23) | `safelink_service.dart:81-82`, `memoria_alerta_guardia_repository.dart:22-43` | BE-04 |
| `guard/alerts/:id` | `GET /events/guard/alerts/:id` | `guard` | Alert (cada cambio de la alerta). Misma visibilidad que `GET /guard/alerts/:id`; `userPhone` solo para el guardia asignado con la alerta activa (D23) | `safelink_service.dart:78,83-84`, `memoria_alerta_guardia_repository.dart:52` | BE-04 |
| `admin/alerts/escalated` | `GET /events/admin/alerts/escalated` | `admin` | Lista **completa** de Alert en `escalated`, la más antigua primero (por `receivedAt`; el front ordena por `triggeredAt`, `memoria_admin_repository.dart:113`) | `safelink_service.dart:85-86`, `memoria_admin_repository.dart:111-114` | BE-05 |

Reglas del transporte:

- `Content-Type: text/event-stream`. Cada evento: `data: {"data": ...}\n\n`, con el mismo envoltorio que las respuestas REST (`safelink_service.dart:90`).
- **Al conectar** se envía el estado actual como primer evento (snapshot completo). En el mock el stream emite el valor actual al suscribirse (`memoria_base_datos.dart:58-63`). **Cada evento es un snapshot completo, no un delta**: el front reemplaza su estado con lo que llega. Puede haber eventos repetidos con el mismo contenido (el mock emite ante cualquier cambio global); el cliente debe tolerarlo.
- Comentario `: ping\n\n` periódico para mantener viva la conexión. El intervalo es configurable por variable de entorno (nombre por definir en BE-03).
- Errores una vez abierto el stream: `data: {"error":{"code":"...","message":"..."}}\n\n` y se cierra la conexión. Así actúa el mock con un canal desconocido: emite un solo evento de error (`safelink_service.dart:88`). Alerta inexistente en `guard/alerts/:id`: `NOT_FOUND`.
- Autenticación: header `Authorization: Bearer <accessToken>`. **Nunca** el token en el query string (queda en logs y en el historial). Si falta o es inválido el token, o el rol no corresponde, se responde **antes de abrir el stream** con HTTP 401 / 403 y el envoltorio JSON normal **(decidido, D22)**.
- Rol por canal: el usuario solo recibe su alerta; el guardia, solo lo que le corresponde; el admin, solo escaladas. Rol incorrecto: `403 FORBIDDEN`.
- **Visibilidad por guardia, en cada emisión (D22):** en `guard/alerts` y `guard/alerts/:id` la visibilidad se reevalúa **en cada emisión y por guardia** (nunca un snapshot global compartido). Si la alerta de `guard/alerts/:id` deja de ser visible para ese guardia (por ejemplo, otro la aceptó), se emite `data: {"error":{"code":"NOT_FOUND","message":"La alerta ya no existe"}}` y se cierra el stream.
- **Vida del stream (D26):** el servidor cierra el stream al llegar el `exp` del access token; el cliente reconecta con un token renovado. Antes de cerrar por `exp`, `logout` o baja de guardia, el servidor emite `data: {"error":{"code":"UNAUTHORIZED","message":"Tu sesión terminó. Vuelve a iniciar sesión."}}`. Hay un máximo configurable de conexiones SSE por usuario; al superarlo se **cierra la conexión más antigua** (no se rechaza la nueva, para no dejar sin datos a la app que reconecta). Un `logout` o la baja de un guardia cierran sus streams abiertos vía `EventBus` (D25).
- **Requisito del cliente (BE-02 / BE-04):** el `escuchar()` real debe reconectar cuando el stream se cierre, renovando antes el token con `POST /auth/refresh`; no debe exponer la reconexión a los view models como fin de stream, y emite error solo si no puede reconectar. Los view models solo manejan `onError` (`presentacion/usuario/estado_alerta_view_model.dart:34-42`, `presentacion/guardia/navegacion_view_model.dart:63-71`).
- Los snapshots se vuelven a emitir cuando cambian los datos que los componen: estado de alertas, cobertura y turno del guardia, ubicación del guardia (afecta `distanceMeters`) y el paso del tiempo (`waitingMinutes`, inicio y fin de turno). El bus de eventos es en memoria detrás de una interfaz `EventBus` (D3).
- Implementación: BE-03 (usuario), BE-04 (guardia), BE-05 (admin).

Ejemplo de un evento de `guard/alerts`:

```
data: {"data":[{"alert":{"id":"alt-101","status":"searching","triggerMethod":"shake"},"distanceMeters":850.0,"waitingMinutes":2.5,"score":600.0}]}

```

(El ejemplo abrevia la Alert; en el stream va completa.)

Ejemplo cuando el usuario no tiene alerta activa:

```
data: {"data":null}

```

---

## 7. Reglas de negocio visibles en el contrato

| Regla | Valor configurable | Evidencia |
|---|---|---|
| Geocerca para "Llegué" | `GEOFENCE_METERS` (50) | `configuracion.dart:9` |
| Falsas alarmas para bloquear | `FALSE_ALARM_LIMIT` (3) | `configuracion.dart:12` |
| Días de bloqueo | `BLOCK_DAYS` (7) | `configuracion.dart:13` |
| Peso de la espera en el orden | `WAIT_METERS_PER_MINUTE` (100) | `configuracion.dart:15` |
| Velocidad del guardia para el ETA | `GUARD_METERS_PER_MINUTE` (250) | `configuracion.dart:16` |
| Radio de cobertura mínimo y máximo | `COVERAGE_RADIUS_MIN_METERS` (500), `COVERAGE_RADIUS_MAX_METERS` (10000) | `configuracion.dart:17-18` |
| Largo máximo de la nota del admin | `ADMIN_NOTE_MAX_LENGTH` (300) | `regla_alerta.dart:61` |
| Tiempo de aceptación y de confirmación | `ACCEPT_TIMEOUT_SECONDS` (300), `CONFIRM_TIMEOUT_SECONDS` (900) | `configuracion.dart:10-11` (en minutos en el front). El front **no los usa**: sus simulaciones escalan con `segundosEscalamientoDemo` (90 s) para ambos casos (`memoria_base_datos.dart:191`). Ver D6 y D14 |
| Frecuencia de envío de ubicación (cliente) | `LOCATION_UPDATE_SECONDS` (5) | `configuracion.dart:14` |
| Tolerancia de `triggeredAt` respecto a la hora del servidor | `TRIGGERED_AT_TOLERANCE_SECONDS` (600). Nueva; no existe en el front ni en `backend/src/config/env.ts` todavía (D24) | — |

Los valores de modo demo (`segundosEscalamientoDemo`, `segundosNuevaAlertaMin/Max`, `modoDemo`) son solo del front y no van al backend (`configuracion.dart:19-22`).

---

## 8. Foto de la alerta (D2)

- **Hoy (front):** `POST /alerts` manda `photoPath`, una ruta local del teléfono (`nube_alerta_usuario_repository.dart:27`). El mock solo pone una URL de prueba si `photoPath != null` (`memoria_alerta_usuario_repository.dart:36`).
- **Backend:** la foto se guarda detrás de una interfaz `PhotoStorage { save(stream, mime) → { key, url }; url(key) }`. La tabla `alerts` guarda `photo_key`. `photoUrl` en la respuesta se calcula con `PhotoStorage.url(photo_key)`; es `null` si no hay foto, y entonces `evidenceIncomplete = true`.
- **Subida real:** `multipart/form-data` a disco local, definida en BE-03. Hasta entonces `photoPath` se acepta pero no se puede usar para guardar el archivo; la forma exacta de la subida (misma ruta o ruta aparte) se decide en BE-03.
- Como el front espera `photoUrl` como string, debe ser una URL que la app pueda abrir con la sesión que tiene (detalle en BE-03).
- **Seguridad de la foto (BE-03):**
  - Se sirve por una **ruta autenticada** con la misma autorización que la alerta (dueño, guardia con visibilidad, admin) o con una URL firmada de vida corta. Nunca como archivo estático público ni con el token en el query.
  - `photo_key` es un UUID **generado por el servidor**.
  - El tipo se valida por la **firma de bytes** (no por el `Content-Type` del cliente) y hay un **tamaño máximo**.
  - El `photoPath` del cliente **nunca** se usa como ruta del sistema de archivos.

---

## 9. Reglas de seguridad que afectan al contrato

| Regla | Tarjeta |
|---|---|
| **Deny-by-default:** toda ruta declara `roles` o `public: true` en su configuración; un hook `onRoute` hace fallar el arranque si falta, y una prueba recorre todas las rutas registradas | BE-01 (paso 6) |
| Todos los cuerpos **y queries** se validan con esquemas zod `.strict()`: una clave extra (p. ej. `role`, `isActive`, `falseAlarmCount`) devuelve `400 INVALID_STATE` | BE-01 (paso 4 en adelante) |
| Límites de entrada: `password` ≤ 128 caracteres; largo máximo en `name`, `email`, `phone`, `zone`, `search` y `photoPath`; `heading` entero 0–359; `radiusMeters` entero; `lat` −90..90 y `lng` −180..180, finitos | BE-01 / BE-03 / BE-06 |
| `:id` validado como UUID; uno inválido responde `404 NOT_FOUND` | BE-01 (paso 4 en adelante) |
| Rate limit en `POST /auth/login` y `/auth/refresh` con error `429 TOO_MANY_REQUESTS` (**implementado en BE-01 paso 5**, D29); en `POST /auth/register` (**pendiente, BE-02**); en `POST /alerts` (BE-03); en `PUT /guard/location` y `POST /alerts/:id/locations`, por usuario y acorde a `LOCATION_UPDATE_SECONDS` (BE-04 / BE-03) | BE-01 / BE-02 / BE-03 / BE-04 |
| `GET /health` solo responde `{ "data": { "status": "ok" } }`, sin versión, base de datos ni detalles | BE-01 |
| `PUT /users/me/device-token`: ruta sugerida por `context_desarrollo`, no existe en el front; si se implementa (BE-04), no permitida para el rol `admin` | BE-04 |
| El 404 de ruta inexistente refleja solo el path, sin query string | BE-01 |
| La semilla solo corre con `NODE_ENV` `development` o `test`; se niega con `production` | BE-01 (paso 3) |
| Prohibido registrar en los logs de la aplicación cuerpos, coordenadas, teléfonos, `password`, `accessToken` o `refreshToken` | BE-01 (paso 4 en adelante) |
