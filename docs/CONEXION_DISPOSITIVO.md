# Conectar un teléfono Android físico al backend

Cubre: D4 (conexión de la app a un dispositivo físico) y las historias U-02 y G-01 (inicio de sesión).
Tarjeta: BE-01 (paso 7, `docs(BE-01): guía para conectar un dispositivo físico`). La sección 10 (push del guardia, G-02, D45) se agregó en BE-04 (paso 12).

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

Hallazgo, **resuelto en BE-07**: `android.permission.INTERNET` estaba declarado solo en los manifests `debug` y `profile`, así que un build **release** no podía conectarse a la red. Ya está en `android/app/src/main/AndroidManifest.xml`, junto con los dos de siempre. Eso **no** habilita tráfico en claro: `usesCleartextTraffic` sigue solo en el manifest `debug`, de modo que un release continúa exigiendo `https://`.

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

## 10. Notificaciones push del guardia (guía para la tarjeta del front)

Cubre: G-02 (recepción de la alerta), soporte de G-03 y G-05. Tarjeta: BE-04 (paso 12). Decisión: D45, el cliente HTTP de `/guard/*`, el `escuchar()` real, Firebase/FCM, el canal de alarma y los permisos van en **una tarjeta aparte del front**; en BE-04 solo se documentan aquí. **No se tocó `lib/`.**

Cómo leer esta sección:

- **[Backend]** lo que el servidor hace hoy, verificado contra el código (`backend/src/notifications/`, `backend/src/modules/devices/`). Formato completo del mensaje en `docs/API_CONTRATO.md`, sección 10.
- **[Recomendación, no verificada]** lo que sugiere la documentación de Flutter, Firebase y Android/iOS, **no comprobado en este repo**: el front aún no integra Firebase y el backend nunca se probó contra FCM real (D43). Verifícalo contra la documentación vigente de cada plataforma antes de implementarlo.

### 10.1 Qué necesita el equipo antes de empezar

- Un proyecto de Firebase con Cloud Messaging habilitado y una app Android (y una iOS si aplica) registradas.
- **[Backend]** Una cuenta de servicio con permiso para enviar mensajes. El backend la lee de `FCM_SERVICE_ACCOUNT_FILE` (ruta a un JSON **fuera del repo**) con `PUSH_PROVIDER=fcm` y `FCM_PROJECT_ID`. Ver `backend/README.md`.
- **La configuración de Firebase del cliente no se sube al repo:** `google-services.json` (Android) y `GoogleService-Info.plist` (iOS) quedan fuera de git, igual que el JSON de la cuenta de servicio. Cada integrante los descarga de su consola de Firebase. El `.gitignore` de la raíz ya ignora `android/app/google-services.json` e `ios/Runner/GoogleService-Info.plist`: colócalos exactamente en esas rutas y confirma con `git status` que no aparecen. Ni la cuenta de servicio ni estos archivos se pegan en `.env`, en issues ni en capturas.

### 10.2 Flujo del token de dispositivo

**[Backend]** `PUT /users/me/device-token`, solo rol `guard`, cuerpo `{ "token": "<token FCM>" }`, responde `200 { "data": null }`.

Flujo que el cliente debe seguir:

1. Iniciar sesión como guardia (`POST /auth/login`).
2. Pedir permiso de notificaciones (sección 10.4) y obtener el token FCM del dispositivo.
3. Enviar el token con `PUT /users/me/device-token`.
4. Volver a registrarlo en cada uno de estos casos (**[Recomendación, no verificada]** para la parte de la API de Firebase; lo del servidor está verificado):
   - cuando Firebase notifique un token nuevo (`onTokenRefresh` en el SDK de Flutter): FCM rota tokens y el anterior deja de servir;
   - después de cada `POST /auth/login` nuevo: el servidor asocia el token a la sesión (`sid`) que lo registró, y solo un login crea una sesión nueva (`/auth/refresh` y `/auth/session` conservan el mismo `sid`, así que no hace falta registrarlo ahí);
   - al abrir la app como guardia, para refrescar `last_seen_at` (idempotente: repetirlo no duplica).
5. En **logout** el servidor borra los tokens de esa sesión; la app no necesita un "desregistrar". También se borran al revocar la sesión por reutilización del refresh. Aun así, conviene borrar el token local de Firebase en el cliente al cerrar sesión **[Recomendación, no verificada]**.

Reglas del servidor que el cliente debe conocer **[Backend]**:

- Formato: 1 a 512 caracteres de `A-Z a-z 0-9 _ : . -`, sin recortar espacios. Otro formato responde `400 INVALID_STATE` `El token del dispositivo no es válido`.
- `401 UNAUTHORIZED` si la sesión ya fue revocada: no reintentar en bucle; ir a login.
- `403 FORBIDDEN` si la cuenta no es guardia.
- `429 TOO_MANY_REQUESTS` (30 por minuto por usuario por defecto): respetar `Retry-After`.
- Si el mismo token se registra desde otra cuenta, **se reasigna** a la última: el teléfono que cambia de cuenta deja de recibir avisos de la anterior. Es un riesgo aceptado (D42): quien obtenga el token push de otro guardia puede quitarle sus avisos (no expone datos); no usarlo como mecanismo de cambio de cuenta.
- Un guardia puede tener varios dispositivos (varios tokens). Un token inválido para FCM se borra solo del lado del servidor tras un envío fallido; vuelve a quedar registrado en cuanto el cliente lo registre de nuevo.

### 10.3 Qué recibe la app

**[Backend]** Mensaje **solo de datos**, valores en texto:

```json
{ "type": "alert", "alertId": "<uuid>", "urgent": "false" }
```

- `urgent` es `"true"` si la alerta se disparó con doble clic de volumen (`shake`).
- No trae nombre, teléfono ni ubicación: hay que pedir el detalle al servidor.
- En Android el mensaje no incluye bloque de notificación: **la app debe construir la notificación local** al recibirlo (en primer plano y, con un manejador de segundo plano, en segundo plano). **[Recomendación, no verificada]** para el manejador de segundo plano y de app terminada: es la forma habitual de FCM, pero el comportamiento con la app cerrada depende del fabricante y de las restricciones de batería.
- En iOS el mensaje trae `aps.alert` con título `SafeLink` y cuerpo `Nueva alerta cerca de ti` (texto fijo del backend) y `sound: default`; el sistema lo muestra si la app tiene permiso.
- Prioridad `HIGH` en Android y `apns-priority: 10` en iOS; vida del mensaje en Android = `ACCEPT_TIMEOUT_SECONDS` (300 s por defecto): un aviso que llega después de ese tiempo ya no tiene sentido.

### 10.4 Android: canal de alarma, pantalla completa y permisos

Todo esto es **[Recomendación, no verificada]**: no existe aún en `lib/` ni en `android/` de este repo.

- **Permiso de notificaciones (Android 13+):** declarar `POST_NOTIFICATIONS` en el manifest y pedirlo en tiempo de ejecución. Sin él, no se muestra la notificación local. El guardia no ve pantalla de permisos al iniciar sesión (decisión del 01/11 en `docs/PLAN_DE_PRUEBAS.md`), así que hay que decidir dónde se pide.
- **Canal de notificación de alta importancia:** crear un canal para alertas (importancia alta, sonido de alarma, vibración, visibilidad pública en pantalla de bloqueo) y usarlo al construir la notificación cuando `urgent == "true"`; para `urgent == "false"` basta un canal de importancia alta normal. Los canales no se pueden endurecer después de creados (el usuario los controla): define bien el nombre y la importancia desde el inicio.
- **Pantalla completa (full-screen intent):** para mostrar la alerta sobre la pantalla de bloqueo, declarar `USE_FULL_SCREEN_INTENT`. A partir de Android 14 es un permiso especial que el usuario puede revocar; hay que comprobarlo y llevarlo a su pantalla de ajustes si falta. Sin él, se degrada a una notificación emergente.
- **Silencio y No molestar:** que suene con el teléfono en silencio depende del canal y de que el usuario no lo haya silenciado; el caso "Recepción en Android con el teléfono en silencio" del plan (G-02) solo se puede comprobar en un dispositivo físico.
- **Optimización de batería:** algunos fabricantes retrasan o descartan mensajes con la app cerrada; documentar la excepción de batería para el guardia.
- **Red:** el manifest `main` aún no declara `INTERNET` (hallazgo de la sección 5); un build release no tendría red ni push hasta resolverlo.

### 10.5 iOS

**[Recomendación, no verificada]** (no hay proyecto iOS configurado para push en este repo):

- Habilitar las capacidades Push Notifications y Background Modes (Remote notifications) y subir la llave APNs a Firebase.
- Pedir el permiso de notificaciones en tiempo de ejecución (alertas y sonido).
- **[Backend]** El texto visible lo manda el servidor en `aps.alert` y es genérico, así que lo que muestra iOS es `SafeLink` / `Nueva alerta cerca de ti`. El `alertId` y `urgent` llegan como datos. iOS no tiene full-screen intent; las alertas críticas (que saltan el silencio) exigen un permiso especial de Apple que este backend no usa.

### 10.6 Qué hacer al tocar el aviso

1. Leer `alertId` de los datos y llevar al guardia a la pantalla de detalle de esa alerta. Si no hay sesión, ir a login y reanudar después.
2. Pedir `GET /guard/alerts/:id` (o abrir el canal `guard/alerts/:id`). **Nunca confiar en el push para autorizar o mostrar datos:** el servidor revalida visibilidad, turno, cobertura y que no esté ignorada.
3. `404 NOT_FOUND` (`La alerta ya no existe`): otro guardia la tomó, se escaló, la cerraron o ya no es visible para este guardia. Mostrar que ya no está disponible.
4. Si sigue en `searching`, el guardia puede aceptar (`POST /guard/alerts/:id/accept`) o ignorarla (`POST /guard/alerts/:id/ignore`). `409 ALERT_TAKEN` significa que otro llegó antes.
5. El push es un complemento: el listado en vivo viene del canal `guard/alerts` (SSE), que el cliente debe reconectar al abrirse la app (D26).

### 10.7 Cómo probar sin FCM

- Con `PUSH_PROVIDER=none` (por defecto) el backend no envía nada; las alertas se ven solo por el canal SSE y `GET /guard/alerts/:id`.
- Para probar el registro del token sin Firebase, basta `PUT /users/me/device-token` con cualquier cadena válida con la sesión de `guardia@safelink.mx`; el token no se valida contra FCM al registrarlo.
- Probar un envío real exige una cuenta de servicio y un teléfono con la app integrada con Firebase: **pendiente**, no se ha hecho. Casos de plan que solo se verifican en dispositivo: ver `docs/PLAN_DE_PRUEBAS.md`.

Qué esperar según el estado real (BE-07): el backend ya implementa **37 de las 38 rutas** del contrato: la sesión (`login`, `refresh`, `logout`, `me`, `session`), el registro y los ajustes, las alertas del usuario, la administración de guardias (alta, lectura, edición y baja), las rutas y canales del guardia, el token de dispositivo, el escalamiento y la resolución de escaladas con el canal `admin/alerts/escalated` (BE-05) y el historial, las métricas y la gestión de usuarios del admin (BE-07; ver `docs/PERMISOS.md`). **Lo único que aún no existe en el backend:** `PUT /admin/guards/:id/coverage` (A-03, BE-06), así que la pantalla de cobertura del admin mostrará `NOT_FOUND`. **Lo que falta en el front:** el `escuchar()` real todavía emite `SERVICE_UNAVAILABLE`, así que las pantallas que dependen de tiempo real lo mostrarán hasta la tarjeta del front (D45); lo mismo para el cliente HTTP de las rutas del guardia. Nada de esto es un fallo de conexión.

---

## 11. Doble clic de volumen con la pantalla bloqueada (U-05)

Agregado en BE-07. La implementación nativa está portada del repositorio que compartió el
profesor (`BOTON-ALERTA-PERMISOS/alerta_utez`) y vive en:

| Archivo | Qué hace |
|---|---|
| `android/app/src/main/kotlin/com/utez/safelink/VolumenAccessibilityService.kt` | Escucha las teclas físicas de volumen a nivel de sistema y emite **cada pulsación** a Flutter |
| `android/app/src/main/kotlin/com/utez/safelink/MainActivity.kt` | Los dos canales (`com.utez.safelink/volumen` y `/volumen_eventos`) |
| `android/app/src/main/res/xml/accesibilidad_volumen.xml` | `flagRequestFilterKeyEvents`: sin esto `onKeyEvent` nunca recibe las teclas de volumen |
| `lib/datos/servicio_disparo_rapido_nativo.dart` | La implementación real del contrato `ServicioDisparoRapido` |

Quién decide si hubo doble clic sigue siendo `ReglaDobleClic` (`lib/dominio/`), que ya estaba
probada: el nativo solo reporta pulsaciones. Las dos capas comparten la ventana de 600 ms
(`ReglaDobleClic.ventanaPorDefecto`, que Flutter le pasa a Kotlin al iniciar).

### Activarlo en el teléfono (hay que hacerlo a mano, una vez)

Android **no deja** que la app encienda un servicio de accesibilidad: es una decisión de la
persona. En la app, Configuración → *Alerta por doble clic de volumen*; si el sistema todavía
no dio el acceso, aparece un aviso amarillo con el botón **Abrir Ajustes**. También a mano:

> Ajustes → Accesibilidad → Apps instaladas → **SafeLink · botón de emergencia** → Activar

En algunos fabricantes (Xiaomi, Huawei, Oppo) hay que además quitarle la optimización de
batería a SafeLink para que el servicio no se duerma.

### Qué comprobar

1. Activa el atajo en Configuración y confirma que el aviso amarillo **desaparece**.
2. Bloquea la pantalla y pulsa volumen dos veces seguidas (menos de 600 ms).
3. El teléfono vibra, la app pasa al frente y queda una alerta nueva.
4. Pulsa volumen **una sola vez**: no debe pasar nada y el volumen debe cambiar normalmente.
5. Apaga el atajo y repite el doble clic: no debe enviarse nada.

### Diferencias a propósito con el código del profesor

1. **El nativo emite cada pulsación, no el doble.** Así la regla del doble clic queda en un
   solo lugar (el dominio, con sus pruebas) en vez de dos.
2. **No se queda con las teclas de volumen.** El original devolvía `true` para todas, así que
   mientras el servicio estaba encendido el teléfono no podía cambiar el volumen. Aquí solo se
   consume la pulsación que completa el doble clic.
3. **No usa `vibration` ni `shared_preferences` para esto:** la vibración es
   `HapticFeedback.heavyImpact()` del propio Flutter, así que no se agregó ninguna dependencia.

### Lo que sigue sin estar (no es U-05)

La foto y el rumbo de la alerta (U-06) siguen simulados: el repositorio del profesor **no
incluye cámara** (ni el paquete ni el permiso en el manifiesto), así que eso no se pudo tomar
de ahí. En iOS el atajo no puede funcionar con el teléfono bloqueado: Apple no deja a una app
de terceros interceptar el volumen (eso es exclusivo de funciones del sistema como SOS).
