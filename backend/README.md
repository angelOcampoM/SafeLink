# SafeLink — Backend

API de SafeLink: Node.js + TypeScript (strict) + Fastify. PostgreSQL 16 con Prisma 7. Más adelante: JWT y SSE.

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

Todo se define por variables de entorno (ver `.env.example`). Si alguna es inválida, la API no arranca y lista cuáles. Por defecto `HOST=127.0.0.1` (solo tu equipo); pon `HOST=0.0.0.0` en tu `.env` únicamente para probar con el teléfono en la misma red local (LAN). En Docker Compose la API usa `0.0.0.0` dentro del contenedor y publica el puerto `PORT` solo en `127.0.0.1` (pon `API_BIND=0.0.0.0` en `.env` para probar con el teléfono por LAN), y solo recibe las variables que usa su esquema (no `POSTGRES_PASSWORD` ni `DATABASE_URL_TEST`); mientras que Postgres se publica solo en `127.0.0.1`. Los valores de dominio (geocerca, timeouts, etc.) equivalen a `lib/dominio/configuracion.dart`; `ADMIN_NOTE_MAX_LENGTH` equivale a `lib/dominio/regla_alerta.dart`.

### Secretos

Genera `JWT_SECRET` con:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

La contraseña de Postgres (`POSTGRES_PASSWORD`, y la misma dentro de `DATABASE_URL`) también debe ser aleatoria; no uses el valor de ejemplo.

## Aviso: OneDrive y rutas con espacios

El repo está dentro de OneDrive y la ruta contiene espacios. `node_modules` tiene miles de archivos y OneDrive puede ralentizar la sincronización o bloquear archivos: considera excluir `backend/node_modules` de la sincronización. Entrecomilla cualquier ruta con espacios al usar la terminal.
