# SafeLink — Backend

API de SafeLink: Node.js + TypeScript (strict) + Fastify. PostgreSQL 16 con Prisma 7. Autenticación con JWT y refresh token (argon2) ya disponible; SSE más adelante.

## Requisitos

- Node.js 24 LTS (ver `.nvmrc`)
- npm 11 o superior
- Docker Desktop (para Postgres y para correr la API en contenedor)

## Arranque rápido

```bash
cd backend
cp .env.example .env        # edita JWT_SECRET (mínimo 32 caracteres) y la contraseña de Postgres
npm install                 # también genera el cliente de Prisma (postinstall)
npm run db:up               # Postgres local (puerto host DB_PORT, por defecto 5433)
npm run db:migrate          # aplica las migraciones
npm run db:seed             # datos de demostración (solo desarrollo)
npm run dev                 # API en http://localhost:3000
curl http://localhost:3000/health
```

Para levantar todo en contenedores: `docker compose up --build`. Para apagar: `docker compose down` (sin `-v`, para conservar los datos).

## Scripts

| Script | Descripción |
|---|---|
| `npm run dev` | API en modo desarrollo (recarga al guardar, lee `.env`) |
| `npm run build` | Compila a `dist/` |
| `npm start` | Ejecuta `dist/server.js` (requiere variables de entorno ya cargadas) |
| `npm run typecheck` | Verificación de tipos |
| `npm run lint` | ESLint |
| `npm test` | Pruebas con Vitest. Las unitarias no necesitan `.env`; las de integración (`tests/integration/db/`) requieren `npm run db:up`, `npm run db:test:create`, `npm run db:test:deploy` y `DATABASE_URL_TEST` en `.env` |
| `npm run db:up` | Levanta Postgres (`docker compose up -d db`) |
| `npm run db:generate` | Genera el cliente de Prisma en `src/generated` (ignorado por git) |
| `npm run db:migrate` | `prisma migrate dev`: aplica migraciones y crea nuevas con `--name` |
| `npm run db:deploy` | `prisma migrate deploy`: aplica migraciones pendientes (sin crear) |
| `npm run db:seed` | Semilla idempotente; exige `NODE_ENV=development` o `test` definido de forma explícita (`.env.example` ya trae `NODE_ENV=development`) y se niega en cualquier otro caso, incluido no definido |
| `npm run db:reset` | `prisma migrate reset --force`: BORRA la base de desarrollo y reaplica migraciones; luego corre `npm run db:seed`. Solo desarrollo; Prisma exige que lo ejecute una persona |
| `npm run db:test:create` | Crea la base `safelink_test` (nombre tomado de `DATABASE_URL_TEST`) si no existe |
| `npm run db:test:deploy` | Aplica las migraciones a la base de pruebas |
| `npm run db:test:reset` | Borra y recrea la base de pruebas (sin semilla) |

## Base de datos

- Modelo en `prisma/schema.prisma`; migraciones en `prisma/migrations/` (no edites una ya aplicada: crea otra).
- La migración inicial incluye a mano los `CHECK` y el índice único parcial (una alerta activa por usuario), que Prisma no puede expresar en el esquema; `restricciones_extra` agrega más `CHECK`.
- `POSTGRES_PASSWORD` va dentro de la URL sin codificar: genérala solo con caracteres seguros, por ejemplo `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`.
- `docker-compose.yml` exige `JWT_SECRET` (`:?`) incluso para `docker compose up -d db` y para los scripts `db:test:*`: defínelo en `.env` antes de levantar la base. Genera uno fuerte con el comando de la sección de secretos; nunca uno débil solo para destrabar.
- Una variable vacía en `.env` (por ejemplo `GEOFENCE_METERS=`) hace que la API no arranque: bórrala o dale valor.
- Prisma 7: la URL de la base se lee de `prisma.config.ts` (carga `backend/.env`). El cliente usa el adaptador `pg` (`src/db/prisma.ts`).
- Semilla: mismas cuentas del front (contraseña `SafeLink1`), turnos relativos a la hora de ejecución, alertas activas en cada estado. Cada corrida la reinicia.
- Docker Compose: el servicio `migrate` aplica las migraciones y termina; la API espera a que acabe.
- Pruebas de integración: `npm run db:test:create && npm run db:test:deploy`.

## Configuración

Todo se define por variables de entorno (ver `.env.example`). Si alguna es inválida, la API no arranca y lista cuáles. Por defecto `HOST=127.0.0.1` (solo tu equipo); pon `HOST=0.0.0.0` en tu `.env` únicamente para probar con el teléfono en la misma red local (LAN). En Docker Compose la API usa `0.0.0.0` dentro del contenedor y publica el puerto `PORT` solo en `127.0.0.1` (pon `API_BIND=0.0.0.0` en `.env` para probar con el teléfono por LAN), y solo recibe las variables que usa su esquema (no `POSTGRES_PASSWORD` ni `DATABASE_URL_TEST`); mientras que Postgres se publica solo en `127.0.0.1`. **Advertencia:** no expongas la API con `HOST=0.0.0.0` o `API_BIND=0.0.0.0` fuera de una red de confianza (tu LAN de pruebas). Aún no hay TLS ni proxy inverso: las contraseñas y los tokens viajarían en claro, y el rate limit es por IP y en memoria. Los valores de dominio (geocerca, timeouts, etc.) equivalen a `lib/dominio/configuracion.dart`; `ADMIN_NOTE_MAX_LENGTH` equivale a `lib/dominio/regla_alerta.dart`.

### Variables de autenticación

| Variable | Por defecto | Descripción |
|---|---|---|
| `NODE_ENV` | `production` si falta | `development`, `test` o `production`. Para trabajar en local ponla explícita en `.env` (`NODE_ENV=development`; `.env.example` ya la trae). La semilla exige `development` o `test` |
| `JWT_SECRET` | (obligatoria) | Mínimo 32 caracteres |
| `JWT_ACCESS_EXPIRES_IN` | `15m` | Vigencia del access token |
| `JWT_REFRESH_EXPIRES_IN` | `30d` | Vigencia de cada refresh token (deslizante: cada refresh renueva el plazo) |
| `REFRESH_GRACE_SECONDS` | `5` | Entero de 0 a 60. Segundos en que un refresh token recién rotado se acepta una vez más (dos refresh concurrentes legítimos). `0` desactiva la gracia. Reutilizarlo fuera de ese plazo revoca toda la sesión |
| `JWT_SESSION_MAX_AGE` | `90d` | Vida máxima absoluta de una sesión aunque se siga rotando el refresh token; al superarla, el refresh responde 401 |
| `RATE_LIMIT_LOGIN_MAX` / `RATE_LIMIT_LOGIN_WINDOW` | `10` / `1m` | Intentos máximos por IP y ventana de `POST /auth/login` (memoria del proceso). Al excederse: 429 `TOO_MANY_REQUESTS` con `Retry-After` |
| `RATE_LIMIT_REFRESH_MAX` / `RATE_LIMIT_REFRESH_WINDOW` | `30` / `1m` | Lo mismo para `POST /auth/refresh` |
| `ARGON2_MEMORY_KIB` / `ARGON2_TIME_COST` / `ARGON2_PARALLELISM` | `65536` / `3` / `4` | Parámetros de argon2id. Si los cambias, los hashes viejos se actualizan solos en el siguiente login correcto |

Formato de `JWT_ACCESS_EXPIRES_IN`, `JWT_REFRESH_EXPIRES_IN`, `JWT_SESSION_MAX_AGE` y las ventanas del rate limit: entero positivo (hasta 6 dígitos, sin ceros a la izquierda) seguido de `s`, `m`, `h` o `d`; por ejemplo `900s`, `15m`, `12h`, `30d`. Otro formato (como `15` o `1.5h`) impide el arranque.

### Probar la autenticación

Con la API corriendo (`npm run dev`) y la semilla aplicada. La contraseña `SafeLink1` de las cuentas demo es **solo para desarrollo local**. Las rutas viven bajo `/api/v1`.

```bash
BASE=http://127.0.0.1:3000/api/v1

# 1. Login (cuenta demo del usuario protegido)
curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"usuario@safelink.mx","password":"SafeLink1"}'
# data = User + accessToken + refreshToken. Copia ambos tokens:
ACCESS='<accessToken>'
REFRESH='<refreshToken>'

# 2. Usuario de la sesión
curl -s "$BASE/auth/me" -H "Authorization: Bearer $ACCESS"

# 3. Renovar: devuelve tokens nuevos; el refresh anterior deja de servir
curl -s -X POST "$BASE/auth/refresh" -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"$REFRESH\"}"

# 4. Cerrar sesión (usa el access token vigente; revoca la sesión completa)
curl -s -X POST "$BASE/auth/logout" -H "Authorization: Bearer $ACCESS"
```

Tras el logout, `GET /auth/me` con ese access token responde `401 UNAUTHORIZED` aunque no haya vencido. En el paso 3, repetir el mismo refresh dentro de `REFRESH_GRACE_SECONDS` se acepta una vez; después se revoca la sesión.

**PowerShell (Windows PowerShell 5.1 y PowerShell 7.3+):** usa `Invoke-RestMethod` con `ConvertTo-Json`; no depende de cómo cada versión pase las comillas a programas externos.

```powershell
$base = "http://127.0.0.1:3000/api/v1"

# 1. Login
$login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -ContentType "application/json" `
  -Body (@{ email = "usuario@safelink.mx"; password = "SafeLink1" } | ConvertTo-Json)
$access  = $login.data.accessToken
$refresh = $login.data.refreshToken

# 2. Usuario de la sesión
Invoke-RestMethod -Uri "$base/auth/me" -Headers @{ Authorization = "Bearer $access" }

# 3. Renovar (devuelve tokens nuevos; el refresh anterior deja de servir)
$nuevo = Invoke-RestMethod -Method Post -Uri "$base/auth/refresh" -ContentType "application/json" `
  -Body (@{ refreshToken = $refresh } | ConvertTo-Json)
$access = $nuevo.data.accessToken

# 4. Cerrar sesión
Invoke-RestMethod -Method Post -Uri "$base/auth/logout" -Headers @{ Authorization = "Bearer $access" }
```

Si prefieres `curl.exe`, guarda el cuerpo en un archivo y envíalo tal cual (evita problemas de comillas):

```powershell
Set-Content -Path login.json -Value '{"email":"usuario@safelink.mx","password":"SafeLink1"}' -Encoding ascii
curl.exe -s -X POST "$base/auth/login" -H "Content-Type: application/json" --data-binary "@login.json"
Remove-Item login.json
```

> Un error de la API (por ejemplo 401) hace que `Invoke-RestMethod` lance una excepción; el cuerpo con el código de error está en la propiedad `ErrorDetails.Message` de la excepción.

### Secretos

Genera `JWT_SECRET` con:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

La contraseña de Postgres (`POSTGRES_PASSWORD`, y la misma dentro de `DATABASE_URL`) también debe ser aleatoria; no uses el valor de ejemplo.

## Más documentación

- [Contrato de la API](../docs/API_CONTRATO.md)
- [Decisiones de diseño](../docs/DECISIONES.md)
- [Modelo de datos](../docs/MODELO_DATOS.md)
- [Permisos por rol (deny-by-default)](../docs/PERMISOS.md)
- [Conectar un dispositivo físico](../docs/CONEXION_DISPOSITIVO.md)

## BE-01: criterios de terminado

| Criterio | Evidencia | Estado |
|---|---|---|
| Tablas de usuarios, guardias, alertas y turnos; campos de rol, estado, coordenadas, rumbo, foto, método de disparo y marca de tiempo | `prisma/schema.prisma`, migraciones `20261112024720_init`, `20261112030815_restricciones_extra`, `20261112042801_refresh_family_started_at`; turnos = `shift_start`/`shift_end` en `guard_profiles` (D1) | ✅ |
| El modelo de datos está documentado | `docs/MODELO_DATOS.md` (diagrama ER, diccionario, restricciones, máquina de estados) | ✅ |
| Contratos de lectura y escritura documentados | `docs/API_CONTRATO.md` (31 rutas del front + `/auth/refresh`, 4 canales SSE, errores, formas JSON), `docs/DECISIONES.md` (D1–D29) | ✅ |
| Cada rol solo puede leer y escribir lo que le corresponde | Registro central `src/security/policies.ts` (deny-by-default: el arranque falla si una ruta no tiene política); `tests/integration/seguridad/matriz-permisos.test.ts` (36 entradas × anónimo, protected_user, guard, admin con BD real); `tests/unit/politicas-contrato.test.ts` (paridad con `lib/datos/safelink_service.dart`); `docs/PERMISOS.md` | ✅ |
| Servicio de backend configurado | `docker compose up -d db` + `npm run dev`; `docker compose build migrate api` y `docker compose up -d api` levantan la API y `GET /health` responde `{"data":{"status":"ok"}}` | ✅ |
| Migraciones y semilla desde cero | `npm run db:deploy` + `npm run db:seed` (idempotente; 44 cuentas, 8 guardias, 30 alertas); `tests/integration/db/semilla.test.ts` | ✅ |
| `npm run typecheck`, `lint` y `test` en verde | 20 archivos de prueba, 742 pruebas (unitarias, integración con Postgres real, contrato y permisos); app: `flutter analyze` sin observaciones y `flutter test` 338 pruebas | ✅ |
| La app se conecta al backend en un dispositivo físico | Cliente HTTP en `lib/datos/http_safelink_service.dart` (`--dart-define=API_URL=...`), guía `docs/CONEXION_DISPOSITIVO.md` y `npm run verificar:conexion`. `flutter analyze` y `flutter test` en verde | ⏳ Verificación en el teléfono a cargo de la responsable (checklist de la sección 9 de la guía) |
| PR hacia `develop` aprobado | — | ⏳ Pendiente de revisión del equipo |

Pendientes conocidos que no son de BE-01 (detalle en `docs/DECISIONES.md`, "Pendientes de seguridad"): rate limit de `register` (BE-02); refresh token en almacenamiento seguro (Keystore/Keychain) antes de producción; permiso `INTERNET` en el manifest `main` de Android para un build release; `JWT_SECRET` de alta entropía y rate limit por cuenta antes de cualquier despliegue.

## Aviso: OneDrive y rutas con espacios

El repo está dentro de OneDrive y la ruta contiene espacios. `node_modules` tiene miles de archivos y OneDrive puede ralentizar la sincronización o bloquear archivos: considera excluir `backend/node_modules` de la sincronización. Entrecomilla cualquier ruta con espacios al usar la terminal.
