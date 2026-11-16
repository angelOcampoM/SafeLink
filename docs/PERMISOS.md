# Permisos por rol

Cubre: U-02, G-01 (sesión), G-04, G-05 (visibilidad del guardia), A-01 a A-08 (acceso de administración) y la minimización de datos (D23).
Tarjeta: BE-01 (paso 6, `feat(BE-01): permisos por rol deny-by-default`). Las rutas de BE-02 a BE-07 se agregan después, pero su política ya está registrada.

Fuente de verdad en el código: `backend/src/security/policies.ts` (`ROUTE_POLICIES`). Si este documento y ese archivo discrepan, gana el código: avisa para corregir el documento.

## 1. Principio: deny-by-default

Los permisos se validan en la API, no solo en la interfaz. Una ruta que no tiene política no puede existir.

- **Registro central:** `ROUTE_POLICIES` en `backend/src/security/policies.ts` es la única fuente de verdad. La clave es `MÉTODO /ruta` relativa a `/api/v1`, con la notación `:id` del front.
- **Hook `onRoute`** (`backend/src/security/guards.ts`, `registerRouteGuards`). Se registra en la instancia raíz antes que cualquier ruta (`backend/src/app.ts`). **Aborta el arranque** (lanza `Error`) si:
  - una ruta bajo `/api/v1` no tiene entrada en `ROUTE_POLICIES`;
  - la `config` de la ruta (`public`, `roles`, `auth: 'custom'`) contradice la política central, o declara más de una;
  - una misma ruta tiene métodos con políticas distintas;
  - una ruta está **fuera** del prefijo `/api/v1` y no está en `EXEMPT_ROUTES`. Hoy solo `GET /health` está exenta.
- **HEAD** lo genera Fastify a partir de GET y hereda la política de GET.
- **Orden de los controles** (todos en `onRequest`, no en `preHandler`): `authenticate` (401) → `requireRole` (403) → validación del cuerpo (400) → propiedad/visibilidad (404). Así un anónimo o un rol incorrecto se rechaza antes de leer el cuerpo.

## 2. Tipos de política

| Política | Qué hace | Rutas |
|---|---|---|
| `public` | Sin autenticación. | `POST /auth/login`, `POST /auth/register`, `POST /auth/refresh` |
| `custom` | La ruta verifica el token por su cuenta (D7, D25). | `POST /auth/session` |
| Lista de roles | Exige access token válido y que el rol sea uno de la lista. | El resto |

Cómo se autentica (`backend/src/plugins/auth.ts`, `authenticate`):

1. Se verifica el Bearer (HS256, `exp`, `iat`, `sub`, `sid`, vigencia máxima). Falla = 401 `UNAUTHORIZED`.
2. Se consulta la base (`findLiveSessionUser`): usuario activo y `sid` no revocado. Si no, 401.
3. `request.user = { id, role, sid }`. **El rol sale de la base de datos en cada petición**, no del claim del token. Un cambio de rol, una baja o un logout surten efecto de inmediato.

Códigos: sin token, token inválido, sesión revocada o usuario inactivo = `401 UNAUTHORIZED`; rol incorrecto = `403 FORBIDDEN` ("No tienes permiso para realizar esta acción.", D9).

`POST /auth/session` es la excepción: `401` solo si falta el token, la firma o el algoritmo no son válidos, o venció; con sesión revocada, usuario inactivo o `userId` distinto de `sub` responde `200` con `data: null`.

## 3. Matriz rol × ruta

Leyenda: ✅ permitido (sujeto a la regla de la última columna), 401 = no autenticado, 403 = rol incorrecto. Las rutas son relativas a `/api/v1`. 36 entradas: 31 rutas del front, `POST /auth/refresh` (excepción aprobada, D8) y 4 canales SSE.

La columna "Regla de propiedad o visibilidad" describe lo que define el contrato y las decisiones (D9, D22, D23); se implementa en la tarjeta indicada. Un recurso ajeno responde `404 NOT_FOUND`, nunca 403.

| # | Método y ruta | Anónimo | protected_user | guard | admin | Regla de propiedad o visibilidad | Tarjeta |
|---|---|---|---|---|---|---|---|
| 1 | `POST /auth/login` | ✅ | ✅ | ✅ | ✅ | Pública. Rate limit por IP (D29) | BE-01 |
| 2 | `POST /auth/register` | ✅ | ✅ | ✅ | ✅ | Pública. Siempre crea `protected_user` | BE-02 |
| 3 | `POST /auth/refresh` | ✅ | ✅ | ✅ | ✅ | Pública; la autoriza el refresh token. Rate limit por IP | BE-01 |
| 4 | `POST /auth/logout` | 401 | ✅ | ✅ | ✅ | Revoca la sesión (`sid`) del propio token | BE-01 |
| 5 | `GET /auth/me` | 401 | ✅ | ✅ | ✅ | Solo el usuario del token | BE-01 |
| 6 | `POST /auth/session` | 401 | ✅ | ✅ | ✅ | Verificación propia; `userId` debe ser el `sub`, si no `200` con `data: null` (D7) | BE-01 |
| 7 | `PATCH /users/me/settings` | 401 | ✅ | 403 | 403 | Solo sus propios ajustes | BE-02 |
| 8 | `POST /alerts` | 401 | ✅ | 403 | 403 | Crea para el usuario del token; `USER_BLOCKED` si está bloqueado | BE-03 |
| 9 | `GET /alerts/mine` | 401 | ✅ | 403 | 403 | Solo alertas propias | BE-03 |
| 10 | `POST /alerts/:id/locations` | 401 | ✅ | 403 | 403 | `assertOwnsAlert` | BE-03 |
| 11 | `POST /alerts/:id/confirm` | 401 | ✅ | 403 | 403 | `assertOwnsAlert` | BE-03 |
| 12 | `GET /guard/me` | 401 | 403 | ✅ | 403 | Solo el propio perfil | BE-04 |
| 13 | `GET /guard/history` | 401 | 403 | ✅ | 403 | Solo alertas con `guardId` propio y no activas; sin `userPhone` ni `location` (D23) | BE-04 |
| 14 | `GET /guard/metrics` | 401 | 403 | ✅ | 403 | Sobre la misma lista que el historial | BE-04 |
| 15 | `PUT /guard/location` | 401 | 403 | ✅ | 403 | Solo su propia ubicación | BE-04 |
| 16 | `GET /guard/alerts/:id` | 401 | 403 | ✅ | 403 | `assertGuardCanSee` (D22) | BE-04 |
| 17 | `POST /guard/alerts/:id/accept` | 401 | 403 | ✅ | 403 | `assertGuardCanSee` con `skipStatusCheck`; visible y no `searching` = 409 `ALERT_TAKEN` | BE-04 |
| 18 | `POST /guard/alerts/:id/ignore` | 401 | 403 | ✅ | 403 | `assertGuardCanSee` (alerta visible para él) | BE-04 |
| 19 | `POST /guard/alerts/:id/arrive` | 401 | 403 | ✅ | 403 | `assertAssignedGuard` antes de estado y geocerca | BE-04 |
| 20 | `GET /admin/guards` | 401 | 403 | 403 | ✅ | Sin restricción adicional | BE-06 |
| 21 | `POST /admin/guards` | 401 | 403 | 403 | ✅ | Crea siempre rol `guard` | BE-06 |
| 22 | `GET /admin/guards/:id` | 401 | 403 | 403 | ✅ | `assertIsGuardTarget` | BE-06 |
| 23 | `PATCH /admin/guards/:id` | 401 | 403 | 403 | ✅ | `assertIsGuardTarget` | BE-06 |
| 24 | `DELETE /admin/guards/:id` | 401 | 403 | 403 | ✅ | `assertIsGuardTarget`; baja lógica y revoca sus sesiones | BE-06 |
| 25 | `PUT /admin/guards/:id/coverage` | 401 | 403 | 403 | ✅ | `assertIsGuardTarget` | BE-06 |
| 26 | `POST /admin/alerts/:id/resolve` | 401 | 403 | 403 | ✅ | Solo alertas `escalated`; si no, 409 `INVALID_STATE` | BE-05 |
| 27 | `GET /admin/alerts` | 401 | 403 | 403 | ✅ | Ve todas, sin minimización | BE-07 |
| 28 | `GET /admin/metrics` | 401 | 403 | 403 | ✅ | Sin restricción adicional | BE-07 |
| 29 | `GET /admin/metrics/guards/:id` | 401 | 403 | 403 | ✅ | `NOT_FOUND` si el id no es un guardia | BE-07 |
| 30 | `GET /admin/users` | 401 | 403 | 403 | ✅ | Solo `protected_user` | BE-07 |
| 31 | `GET /admin/users/blocked` | 401 | 403 | 403 | ✅ | Solo bloqueados vigentes | BE-07 |
| 32 | `DELETE /admin/users/:id/block` | 401 | 403 | 403 | ✅ | `NOT_FOUND` si el id no es de un `protected_user` | BE-07 |
| 33 | `GET /events/alerts/active` (SSE) | 401 | ✅ | 403 | 403 | Solo la alerta activa propia | BE-03 |
| 34 | `GET /events/guard/alerts` (SSE) | 401 | 403 | ✅ | 403 | Visibilidad reevaluada por guardia en cada emisión (D22) | BE-04 |
| 35 | `GET /events/guard/alerts/:id` (SSE) | 401 | 403 | ✅ | 403 | `assertGuardCanSee`; si deja de ser visible, evento `NOT_FOUND` y cierre | BE-04 |
| 36 | `GET /events/admin/alerts/escalated` (SSE) | 401 | 403 | 403 | ✅ | Solo alertas `escalated` | BE-05 |

En los canales SSE, 401 y 403 se responden como HTTP normal antes de abrir el stream (D22). Nunca se acepta el token en el query string.

Estado de implementación hoy: solo las filas 1, 3, 4, 5 y 6 tienen handler (módulo `backend/src/modules/auth/routes.ts`). El resto está en `ROUTE_POLICIES` pero la ruta aún no existe; hasta entonces responde 404 por ser inexistente, no por permisos.

## 4. Reglas de propiedad y visibilidad

Código: `backend/src/security/ownership.ts` (funciones puras sobre datos ya cargados, sin consultas) y `backend/src/domain/guard-visibility.ts`. Si no se cumplen lanzan `404 NOT_FOUND`, **nunca** 403: un recurso ajeno no debe revelar que existe (D9, D22).

| Helper | Regla |
|---|---|
| `assertOwnsAlert(alert, user)` | La alerta existe y `alert.userId` es el usuario autenticado. |
| `assertAssignedGuard(alert, user)` | La alerta existe y `alert.guardId` es el guardia autenticado (`arrive`). |
| `assertGuardCanSee(alert, guard, ctx)` | Ver abajo. |
| `assertIsGuardTarget(target)` | El objetivo de `/admin/guards/:id` existe y tiene rol `guard`. Si no, `404` con el mensaje "No encontramos a ese guardia". |

### Visibilidad del guardia (`assertGuardCanSee`, D22)

Una alerta es visible para el guardia si:

1. **Está asignada a él** (`guardId` igual a su id), o
2. **Está disponible para él**, y deben cumplirse todas estas condiciones:
   - el guardia está activo (no dado de baja ni bloqueado);
   - la alerta está en `searching` (esta condición se omite con `skipStatusCheck`);
   - el guardia no la ignoró (`alert_ignores`);
   - la alerta tiene ubicación y el guardia tiene cobertura, y el punto cae dentro del radio de cobertura (centro + `radiusMeters`, distancia Haversine en metros, borde incluido; `backend/src/domain/geo.ts`). `zone` es solo una etiqueta y no filtra;
   - el turno está vigente en la zona horaria `TZ_SHIFTS`: intervalo `[inicio, fin)`, admite cruce de medianoche (22:00 a 06:00) e inicio igual a fin significa 24 h (`backend/src/domain/shift.ts`).

`accept` usa `skipStatusCheck: true`: si la alerta no es visible, `404 NOT_FOUND`; si es visible pero ya no está en `searching`, `409 ALERT_TAKEN` (G-05). Además el `UPDATE ... WHERE status = 'searching'` es atómico.

### Minimización de datos (D23)

- `userPhone` es `null` salvo para el guardia **asignado** mientras la alerta esté activa. En `/guard/history` y en `guard/alerts` siempre `null`.
- Para el rol `guard`, `location` es `null` cuando la alerta ya no está activa (historial y `GET /guard/alerts/:id` de alertas no activas).
- `photoUrl` **se conserva** como evidencia de las alertas que atendió.
- `userName` y `evidenceIncomplete` conservan su valor real. El admin ve todo; el dueño ve su alerta completa.
- Aplica a REST y SSE.

## 5. Cómo agregar una ruta nueva

1. Agrega la entrada `'MÉTODO /ruta': <política>` en `ROUTE_POLICIES` (`backend/src/security/policies.ts`). Sin ella, la API no arranca.
2. Registra la ruta bajo el prefijo `/api/v1` con la misma notación `:id`. Si declaras `config.roles`/`public`/`auth`, debe coincidir con la central.
3. Si la ruta toca recursos de otro usuario, usa el helper de `ownership.ts` que corresponda (404, nunca 403). Si hace falta una regla nueva, agrégala ahí como función pura y con pruebas unitarias.
4. Aplica la minimización de datos (D23) si devuelve alertas a un guardia.
5. Agrega la fila a la matriz de pruebas de permisos (`backend/tests/integration/seguridad/matriz-permisos.test.ts`) y verifica anónimo, cada rol y recurso ajeno.
6. Actualiza este documento (sección 3) y `docs/API_CONTRATO.md`.

Advertencia sobre hooks: Fastify ejecuta los hooks `onRequest` de **instancia** antes que los de ruta, o sea **antes de `authenticate`**. Cualquier hook `onRequest` global que se agregue en el futuro corre sin autenticar: no debe leer el cuerpo ni datos sensibles.

Notas de reglas:

- `skipStatusCheck` solo decide entre 404 y 409 en `accept`; nunca devuelve datos.
- "Disponible" para un guardia exige además `guardId` nulo (alerta sin asignar).
- `POST /auth/session` tiene el mismo rate limit que `refresh` (`RATE_LIMIT_REFRESH_MAX` / `RATE_LIMIT_REFRESH_WINDOW`).

### Pendientes para tarjetas siguientes

- **Usuario bloqueado:** pasa `authenticate` (el login lo permite a propósito). `POST /alerts` (BE-03) debe responder `USER_BLOCKED`, y la visibilidad del guardia debe usar `active = isActive && !bloqueado`.
- **`POST /auth/register` (BE-02):** debe forzar `role = protected_user` e ignorar cualquier `role` del cuerpo (el `.strict()` ya rechaza claves extra).
- **`POST /alerts/:id/confirm` (BE-03):** exige guardia asignado y estado `guard_arrived`; el guardia nunca cierra la alerta.

## 6. Cómo se prueba

Desde `backend/`: `npm test`. Archivos relacionados con permisos y sesión que existen hoy:

- `backend/tests/unit/auth.test.ts`
- `backend/tests/integration/auth/login-jwt.test.ts`
- `backend/tests/integration/auth/refresh-logout-session.test.ts`
- `backend/tests/integration/auth/endurecimiento.test.ts`
- `backend/tests/integration/auth/logs-sin-prisma.test.ts`
- `backend/tests/integration/auth/helpers.ts` (utilidades)
- `backend/tests/integration/seguridad/matriz-permisos.test.ts` (matriz rol × ruta)
- `backend/tests/integration/seguridad/deny-by-default.test.ts` (el arranque aborta si una ruta no tiene política)
- `backend/tests/unit/politicas-contrato.test.ts` (política central contra el contrato)
- `backend/tests/unit/geo-turno-visibilidad.test.ts` (Haversine, turnos y visibilidad del guardia)
