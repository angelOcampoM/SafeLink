# SafeLink — Backend

API de SafeLink: Node.js + TypeScript (strict) + Fastify. Más adelante: PostgreSQL 16, Prisma, JWT y SSE.

## Requisitos

- Node.js 24 LTS (ver `.nvmrc`)
- npm 11 o superior
- Docker Desktop (para Postgres y para correr la API en contenedor)

## Arranque rápido

```bash
cd backend
cp .env.example .env        # edita JWT_SECRET (mínimo 32 caracteres) y la contraseña de Postgres
npm install
docker compose up -d db     # Postgres local (puerto host DB_PORT, por defecto 5433)
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
| `npm test` | Pruebas con Vitest (no necesitan `.env`) |

## Configuración

Todo se define por variables de entorno (ver `.env.example`). Si alguna es inválida, la API no arranca y lista cuáles. Por defecto `HOST=127.0.0.1` (solo tu equipo); pon `HOST=0.0.0.0` en tu `.env` únicamente para probar con el teléfono en la misma red local (LAN). En Docker Compose la API usa `0.0.0.0` dentro del contenedor y publica el puerto `PORT` (accesible por LAN), mientras que Postgres se publica solo en `127.0.0.1`. Los valores de dominio (geocerca, timeouts, etc.) equivalen a `lib/dominio/configuracion.dart`; `ADMIN_NOTE_MAX_LENGTH` equivale a `lib/dominio/regla_alerta.dart`.

### Secretos

Genera `JWT_SECRET` con:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

La contraseña de Postgres (`POSTGRES_PASSWORD`, y la misma dentro de `DATABASE_URL`) también debe ser aleatoria; no uses el valor de ejemplo.

## Aviso: OneDrive y rutas con espacios

El repo está dentro de OneDrive y la ruta contiene espacios. `node_modules` tiene miles de archivos y OneDrive puede ralentizar la sincronización o bloquear archivos: considera excluir `backend/node_modules` de la sincronización. Entrecomilla cualquier ruta con espacios al usar la terminal.
