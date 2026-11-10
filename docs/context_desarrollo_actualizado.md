# SafeLink — Contexto de desarrollo

> Documento de contexto histórico. La versión vigente del contrato y las decisiones está en docs/API_CONTRATO.md y docs/DECISIONES.md; si chocan, ganan esos.

> Usa este archivo como contexto inicial en chats de desarrollo: pantallas en Flutter, datos mock, funciones de lógica y API.
> Los valores marcados como **(provisional)** aún no los define el equipo; úsalos como valores por defecto configurables, nunca escritos directamente en el código.
> **Versión actualizada el 2026-11-10 contra el front en `develop`.** Lo marcado **(front)** está verificado en el código de la app (`lib/datos/safelink_service.dart`, `lib/datos/nube_mapeadores.dart`, `lib/dominio/`). **Si este documento y el front difieren, gana el front.** Lo marcado **(pendiente)** es una decisión abierta (ver sección 12).

---

## Registro de cambios respecto a la versión anterior (2026-10-08)

| # | Qué cambió | Dónde |
|---|---|---|
| 1 | Ajuste del usuario: `shakeEnabled` → `volumeDoubleClickEnabled`. El código de método `shake` se conserva, pero en la app es **doble clic de volumen** | 4.1, 4.3, 6.1 |
| 2 | Backend definido: Node.js + TypeScript + Fastify + PostgreSQL (Prisma), carpeta `backend/`, solo Docker Compose local | 2 |
| 3 | `GuardProfile` real: agrega `zone` y `lastLocationAt`; `coverageCenter` y `coverageRadiusMeters` pueden ser nulos; el guardia viaja como `{ user, profile }` | 4.2 |
| 4 | `Alert` real: agrega `userName`, `userPhone`, `guardName`, `adminNote`, `etaSeconds` | 4.3 |
| 5 | Valores configurables nuevos: `metrosPorMinutoGuardia` (ETA), límites del radio de cobertura, largo máximo de la nota del admin | 5 |
| 6 | Reglas de validación de registro/turno/nota (el backend debe repetirlas) | 6.7 (nueva) |
| 7 | La nota administrativa es **obligatoria** al resolver (1–300 caracteres) | 6.6, 7 |
| 8 | `USER_BLOCKED` se lanza al **crear una alerta**, no al iniciar sesión; cuándo se lanza cada error | 6.8 (nueva) |
| 9 | Contrato de la API reescrito con las rutas reales del front. Rutas nuevas: `/auth/logout`, `/auth/session`, `/alerts/mine`, `/guard/me`, `/guard/history`, `/guard/metrics`, `/guard/alerts/{id}/ignore`, `/admin/guards/{id}`, `/admin/users` | 7 |
| 10 | Rutas del documento anterior que **el front no usa**: `GET /alerts/active`, `GET /guard/alerts`, `GET /admin/alerts/escalated` (el front las obtiene por canal en tiempo real) | 7 |
| 11 | `PATCH /users/me/settings` usa `{ volumeDoubleClickEnabled }` | 7 |
| 12 | `POST /alerts` hoy manda JSON con `location: { lat, lng }` y `photoPath`, no multipart con `lat`/`lng` sueltos | 7, 12 |
| 13 | `PUT /guard/location` y `POST /alerts/{id}/locations` mandan `{ location: { lat, lng } }` | 7 |
| 14 | `PUT /admin/guards/{id}/coverage` usa `center`, `radiusMeters`, `zone` | 7 |
| 15 | Eventos en tiempo real reemplazados por los **4 canales** que el front escucha; cada evento es `{ data }` | 7.1 |
| 16 | Todas las respuestas llevan envoltorio `{ data }` o `{ error }` | 7 |
| 17 | Métricas: agrega `totalAlerts`; `alertsByZone` es `[{ zone, count }]`; las tasas son fracciones 0–1 | 7.2 |
| 18 | Estructura real del front (tres capas, MVVM, nombres en español en Dart) | 8.1 |
| 19 | Cuentas de prueba del front (contraseña `SafeLink1`) | 9 |
| 20 | Pendientes abiertos D1–D9 | 12 (nueva) |

---

## 1. Producto en una línea

App móvil que conecta a un **usuario en riesgo** con un **guardia de seguridad privada**. El usuario dispara una alerta; la app captura automáticamente **foto, ubicación GPS, rumbo de la cámara, hora y método de disparo**, y la publica a los guardias en turno dentro de su radio. Un guardia la acepta, navega al punto, marca su llegada por geocerca y el usuario confirma que fue atendido. Un **administrador** gestiona guardias, revisa alertas escaladas y consulta métricas.

Proyecto académico (UTEZ), prototipo funcional. Las pruebas se enfocan principalmente en la interfaz.

---

## 2. Stack y convenciones

| Capa | Decisión |
|---|---|
| App móvil | **Flutter** (Material 3), Android como plataforma principal; iOS soportado con limitaciones (ver 6.4) |
| API | API REST propia con JSON bajo `/api/v1`. Tiempo real por **SSE** (pendiente D3; el documento anterior decía "WebSocket o equivalente") |
| Backend | **Node.js LTS + TypeScript (strict) + Fastify + PostgreSQL 16 + Prisma + zod + argon2**, en la carpeta `backend/` del mismo repo. Pruebas con Vitest + supertest. **Sin despliegue por ahora:** solo Docker Compose en local; configuración por variables de entorno |
| Autenticación | Token JWT enviado en `Authorization: Bearer <token>`. **(pendiente D7)** el front hoy no recibe ni guarda token (ver 12) |
| Notificaciones push | Firebase Cloud Messaging (FCM). **(pendiente)** no existe aún en el front ni en el servicio simulado; se hace en BE-04 |
| Mapas | Google Maps (mapa en la app + enlace externo a Google Maps) |
| Almacenamiento de fotos | Servicio de archivos; la alerta guarda la URL de la foto. Detrás de una interfaz `PhotoStorage` (disco local primero). **(pendiente D2)** |

**Convenciones**
- Endpoints, campos JSON y backend en **inglés** (`camelCase` en JSON). **El front Flutter usa nombres en español en Dart** (`Alerta`, `EstadoAlerta`, `ReglaGeocerca`…); la traducción a los códigos de la API vive solo en `lib/datos/nube_mapeadores.dart`.
- Todo el texto visible de la interfaz y los mensajes de error de la API en **español (México)**.
- Fechas en ISO 8601 UTC (`2026-10-07T18:17:00Z`); la app las muestra en hora local. **(front)** el cliente envía `DateTime.toIso8601String()`: confirmar que mande UTC (ver D8).
- Distancias en metros, tiempos en segundos, rumbo en grados (0–359, 0 = norte).
- IDs como strings (UUID).
- Control de versiones: GitFlow (`main`, `develop`, `feat/<id>-<descripcion>`, por ejemplo `feat/U-03-toque-simple` o `feat/BE-01-Base`).

---

## 3. Roles del sistema

| Rol (`role`) | Alta | Puede | No puede |
|---|---|---|---|
| `protected_user` — Usuario protegido | Se registra solo | Disparar alertas, compartir ubicación, ver guardia asignado y ETA, confirmar atención | Elegir guardia, ver ubicación del guardia |
| `guard` — Guardia de respuesta | Lo crea el administrador | Ver alertas de su radio, aceptar, ignorar, navegar, marcar llegada | Registrarse, cerrar alertas, ver alertas tomadas por otro guardia |
| `admin` — Administrador | Precargado en el sistema | Gestionar guardias, turnos y radios, resolver escaladas, ver historial y métricas, gestionar bloqueos | Disparar o aceptar alertas |

Los permisos se validan **en la API**, no solo en la interfaz.

---

## 4. Modelo de datos

### 4.1 User (front)
```
id: string
name: string
email: string                    // único
phone: string                    // 10 dígitos
role: "protected_user" | "guard" | "admin"
isActive: bool                   // false = guardia dado de baja (no puede iniciar sesión)
volumeDoubleClickEnabled: bool   // solo protected_user (antes: shakeEnabled)
falseAlarmCount: int             // solo protected_user
blockedUntil: datetime?          // solo protected_user; null = no bloqueado
createdAt: datetime
```

### 4.2 GuardProfile (solo `guard`) (front)
```
userId: string
shiftStart: "HH:mm"              // puede cruzar medianoche (ej. 22:00 → 06:00); inicio = fin → turno de 24 h
shiftEnd: "HH:mm"
coverageCenter: { lat, lng }?    // nulo hasta que el admin lo define
coverageRadiusMeters: int?       // nulo hasta que el admin lo define
zone: string?                    // nombre de la zona de cobertura (lo usa la métrica por zona)
lastLocation: { lat, lng }?
lastLocationAt: datetime?
```
En la API un guardia viaja como `{ "user": <User>, "profile": <GuardProfile> }`.

Un guardia está **disponible** si `isActive`, tiene turno vigente en la hora actual y tiene cobertura definida (centro y radio > 0).

### 4.3 Alert (front)
```
id: string
userId: string
userName: string?                  // desnormalizado para listados
userPhone: string?
guardId: string?
guardName: string?
status: AlertStatus
triggerMethod: "tap" | "hold" | "shake"   // shake = doble clic de volumen en la app
photoUrl: string?
evidenceIncomplete: bool           // true si no hay foto
location: { lat, lng }?            // del GPS en el instante del disparo
heading: int?                      // grados 0–359 del magnetómetro
triggeredAt: datetime              // del dispositivo en el instante del disparo
acceptedAt: datetime?
arrivedAt: datetime?
closedAt: datetime?
escalationReason: "no_response" | "no_confirmation" | null
resolution: "resolved" | "false_alarm" | "service_incident" | null
adminNote: string?                 // nota del admin al resolver
etaSeconds: int?                   // estimado de llegada del guardia
```
Una alerta es **urgente** si `triggerMethod = shake`.

### 4.4 LocationUpdate (seguimiento en tiempo real)
```
alertId: string
lat: double
lng: double
recordedAt: datetime             // lo asigna el servidor; el front manda solo { location: { lat, lng } }
```

### 4.5 Estados de la alerta (`AlertStatus`) (front)

| Estado | Texto en UI | Significado |
|---|---|---|
| `pending_location` | Pendiente de ubicación | Sin coordenadas válidas; no se publica |
| `searching` | Buscando guardia | Publicada a guardias disponibles |
| `in_progress` | En atención | Un guardia la aceptó |
| `guard_arrived` | Guardia en el lugar | Llegada validada por geocerca |
| `closed` | Atendida | El usuario confirmó la atención |
| `no_response` | Sin respuesta | Nadie la aceptó a tiempo; se escala |
| `escalated` | Escalada | En bandeja del administrador |
| `resolved_by_admin` | Resuelta por administrador | El admin asignó una `resolution` |

Estados **activos**: `pending_location`, `searching`, `in_progress`, `guard_arrived`. Estados **terminales**: `closed`, `resolved_by_admin`.

**Transiciones válidas** (idénticas en el front, `ReglaAlerta`)
```
pending_location → searching            (llegan coordenadas válidas)
searching        → in_progress          (guardia acepta)
searching        → no_response → escalated   (vence tiempo de aceptación)
in_progress      → guard_arrived        (guardia dentro de geocerca marca llegada)
guard_arrived    → closed               (usuario confirma)
guard_arrived    → escalated            (vence tiempo de confirmación)
escalated        → resolved_by_admin    (admin elige resolución)
```

---

## 5. Valores configurables

| Clave (API/backend) | Nombre en el front | Valor | Uso |
|---|---|---|---|
| `tapCountdownSeconds` | `segundosCuentaRegresiva` | 3 | Cuenta regresiva del toque simple |
| `geofenceRadiusMeters` | `radioGeocercaMetros` | 50 **(provisional)** | Radio para habilitar "Llegué" |
| `acceptanceTimeoutMinutes` | `minutosAceptacion` | 5 **(provisional)** | Tiempo máximo sin aceptar antes de `no_response` |
| `confirmationTimeoutMinutes` | `minutosConfirmacion` | 15 **(provisional)** | Tiempo máximo sin confirmar tras la llegada |
| `falseAlarmLimit` | `limiteFalsasAlarmas` | 3 **(provisional)** | Falsas alarmas para bloquear |
| `blockDurationDays` | `diasBloqueo` | 7 **(provisional)** | Duración del bloqueo |
| `locationUpdateIntervalSeconds` | `segundosActualizacionUbicacion` | 5 **(provisional)** | Frecuencia de envío de ubicación |
| `waitingMetersPerMinute` | `metrosPorMinutoEspera` | 100 **(provisional)** | Peso de la espera en el orden del listado (6.3) |
| `guardMetersPerMinute` | `metrosPorMinutoGuardia` | 250 **(provisional)** | Velocidad para estimar el ETA (~15 km/h en ciudad): `etaSeconds = distancia / 250 × 60` |
| `coverageRadiusMinMeters` | `radioCoberturaMinMetros` | 500 | Radio de cobertura mínimo permitido |
| `coverageRadiusMaxMeters` | `radioCoberturaMaxMetros` | 10000 | Radio de cobertura máximo permitido |
| `adminNoteMaxLength` | `maxNota` | 300 | Largo máximo de la nota al resolver |

Solo del **modo demo del front** (no van en el backend): `segundosEscalamientoDemo` = 90 s (en producción rige `acceptanceTimeoutMinutes`), `segundosNuevaAlertaMin/Max` = 20–40 s (alertas simuladas).

---

## 6. Reglas de negocio clave

### 6.1 Disparo de alerta (un solo botón, tres métodos)
- **Toque (`tap`)**: muestra cuenta regresiva de 3 s con botón "Cancelar". Al llegar a 0 se dispara; si cancela, no se crea nada.
- **Mantener presionado (`hold`)**: sin límite de tiempo. Aparece una zona "Descartar" (tipo bote de basura) que se resalta al pasar encima. Soltar fuera → dispara de inmediato. Soltar dentro → descarta.
- **Doble clic de volumen (código `shake`)** (front, U-05): presionar dos veces el botón de bajar volumen. Servicio en segundo plano con notificación persistente; funciona con la pantalla bloqueada; una sola pulsación no dispara; el teléfono vibra al disparar. Se activa o desactiva en Configuración (`volumeDoubleClickEnabled`). La versión anterior de este documento lo describía como agitación con acelerómetro; `docs/HISTORIAS_DE_USUARIO.md` (nota del 01/11/2026) confirma que el método es el doble clic de volumen. El código de la API sigue siendo `shake` y es el método **urgente**.
- Comando de voz: **fuera del alcance**.

### 6.2 Evidencia
- Al disparar se toma **una sola foto** automática, sin intervención del usuario.
- Ubicación, rumbo y hora se toman **de los sensores en el instante del disparo**, nunca de los metadatos de la imagen.
- Sin foto → la alerta se envía con `evidenceIncomplete = true`.
- Sin coordenadas válidas → `pending_location`, no se publica y se avisa al usuario.
- Mientras la alerta esté activa, la ubicación del usuario se transmite en tiempo real, incluso en segundo plano.

### 6.3 Despacho y orden de alertas (front)
- Solo reciben la alerta guardias **disponibles** cuyo radio contiene la ubicación de la alerta.
- Solo se listan alertas que **tienen ubicación**.
- Orden del listado del guardia **(provisional)**:
  1. Primero las urgentes (`triggerMethod = shake`), destacadas en ámbar.
  2. Después, de menor a mayor `score = distanceMeters − (waitingMinutes × 100)`, donde `waitingMinutes = (ahora − triggeredAt) / 60`. Cada minuto de espera equivale a acercar la alerta 100 m.
- Cada elemento del listado viaja como `{ alert, distanceMeters, waitingMinutes, score }`.
- Al aceptar, la alerta se asigna a un solo guardia (control de concurrencia en la API) y desaparece del listado de los demás. El guardia también puede **ignorar** una alerta (desaparece solo de su listado).

### 6.4 Notificaciones al guardia
- **Android**: canal de notificación tipo alarma + notificación de pantalla completa; suena aunque el teléfono esté en silencio o No molestar.
- **iOS**: notificación normal; **no** se contempla modo silencio ni No molestar (requiere permiso especial de Apple). El guardia sigue recibiendo alertas.

### 6.5 Llegada y cierre
- "Llegué" solo se habilita si la distancia guardia–alerta ≤ `geofenceRadiusMeters` (distancia Haversine); fuera, muestra la distancia restante.
- Solo el usuario cierra la alerta ("Ya fui atendido"), y solo en `guard_arrived` con guardia asignado.
- El guardia nunca cierra la alerta.
- El usuario no puede cerrar una alerta sin guardia asignado.

### 6.6 Resolución del admin y bloqueo por falsas alarmas (front)
- Solo se resuelven alertas en `escalated`.
- La **nota administrativa es obligatoria** al resolver: 1–300 caracteres (`adminNote`).
- Cada resolución `false_alarm` incrementa `falseAlarmCount` del usuario.
- Al llegar a `falseAlarmLimit`, `blockedUntil = ahora + blockDurationDays`.
- El usuario bloqueado ve un aviso con la fecha de fin en lugar del botón. El admin puede retirar el bloqueo manualmente.

### 6.7 Reglas de validación (front, `ReglaRegistro` y `ReglaTurno`; el backend debe repetirlas)
| Campo | Regla |
|---|---|
| `name` | Obligatorio, mínimo 3 caracteres (sin espacios de los extremos) |
| `email` | Obligatorio; formato `^[\w.+-]+@[\w-]+(\.[\w-]+)+$`; único |
| `phone` | Obligatorio; exactamente 10 dígitos |
| `password` | Obligatoria, mínimo 8 caracteres y al menos 1 número (en el login solo es obligatoria) |
| `shiftStart` / `shiftEnd` | Formato `HH:mm` (00:00–23:59). Si inicio < fin, el turno es de ese día; si inicio > fin, cruza medianoche; si son iguales, turno de 24 h |
| `radiusMeters` | Entre `coverageRadiusMinMeters` (500) y `coverageRadiusMaxMeters` (10000) |
| `zone` | Obligatoria al definir cobertura |

### 6.8 Cuándo se lanza cada error (front)
| Código | Cuándo |
|---|---|
| `INVALID_CREDENTIALS` | Login con correo inexistente, contraseña incorrecta o usuario con `isActive = false` |
| `EMAIL_TAKEN` | Registro, alta de guardia o edición de guardia con un correo ya usado |
| `USER_BLOCKED` | **Crear una alerta** estando bloqueado (no al iniciar sesión) |
| `ALERT_TAKEN` | Aceptar una alerta que ya no está en `searching` |
| `OUTSIDE_GEOFENCE` | Marcar llegada fuera del radio; incluye `remainingMeters` |
| `INVALID_STATE` | Acción no válida para el estado actual (confirmar sin llegada, resolver una alerta no escalada) y rechazos de validación del admin (alta de guardia, cobertura) |
| `NOT_FOUND` | Alerta o guardia inexistente |
| `UNAUTHORIZED` | Sin sesión |
| `SERVICE_UNAVAILABLE` | Servicio no disponible |

Códigos HTTP **(propuesta, pendiente D9)**: `INVALID_CREDENTIALS` 401 · `UNAUTHORIZED` 401 · `USER_BLOCKED` 403 · `NOT_FOUND` 404 · `ALERT_TAKEN` 409 · `EMAIL_TAKEN` 409 · `INVALID_STATE` 409 · `OUTSIDE_GEOFENCE` 422 · `SERVICE_UNAVAILABLE` 503. Hoy el servicio simulado no usa códigos HTTP: el cliente decide por `error.code`.

---

## 7. API REST (contrato verificado contra el front)

Base: `/api/v1`. **Toda respuesta** es `{ "data": ... }` o `{ "error": { "code": "STRING", "message": "texto en español", ["remainingMeters": number] } }`. Las acciones sin resultado devuelven `{ "data": null }`. Todas las rutas, salvo `register` y `login`, requieren sesión.

### Autenticación
| Método | Ruta | Rol | Cuerpo | `data` | Historia |
|---|---|---|---|---|---|
| POST | `/auth/register` | público | `{ name, email, phone, password }` | `User` | U-01 |
| POST | `/auth/login` | público | `{ email, password }` | `User` **(pendiente D7: token)** | U-02, G-01 |
| POST | `/auth/logout` | todos | — | `null` | U-02 |
| GET | `/auth/me` | todos | — | `User` | U-02, G-01 |
| POST | `/auth/session` | todos | `{ userId }` | `User` o `null` **(pendiente D7)** | U-02 |
| PATCH | `/users/me/settings` | protected_user | `{ volumeDoubleClickEnabled }` | `User` | U-05 |
| PUT | `/users/me/device-token` | todos | `{ token }` | `null` | G-02 **(pendiente, no está en el front; BE-04)** |

### Alertas — usuario protegido
| Método | Ruta | Cuerpo | `data` | Historia |
|---|---|---|---|---|
| POST | `/alerts` | `{ triggerMethod, triggeredAt, location: {lat,lng}?, heading?, photoPath? }` **(pendiente D2: foto)** | `Alert` | U-03–U-06 |
| GET | `/alerts/mine` | — | `Alert[]` (historial del usuario) | — (extra del front) |
| POST | `/alerts/{id}/locations` | `{ location: {lat,lng} }` | `null` | U-07 |
| POST | `/alerts/{id}/confirm` | — | `Alert` | U-09 |

La alerta activa del usuario llega por el canal `alerts/active` (7.1). Se recomienda ofrecer también `GET /alerts/active` como instantánea (no existe en el front).

### Alertas — guardia
| Método | Ruta | Cuerpo | `data` | Historia |
|---|---|---|---|---|
| GET | `/guard/me` | — | `Guard` (`{ user, profile }`) | G-01 (extra del front) |
| GET | `/guard/history` | — | `Alert[]` | — (extra del front) |
| GET | `/guard/metrics` | — | `GuardMetrics` | — (extra del front) |
| PUT | `/guard/location` | `{ location: {lat,lng} }` | `null` | G-06, G-07 |
| GET | `/guard/alerts/{id}` | — | `Alert` | G-04 |
| POST | `/guard/alerts/{id}/accept` | — | `Alert`; `ALERT_TAKEN` si ya fue tomada | G-05 |
| POST | `/guard/alerts/{id}/ignore` | — | `null` | G-03 (extra del front) |
| POST | `/guard/alerts/{id}/arrive` | — | `Alert`; `OUTSIDE_GEOFENCE` si está fuera | G-07 |

El listado de alertas disponibles llega por el canal `guard/alerts` (7.1). Se recomienda ofrecer también `GET /guard/alerts` como instantánea (no existe en el front).

### Administración
| Método | Ruta | Cuerpo / query | `data` | Historia |
|---|---|---|---|---|
| GET | `/admin/guards?search=` | `search` | `Guard[]` | A-02 |
| POST | `/admin/guards` | `{ name, email, phone, password }` | `Guard` | A-01 |
| GET | `/admin/guards/{id}` | — | `Guard` | A-02 (extra del front) |
| PATCH | `/admin/guards/{id}` | `{ name?, email?, phone? }` | `Guard` | A-02 |
| DELETE | `/admin/guards/{id}` | — | `null` (baja lógica, `isActive = false`) | A-02 |
| PUT | `/admin/guards/{id}/coverage` | `{ shiftStart, shiftEnd, center: {lat,lng}, radiusMeters, zone }` | `Guard` | A-03 |
| POST | `/admin/alerts/{id}/resolve` | `{ resolution, adminNote }` (nota obligatoria) | `Alert` | A-04 |
| GET | `/admin/alerts?from=&to=&guardId=&userId=&status=` | filtros opcionales (`from`/`to` ISO 8601, `status` = código de estado) | `Alert[]` | A-05 |
| GET | `/admin/metrics?from=&to=` | periodo opcional | `GeneralMetrics` | A-06 |
| GET | `/admin/metrics/guards/{id}?from=&to=` | periodo opcional | `GuardMetrics` | A-07 |
| GET | `/admin/users` | — | `User[]` | A-08 (extra del front) |
| GET | `/admin/users/blocked` | — | `User[]` | A-08 |
| DELETE | `/admin/users/{id}/block` | — | `null` | A-08 |

La bandeja de escaladas llega por el canal `admin/alerts/escalated` (7.1). Se recomienda ofrecer también `GET /admin/alerts/escalated` como instantánea (no existe en el front).

### 7.1 Tiempo real: canales que el front escucha (front)
Cada mensaje es `{ "data": ... }`. El transporte (SSE, pendiente D3) se define en BE-01; la **forma de los mensajes no cambia**.

| Canal | Quién escucha | `data` |
|---|---|---|
| `alerts/active` | Usuario protegido | `Alert` activa del usuario, o `null` si no tiene. Aquí llegan los cambios que antes eran los eventos `alert.accepted`, `alert.eta` y `alert.arrived` (`guardName`, `etaSeconds`, `status`, `arrivedAt` van dentro de la `Alert`) |
| `guard/alerts` | Guardia en sesión | Lista ordenada de `{ alert, distanceMeters, waitingMinutes, score }` de las alertas disponibles. Reemplaza a `alert.created` y `alert.taken` (una alerta tomada deja de aparecer en la lista) |
| `guard/alerts/{id}` | Guardia | `Alert` (cambios de la alerta que está atendiendo; reemplaza a `alert.location`) |
| `admin/alerts/escalated` | Administrador | Lista de `Alert` escaladas. Reemplaza a `alert.escalated` |

> Los eventos nombrados del documento anterior (`alert.created`, `alert.taken`, `alert.accepted`, `alert.location`, `alert.eta`, `alert.arrived`, `alert.escalated`) **no existen en el front**; su información viaja dentro de las entidades de estos cuatro canales.

### 7.2 Métricas (front)
- **`GeneralMetrics`**: `{ totalAlerts, avgAcceptanceSeconds, avgArrivalSeconds, noResponseRate, confirmedCloseRate, alertsByHour: int[24], alertsByZone: [{ zone, count }] }`.
  - `noResponseRate` = alertas con `escalationReason = no_response` ÷ total (fracción 0–1). `confirmedCloseRate` = alertas `closed` ÷ total (0–1).
  - `avgAcceptanceSeconds` = promedio de `acceptedAt − triggeredAt`; `avgArrivalSeconds` = promedio de `arrivedAt − (acceptedAt o triggeredAt)`. Solo cuentan alertas que tienen ambos valores.
  - `alertsByHour` cuenta por hora **local** de `triggeredAt` (ver D8). `alertsByZone` usa la zona del guardia asignado; sin guardia o sin zona → `"Sin zona asignada"`; se ordena de mayor a menor y luego por nombre.
- **`GuardMetrics`**: `{ attendedCount, avgAcceptanceSeconds, avgArrivalSeconds, escalatedCount }`. `attendedCount` = alertas del guardia con `arrivedAt`; `escalatedCount` = alertas del guardia con `escalationReason`.
- Con cero alertas, todos los valores son 0 y las listas van vacías (sin divisiones entre cero).

---

## 8. App Flutter

### 8.1 Estructura real (front)
Tres capas (dominio · datos · presentación) con MVVM. **No** es la estructura `core/data/features/shared` sugerida en la versión anterior.
```
lib/
  main.dart                  raíz de composición (usarNube, tasaFallo, Dependencias)
  dominio/                   entidades y reglas en Dart puro (sin Flutter)
  datos/                     contratos de repositorio, implementaciones memoria_ y nube_,
                             servicio simulado (safelink_service.dart), mapeadores JSON, semilla
  presentacion/
    comun/                   EstadoVista, ViewModel base, formato, tema, widgets, rutas
    sesion/  auth/  usuario/  guardia/  admin/  dev/
test/
  dominio/  datos/  presentacion/  interfaz/  arquitectura_test.dart
```
- Regla de dependencias: `presentacion → datos → dominio` (la verifica `test/arquitectura_test.dart`).
- La capa de datos usa **repositorios con interfaz**, con una implementación en memoria y otra `nube_*` que traduce entidad ↔ JSON y habla con `SafeLinkService`. Con `usarNube = true` la app usa la "nube" simulada; para la API real hay que reemplazar el cuerpo de `SafeLinkService` por HTTP **(pendiente D4)**; los `nube_*` no cambian.
- La lógica pura (validadores, geocerca, distancia, orden, ETA, métricas, reglas de cierre y bloqueo) está en funciones aisladas con pruebas unitarias (`test/dominio/`).

### 8.2 Diseño visual
| Token | Valor | Uso |
|---|---|---|
| background | `#0F172A` | Fondo (tema oscuro) |
| surface | navy más claro | Tarjetas |
| emergency | `#EF4444` | Solo botón de alerta y alertas activas |
| warning | `#F59E0B` | Urgente / pendiente |
| success | `#22C55E` | Confirmado / seguro |
| info | `#3B82F6` | Mapas y navegación |

Bordes redondeados de 16 px, objetivos táctiles mínimos de 56 px, tipografía Inter o Roboto, alta legibilidad bajo estrés. Diseños de referencia generados en Google Stitch.

### 8.3 Pantallas por rol

**Compartida**: Login.

**Usuario protegido**: Registro · Permisos (cámara, ubicación, notificaciones) · Inicio con botón · Cuenta regresiva · Mantener presionado con zona de descarte · Buscando guardia · Guardia asignado con ETA · Guardia llegó ("Ya fui atendido") · Configuración (toggle de doble clic de volumen) · Cuenta bloqueada · Historial de mis alertas.

**Guardia**: Inicio con dashboard y métricas personales · Alerta entrante (pantalla completa) · Listado de alertas (con filtros y estado vacío) · Detalle con foto y cono de rumbo · Navegación con ruta, "Abrir en Google Maps" y botón "Llegué" · Esperando confirmación · Fuera de turno · Historial.

**Administrador** (barra inferior: Inicio, Guardias, Escaladas, Historial): Métricas generales · Listado de guardias · Alta/edición · Turno y radio en mapa · Métricas por guardia · Bandeja de escaladas · Detalle de escalada con acciones · Detalle de alerta · Historial con filtros · Usuarios bloqueados.

---

## 9. Datos mock

Usar datos realistas de **Morelos, México** (zona de Emiliano Zapata y Cuernavaca, alrededor de `18.84, -99.18`), nombres y teléfonos mexicanos ficticios. La semilla del backend (BE-01) debe **reproducir la del front** (`lib/datos/datos_semilla.dart`) con las mismas cuentas.

**Cuentas de prueba del front** (contraseña `SafeLink1`)

| Correo | Rol | Notas |
|---|---|---|
| `usuario@safelink.mx` | `protected_user` | Cuenta principal de pruebas |
| `rosa.diaz@mail.com` | `protected_user` | `falseAlarmCount = 2`: una falsa alarma más y se bloquea |
| `bloqueado@safelink.mx` | `protected_user` | Bloqueada |
| `guardia@safelink.mx` | `guard` | En turno |
| `guardia.noche@safelink.mx` | `guard` | Turno 22:00 → 06:00 (cruza medianoche) |
| `admin@safelink.mx` | `admin` | Precargado |

Conjunto mínimo recomendado:
- 1 administrador.
- 5 guardias: 3 en turno, 1 fuera de turno (incluido un turno nocturno que cruce medianoche), 1 dado de baja.
- 4 usuarios protegidos: 1 con `falseAlarmCount = 2`, 1 bloqueado.
- Alertas que cubran **todos los estados** de 4.5, **los tres métodos** de disparo, al menos una con `evidenceIncomplete = true`, una urgente (`shake`), y las dos razones de escalamiento.
- Historial de al menos 30 alertas cerradas en distintas horas para que las métricas y gráficas tengan datos.

---

## 10. Historias de usuario (referencia)

**Usuario protegido**: U-01 Registro · U-02 Inicio de sesión · U-03 Toque simple · U-04 Mantener presionado · U-05 Disparo de alerta sin desbloquear el teléfono (doble clic de volumen; antes "Agitación") · U-06 Captura de evidencia · U-07 Ubicación en tiempo real · U-08 Guardia asignado y ETA · U-09 Confirmación de atención.

**Guardia**: G-01 Inicio de sesión · G-02 Recepción de alertas · G-03 Listado por cercanía y prioridad · G-04 Detalle de alerta · G-05 Aceptación · G-06 Ruta hacia el usuario · G-07 Registro de llegada.

**Administrador**: A-01 Alta de guardias · A-02 Edición y baja · A-03 Turnos y radios · A-04 Bandeja de escaladas · A-05 Historial · A-06 Métricas generales · A-07 Métricas por guardia · A-08 Bloqueo por falsas alarmas.

Cada historia tiene pruebas de **Interfaz**, **Unitaria** e **Integración** definidas. Al generar código para una historia, incluir el ID en la rama, en los comentarios relevantes y en los nombres de los archivos de prueba.

---

## 11. Fuera del alcance

Pagos y facturación · integración con seguridad pública o líneas de emergencia · llamadas de voz o video · verificación documental de guardias · comando de voz · alertas en modo silencio en iOS.

---

## 12. Pendientes y decisiones abiertas

| ID | Tema | Situación y recomendación |
|---|---|---|
| D1 | Turnos | La tarjeta BE-01 pide una tabla de turnos, pero el front modela **un turno por guardia** (`shiftStart`/`shiftEnd` en el perfil). Recomendación: columnas en `guard_profiles`; tabla aparte solo si se necesita historial de turnos |
| D2 | Foto | El front manda `photoPath` (ruta local); la subida real aún no existe. Recomendación: `multipart/form-data` en BE-03 detrás de una interfaz `PhotoStorage`; en BE-01 solo se define la interfaz |
| D3 | Tiempo real | El front escucha 4 canales (7.1). Recomendación: SSE, una ruta por canal, mensaje `{ data }`; implementación en BE-04/BE-05 |
| D4 | Conexión del front | El front no tiene cliente HTTP: `SafeLinkService` es simulado. Hay que reemplazar su cuerpo por HTTP (toca `lib/` y `pubspec.yaml`) para probar en dispositivo físico |
| D5 | Tablas extra | El front sugiere: alertas ignoradas por guardia, historial de cambios de estado/auditoría (A-05) y `location_updates` (4.4) |
| D6 | Diferencias front vs documento | **Resuelto en esta versión**: gana el front (ver registro de cambios) |
| D7 | Token y sesión | El front hoy recibe solo el `User` en `/auth/login` y restaura la sesión con `POST /auth/session { userId }`. Con JWT hace falta devolver el token (por ejemplo `data: { token, user }`, lo que obliga a un cambio pequeño en `NubeAuthRepository`) y restaurar la sesión con `GET /auth/me` usando el token guardado |
| D8 | Zona horaria y fechas | `alertsByHour` usa la hora local; el backend debe fijar una zona (recomendación: `America/Mexico_City` por configuración). Además, el cliente envía `toIso8601String()`: confirmar que mande UTC (`toUtc()`) |
| D9 | Códigos HTTP | Proponer los de 6.8 y documentarlos; el front decide por `error.code` |

---

## Apéndice — qué se verificó y dónde

- Rutas, cuerpos y respuestas: `lib/datos/safelink_service.dart`, `lib/datos/nube_*_repository.dart`.
- Nombres de campos, códigos de enums y errores: `lib/datos/nube_mapeadores.dart`.
- Reglas: `lib/dominio/regla_alerta.dart` (transiciones, aceptación, confirmación, escalamiento, nota, falsa alarma), `regla_prioridad.dart`, `regla_geocerca.dart`, `regla_turno.dart`, `regla_eta.dart`, `regla_registro.dart`, `regla_metricas.dart`, `configuracion.dart`.
- Dónde se lanza cada error: `lib/datos/memoria_*_repository.dart`.
- **No se verificó**: las sentencias exactas de cada rechazo de validación del admin (el texto de los mensajes vive en el dominio del front) ni el contenido completo de la semilla; el backend debe leerlos de `lib/dominio/` y `lib/datos/datos_semilla.dart` al implementarlos.
