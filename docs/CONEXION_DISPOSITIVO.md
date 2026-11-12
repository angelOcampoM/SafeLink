# Conectar un teléfono Android físico al backend

Cubre: D4 (conexión de la app a un dispositivo físico) y las historias U-02 y G-01 (inicio de sesión).
Tarjeta: BE-01 (paso 7, `docs(BE-01): guía para conectar un dispositivo físico`).

> Estado: la app ya tiene un cliente HTTP mínimo (`lib/datos/http_safelink_service.dart`), que se activa con `--dart-define=API_URL=...`. Sin `API_URL` la app sigue en modo simulado (memoria).

## 1. Requisitos

- Docker Desktop.
- Node.js 24 LTS (ver `backend/.nvmrc`).
- Teléfono Android con **depuración USB** activada y cable de datos.
- `adb` en el PATH (viene con Android SDK platform-tools). Comprueba con `adb version`.
- Opción B (LAN): PC y teléfono en la misma red Wi-Fi.

## 2. Levantar el backend

En `backend/` (primera vez: `cp .env.example .env`, define `JWT_SECRET` de al menos 32 caracteres y una contraseña de Postgres aleatoria; **nunca subas `.env`**).

```powershell
cd backend
npm install
npm run db:up        # Postgres en 127.0.0.1:5433 (DB_PORT)
npm run db:deploy    # aplica las migraciones
npm run db:seed      # datos de demostración; exige NODE_ENV=development (o test) en .env
npm run dev          # API en http://127.0.0.1:3000
```

`.env.example` ya trae `NODE_ENV=development`. Sin esa variable la API asume `production` y la semilla se niega a correr (D28).

Comprueba desde la PC:

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health
```

Debe responder `data.status = ok`. Ojo: `/health` no consulta la base de datos; confirma solo que la API está arriba.

## 3. Opción A (recomendada): `adb reverse`

El teléfono usa su propio `127.0.0.1:3000` y `adb` lo redirige por el cable USB a la PC.

```powershell
adb devices                       # el teléfono debe aparecer como "device"
adb reverse tcp:3000 tcp:3000
adb reverse --list                # verifica la regla
```

En el teléfono, la API es `http://127.0.0.1:3000/api/v1`.

- No requiere abrir el firewall de Windows.
- No requiere `HOST=0.0.0.0`: la API se queda en `127.0.0.1` y no queda expuesta a la red.
- La regla se pierde al desconectar el cable o reiniciar `adb`: **repite `adb reverse` cada vez que reconectes**.
- Si cambias `PORT` en `.env`, ajusta ambos puertos.

## 4. Opción B: por la red local (LAN)

Úsala si no puedes usar cable.

1. Expón la API en todas las interfaces:
   - con `npm run dev`: pon `HOST=0.0.0.0` en `.env` y reinicia;
   - con Docker Compose: pon `API_BIND=0.0.0.0` en `.env` y levanta con `docker compose up --build` (por defecto se publica en `127.0.0.1`).
2. Obtén la IP de la PC con `ipconfig` (adaptador Wi-Fi, "Dirección IPv4", por ejemplo `192.168.1.50`).
3. Abre el puerto en el firewall de Windows, solo para el perfil Privado (PowerShell como administrador):

   ```powershell
   New-NetFirewallRule -DisplayName "SafeLink API (desarrollo)" -Direction Inbound -Protocol TCP -LocalPort 3000 -Profile Private -RemoteAddress LocalSubnet -Action Allow
   ```

   Para quitarla al terminar: `Remove-NetFirewallRule -DisplayName "SafeLink API (desarrollo)"`. Si Windows clasificó tu Wi-Fi como "Pública", la regla no aplicará: cambia la red a Privada solo si confías en ella.
4. En el teléfono, la API es `http://<IP-de-la-PC>:3000/api/v1`.

Advertencias:

- **Seguridad:** con la API expuesta en la LAN, cualquier equipo de la red puede iniciar sesión como `admin@safelink.mx` con la contraseña de semilla publicada (`SafeLink1`). Úsala solo en una red de confianza y **baja la API al terminar** (o regresa `HOST`/`API_BIND` a `127.0.0.1`).
- La API **no tiene TLS** y el rate limit es por IP y en memoria: contraseñas y tokens viajan en claro. No uses esta opción en redes públicas ni escolares sin aislamiento.
- Con Docker Desktop y `API_BIND=0.0.0.0`, la publicación del puerto la gestiona Docker y **no depende de la regla de firewall de arriba**; esa regla aplica a `npm run dev`. Con Docker, el control real es `API_BIND`.
- Muchas redes escolares tienen **AP isolation** (los clientes no se ven entre sí) y la conexión falla aunque todo esté bien. En ese caso usa un **hotspot** del teléfono (la PC se conecta a él) o la opción A.
- Al terminar, regresa `HOST` y `API_BIND` a `127.0.0.1`.

CORS: la app móvil no es un navegador y no necesita `CORS_ORIGINS` (vacío = ninguno). Solo afectaría a un cliente web.

## 5. Tráfico HTTP sin cifrar en Android

Las URLs de esta guía son `http://`, no `https://`. Android (API 28 o superior) bloquea el tráfico en claro para las apps que usan la pila de red de Android (`usesCleartextTraffic="false"` por defecto desde API 28).

- Ya se agregó `<application android:usesCleartextTraffic="true" />` **solo** en `android/app/src/debug/AndroidManifest.xml` (builds de depuración). El manifest `main` no lo tiene, así que un release no permite `http://`.
- **Pendiente de confirmar en un teléfono real:** no se ha comprobado en un dispositivo físico si hacía falta (Dart usa `dart:io` y quizá no aplique la política de cleartext de Android). Forma parte de la verificación final (sección 9).

Hallazgo: el permiso `android.permission.INTERNET` está declarado solo en los manifests `debug` y `profile` (`android/app/src/debug/AndroidManifest.xml` y `android/app/src/profile/AndroidManifest.xml`). `android/app/src/main/AndroidManifest.xml` no lo tiene. Un build **release** no podría conectarse a la red. Hay que agregarlo al manifest `main` antes de generar un APK de entrega. Es un cambio en `android/`, fuera del alcance de este paso: queda como pendiente a confirmar con la responsable.

## 6. Ejecutar la app contra el backend

Con el teléfono conectado y la opción A activa (desde la raíz del repo):

```powershell
flutter run --dart-define=API_URL=http://127.0.0.1:3000/api/v1
```

Con la opción B: `flutter run --dart-define=API_URL=http://<IP-de-la-PC>:3000/api/v1`.

Cómo elige `lib/main.dart` el servicio:

- Con `API_URL`: usa el backend real (`HttpSafeLinkService`).
- Con `--dart-define=USAR_NUBE=true` y sin `API_URL`: usa el servicio simulado "nube" (en memoria).
- Sin ninguno (por defecto): repositorios en memoria.

Qué hace el cliente (`lib/datos/http_safelink_service.dart`, `lib/datos/almacen_tokens.dart`):

- **Tokens:** el access token vive solo en memoria; el refresh token se guarda en `SharedPreferences` (texto plano en el teléfono). Es aceptable para el prototipo; **en producción debe ir a almacenamiento seguro (Keystore/Keychain)**.
- Manda `Authorization: Bearer` en todas las rutas salvo `/auth/login`, `/auth/register` y `/auth/refresh`.
- **Al reabrir la app** hace `POST /auth/refresh` antes de `POST /auth/session`.
- **Ante un 401 `UNAUTHORIZED`** hace un solo refresh compartido entre peticiones concurrentes y reintenta la petición una vez. Si el refresh es rechazado, borra los tokens.
- **Logout:** borra los tokens locales aunque el servidor falle. Si el access token ya venció, primero hace refresh y reintenta, para revocar la sesión también en el servidor.
- **HTTPS en release/profile:** en esos modos la app rechaza un `API_URL` sin `https` y se queda en modo memoria (`urlApiPermitida` en `lib/datos/url_api.dart`, evaluada en `lib/main.dart`). En debug se permite `http://`.
- **Respaldo de Android:** `android:allowBackup="false"` en el manifest `main`, para que el refresh token no entre al respaldo del teléfono.
- **Hallazgo pendiente:** el permiso `INTERNET` no está en el manifest `main` (solo en debug/profile). Un build release no tendría red; hay que resolverlo en la tarjeta que haga el build release.
- **Errores de red**, tiempo agotado (15 s) o respuestas que no son JSON del backend se convierten en `SERVICE_UNAVAILABLE`.
- **Tiempo real:** aún no disponible. `escuchar()` emite `SERVICE_UNAVAILABLE` ("Tiempo real disponible en una tarjeta posterior") hasta BE-03/BE-04.

Cuentas de la semilla (`backend/prisma/seed.ts`), contraseña `SafeLink1` (solo desarrollo): `usuario@safelink.mx` (protected_user), `guardia@safelink.mx` (guard), `admin@safelink.mx` (admin).

## 7. Script de verificación

`backend/scripts/verificar-conexion.ps1` (solo Windows, PowerShell 5.1 o 7+). No lee ni imprime `.env`. Parámetros: `-Port` (por defecto 3000; usa tu `PORT`) y `-AplicarReverse` (si falta la regla, ejecuta `adb reverse tcp:<Port> tcp:<Port>`; sin él solo muestra el comando).

Comprobaciones, en orden:

1. Docker responde.
2. Contenedor `db` en ejecución y `healthy`.
3. `GET http://127.0.0.1:<Port>/health` desde la PC con `data.status = ok`.
4. `adb` en el PATH y al menos un dispositivo en estado `device` (avisa si hay varios, o `unauthorized`/`offline`).
5. Regla `adb reverse tcp:<Port>`.
6. `/health` desde el teléfono con `adb shell` usando `curl` o `wget`. Es opcional: si no hay ninguno o no responde, solo avisa y no cuenta como fallo.

Termina con código 0 si lo esencial (1 a 5) está bien y con código 1 si algo falló.

Cómo correrlo, desde `backend/`:

```powershell
npm run verificar:conexion -- -AplicarReverse
```

El script de npm es `powershell -ExecutionPolicy Bypass -File scripts/verificar-conexion.ps1`; lo que va después de `--` se pasa al script. Equivalente directo:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verificar-conexion.ps1 -AplicarReverse
```

Ejemplo de salida (todo bien; los textos reales vienen del script, con marcas de color):

```text
Verificacion de conexion SafeLink (puerto 3000)

1. Docker
  ✔ Docker responde.

2. Base de datos (contenedor db)
  ✔ Contenedor backend-db-1 healthy.

3. API desde la PC
  ✔ GET http://127.0.0.1:3000/health respondio ok.

4. adb y dispositivo
  ✔ adb encontrado.
  ✔ Dispositivos conectados: 1 (R58M123ABCD).

5. adb reverse tcp:3000
  ✔ Regla aplicada: adb reverse tcp:3000 tcp:3000

6. API desde el telefono (opcional)
  ✔ El telefono alcanza http://127.0.0.1:3000/health.

✔ Todo lo esencial esta bien. En la app: --dart-define=API_URL=http://127.0.0.1:3000/api/v1
```

El nombre del contenedor y el serial del teléfono son ilustrativos. Cuando algo falla, la línea lleva ✘ y debajo una flecha `->` con la acción sugerida.

## 8. Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `EADDRINUSE` al iniciar | El puerto 3000 está ocupado (otra API o el contenedor `api`) | `Get-NetTCPConnection -LocalPort 3000` para ver el proceso; ciérralo o cambia `PORT` |
| `ECONNREFUSED` o "connection refused" en el teléfono | API apagada, `adb reverse` perdido o puerto distinto | Revisa `/health` en la PC y repite `adb reverse tcp:3000 tcp:3000` |
| Funciona en la PC, no por LAN | API en `127.0.0.1`, firewall, AP isolation o red Pública | `HOST=0.0.0.0`, regla de firewall en perfil Privado, probar con hotspot |
| `docker compose` pide `JWT_SECRET` o `POSTGRES_PASSWORD` | Faltan en `.env` | Defínelos (compose los exige incluso para `db:up`) |
| La semilla se niega a correr | `NODE_ENV` no es `development` ni `test` | Pon `NODE_ENV=development` en `.env` |
| `401 UNAUTHORIZED` con credenciales o token válidos | Reloj del teléfono desfasado: el JWT dura 15 min y se valida con `iat`/`exp` | Activa la hora automática del teléfono y reintenta |
| `429 TOO_MANY_REQUESTS` | Rate limit por IP: login 10 por minuto, refresh 30 por minuto (D29) | Espera lo que indique `Retry-After` o sube `RATE_LIMIT_LOGIN_MAX` en `.env` solo para pruebas |
| `adb devices` no muestra el teléfono | Depuración USB apagada, cable solo de carga o autorización pendiente | Acepta el aviso de depuración en el teléfono; prueba otro cable o `adb kill-server` y `adb devices` |

## 9. Lista de verificación final (la haces tú, en el teléfono)

Antes: teléfono con depuración USB y la hora automática activadas, conectado por cable.

1. [ ] En `backend/`: `npm run db:up`, `npm run db:deploy` y `npm run db:seed` (con `NODE_ENV=development` en `.env`).
2. [ ] `npm run dev` y, en otra terminal, `npm run verificar:conexion -- -AplicarReverse`. Esperado: todas las comprobaciones 1 a 5 con ✔ y exit 0.
3. [ ] En la raíz del repo: `flutter run --dart-define=API_URL=http://127.0.0.1:3000/api/v1` (opción A) o con la IP LAN (opción B).
4. [ ] **Cleartext:** confirma que la app llega al backend por `http://`. Si el login responde "servicio no disponible" aunque el script esté en verde, el cleartext del manifest debug no está funcionando y hay que revisarlo. Este punto sigue sin confirmarse en un teléfono real.
5. [ ] Inicia sesión con cada cuenta (contraseña `SafeLink1`, solo desarrollo): `usuario@safelink.mx`, `guardia@safelink.mx` y `admin@safelink.mx`. Esperado: entra a la pantalla de su rol. Una contraseña incorrecta muestra el mensaje de credenciales inválidas.
6. [ ] Cierra la app por completo y ábrela de nuevo. Esperado: entra directo sin pedir login (restaura la sesión con refresh y `/auth/session`).
7. [ ] Cierra sesión. Esperado: vuelve al login; al reabrir la app ya no restaura la sesión.
8. [ ] Al terminar: `HOST` y `API_BIND` de vuelta en `127.0.0.1`, regla de firewall eliminada, `adb reverse --remove tcp:3000` si ya no la usas.

Qué esperar de lo que aún no existe: hoy el backend solo implementa `login`, `refresh`, `logout`, `me` y `session` (ver `docs/PERMISOS.md`). Las pantallas que usen rutas pendientes (alertas, guardia, administración, ajustes) mostrarán un error `NOT_FOUND`, y todas las que dependan de tiempo real mostrarán `SERVICE_UNAVAILABLE`, hasta las tarjetas BE-02 a BE-07. Eso es normal en esta tarjeta y no es un fallo de conexión.
