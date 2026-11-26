# Firma y empaquetado de la app Android (FIRMA-01)

Cómo se versiona, se firma y se empaqueta SafeLink para entregarla, y cómo se compila para
desarrollo (contra el backend local) y para producción (modo simulado).

> **Regla de oro:** el keystore y sus contraseñas **nunca** entran al repositorio ni al chat.
> `android/key.properties`, `*.jks` y `*.keystore` están en `android/.gitignore`.
> **Respalda el keystore y las contraseñas fuera del repo** (por ejemplo, en una USB y en un
> gestor de contraseñas). Si se pierden, no se puede volver a publicar una actualización de la
> app con la misma identidad: habría que publicarla como una app nueva.

---

## 1. Versionamiento

La versión sale de **una sola línea** de `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

| Parte | En Android | Para qué |
|---|---|---|
| `1.0.0` | `versionName` | Lo que ve la persona en Ajustes > Apps. Formato `MAYOR.MENOR.PARCHE` |
| `1` (tras el `+`) | `versionCode` | Entero que Android usa para saber si un APK es más nuevo. Una actualización **debe** tener un `versionCode` mayor que el instalado |

`android/app/build.gradle.kts` los toma de ahí (`flutter.versionName` y `flutter.versionCode`):
no se escriben a mano en Gradle.

**Política del proyecto**

- **MAYOR**: cambio incompatible o entrega formal (la `1.0.0` es la primera entrega firmada).
- **MENOR**: funciones nuevas que no rompen nada (`1.1.0`).
- **PARCHE**: solo correcciones (`1.0.1`).
- **`+build`**: sube en **cada** build que se entregue a alguien, aunque la versión no cambie
  (`1.0.0+1` → `1.0.0+2`). Nunca baja ni se reutiliza.

**Cómo ver la versión dentro del APK**

```powershell
& "$env:LOCALAPPDATA\Android\sdk\build-tools\36.0.0\aapt.exe" dump badging build\app\outputs\flutter-apk\app-release.apk | Select-String "versionCode"
```

Sale algo como `package: name='com.utez.safelink' versionCode='1' versionName='1.0.0'`.
También se ve en Android Studio: **Build > Analyze APK…** y elegir el archivo.

---

## 2. Keystore y firma

### 2.1 Crear el keystore (una sola vez, lo hace la persona responsable)

En la terminal de Android Studio (PowerShell), **fuera del repo**:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.keystores" | Out-Null
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore "$env:USERPROFILE\.keystores\safelink-release.jks" `
  -keyalg RSA -keysize 2048 -validity 10000 -alias safelink
```

- Pide la contraseña del almacén y los datos del certificado (nombre, unidad, organización,
  ciudad, estado, país `MX`). Escribe las contraseñas **solo ahí**.
- El formato por defecto es PKCS12: **la contraseña de la llave es la misma que la del
  almacén**, así que en `key.properties` `keyPassword` y `storePassword` llevan el mismo valor.
- Validez de 10000 días (~27 años): Google Play exige que dure más allá de 2033.

Comprobar que quedó bien (pide la contraseña):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v `
  -keystore "$env:USERPROFILE\.keystores\safelink-release.jks" -alias safelink
```

Anota el **SHA256** del certificado: es la huella con la que se compara cada build firmado.

**Tropiezos conocidos con `keytool` en Windows en español**

- Al responder `¿Es correcto CN=…?`, la versión en español acepta `si`; la versión en inglés
  pide `yes`.
- `keytool -list -v` puede fallar al imprimir el certificado con
  `MissingFormatArgumentException: Format specifier '%2$s'`. Es un fallo de la traducción de
  la JDK, no del keystore. Se evita pidiéndole la salida en inglés. En PowerShell esos
  argumentos van **entre comillas simples**: sin comillas, PowerShell los corta en el punto y
  `keytool` responde `Opción no permitida: .language=en`.

  ```powershell
  & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" '-J-Duser.language=en' '-J-Duser.country=US' -list -v `
    -keystore "$env:USERPROFILE\.keystores\safelink-release.jks" -alias safelink
  ```

  Lo mismo aplica a `keytool -printcert -jarfile …` (sección 2.4).

### 2.2 `android/key.properties`

Copia `android/key.properties.example` a `android/key.properties` y llénalo:

```properties
storePassword=<la contraseña del almacén>
keyPassword=<la misma, con PKCS12>
keyAlias=safelink
storeFile=C:/Users/<tu usuario>/.keystores/safelink-release.jks
```

- En `storeFile` usa `/` (o `\\`): en un `.properties` una `\` sola es carácter de escape.
- Comprueba que git lo ignora: `git check-ignore -v android/key.properties` debe responder
  con la regla de `android/.gitignore`.

### 2.3 Qué hace Gradle

`android/app/build.gradle.kts`:

- Si existe `android/key.properties`, crea la firma `release` con sus cuatro claves y el build
  release la usa. Si falta una clave, el build se detiene y dice cuál.
- Si **no** existe (por ejemplo, en la computadora de un compañero), el release se firma con la
  llave **debug** y Gradle avisa:
  `ADVERTENCIA SafeLink: no existe android/key.properties; el release se firma con la llave DEBUG y no sirve para entregar.`
  Así `flutter run --release` sigue funcionando para probar, pero **ese APK no se entrega**.
- No se activa R8, minify ni ofuscación (fuera del alcance de FIRMA-01).

### 2.4 Verificar con qué llave quedó firmado

```powershell
& "$env:LOCALAPPDATA\Android\sdk\build-tools\36.0.0\apksigner.bat" verify --print-certs build\app\outputs\flutter-apk\app-release.apk
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" '-J-Duser.language=en' -printcert -jarfile build\app\outputs\bundle\release\app-release.aab
```

El `SHA-256` que muestran debe ser **igual** al del keystore (2.1). Si sale
`CN=Android Debug`, se firmó con la llave debug.

---

## 3. APK o AAB

| | APK (`.apk`) | AAB (`.aab`, Android App Bundle) |
|---|---|---|
| Comando | `flutter build apk --release` | `flutter build appbundle --release` |
| Salida | `build/app/outputs/flutter-apk/app-release.apk` | `build/app/outputs/bundle/release/app-release.aab` |
| Se instala directo | Sí: `adb install -r`, o copiarlo al teléfono y abrirlo | **No.** Es el formato que se sube a Google Play; Play genera un APK optimizado para cada dispositivo (idioma, densidad, arquitectura) |
| Tamaño | Mayor: lleva el código nativo de todas las arquitecturas | El archivo pesa parecido, pero lo que descarga cada teléfono es más chico |
| Para qué | Pruebas, demo y entrega manual | Publicar en Google Play |

Para probar un AAB sin Play se usa **`bundletool`** (herramienta de Google): `build-apks`
genera los APK a partir del `.aab` con tu llave y `install-apks` los instala en el teléfono
conectado.

**Qué entregar:** para la entrega académica y las pruebas, el **APK firmado**: se instala sin
tienda. El AAB se genera y se conserva para cuando se publique en Google Play.

### Instalar el APK en un teléfono

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" devices
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-release.apk
```

Si el teléfono ya tiene SafeLink instalada con **otra** firma (por ejemplo, la debug de
`flutter run`), Android rechaza la actualización con `INSTALL_FAILED_UPDATE_INCOMPATIBLE`:
desinstálala primero (`adb uninstall com.utez.safelink`).

Con el APK de producción (modo simulado), el login muestra las cuentas de prueba; todas usan
la contraseña `SafeLink1` (por ejemplo, `usuario@safelink.mx`, `guardia@safelink.mx` y
`admin@safelink.mx`; la lista completa está en `lib/datos/datos_semilla.dart`).

---

## 4. Configuración por ambiente

`lib/main.dart` lee dos valores de compilación: `API_URL` (`String.fromEnvironment`) y
`USAR_NUBE` (`bool.fromEnvironment`). Se pasan con `--dart-define-from-file`:

| Archivo | Contenido | Resultado |
|---|---|---|
| `config/dev.json` | `API_URL = http://127.0.0.1:3000/api/v1` | Backend local real, a través de `adb reverse tcp:3000 tcp:3000` (puerto de `backend/.env.example`). Sin modo demo |
| `config/prod.json` | `API_URL` vacía y `USAR_NUBE = false` | **Modo simulado en memoria**: datos de demostración, cuentas de prueba en el login, sin red |

Por qué `prod.json` da el modo simulado (`lib/main.dart`): con `API_URL` vacía,
`usarNube = USAR_NUBE || urlApi != ''` queda en `false` y `Dependencias.crear` arma los
repositorios en memoria. Además, en release o profile una `API_URL` que no empiece con
`https://` se ignora y también cae al modo simulado: **`config/dev.json` solo sirve en debug**.

**Comandos**

```powershell
# Dev: debug contra el backend local
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" reverse tcp:3000 tcp:3000
flutter run --dart-define-from-file=config/dev.json

# Producción: release firmado, modo simulado
flutter build apk --release --dart-define-from-file=config/prod.json
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

**Cuando haya un backend real publicado.** JSON no admite comentarios, así que la nota va aquí:
basta con poner la URL **https** en `config/prod.json`, por ejemplo
`"API_URL": "https://api.ejemplo.mx/api/v1"` (sin `USAR_NUBE`). Una URL `http://` en release se
ignora a propósito. Con una URL, la app apaga sola el modo demo (D54).

**En Android Studio** (sin tocar `.idea` ni `.run` del repo): **Run > Edit Configurations…**,
duplica la configuración de `main.dart` dos veces y en **Additional run args** pon:

- *SafeLink Dev*: `--dart-define-from-file=config/dev.json`
- *SafeLink Producción*: `--release --dart-define-from-file=config/prod.json`

Esas configuraciones quedan en tu copia local.

---

## 5. Si el build falla al descargar dependencias (`PKIX path building failed`)

**Síntoma.** `flutter build apk --release` (o `appbundle`) falla en segundos con algo así:

```
Could not resolve androidx.core:core:1.17.0.
  Could not GET 'https://dl.google.com/dl/android/maven2/androidx/core/core/1.17.0/core-1.17.0.pom'.
  Got SSL handshake exception during request.
  (certificate_unknown) PKIX path building failed: ... unable to find valid certification path to requested target
BUILD FAILED
[!] Gradle threw an error while downloading artifacts from the network.
```

**Qué significa.** No es un problema de la firma ni del código. Gradle corre con la JDK de
Android Studio (`jbr`), y esa JDK no confía en el certificado que le presenta el servidor. Casi
siempre se debe a que algo en medio revisa el tráfico HTTPS con un certificado propio: el
**análisis HTTPS de un antivirus** o el **proxy o filtro de una red** (escuela, empresa). Windows
y el navegador confían en ese certificado; Java no, porque usa su propio almacén.

**Por qué a veces sí compila.** Gradle guarda en caché lo que ya descargó. El modo debug puede
funcionar con lo que ya estaba descargado, y el release falla en cuanto necesita algo que no
está en caché: una dependencia nueva (por ejemplo, `androidx.browser`, que trae `url_launcher`)
o la primera compilación release. Si se limpia la caché de Gradle (`~/.gradle/caches`) o se
agrega una dependencia, el error vuelve.

**Cómo resolverlo, de menor a mayor esfuerzo**

1. **Cambiar de red.** Compartir internet desde el celular y compilar una vez. Las dependencias
   quedan en caché y los siguientes builds funcionan también en la red original.
2. **Ver quién intercepta.** En el navegador, abrir
   `https://dl.google.com/dl/android/maven2/androidx/core/core/1.17.0/core-1.17.0.pom`, clic en
   el candado y ver **Emitido por** del certificado. Si dice Google Trust Services, no hay
   intercepción en el navegador. Si dice el nombre de un antivirus (Avast, AVG, Kaspersky, ESET,
   Bitdefender, Norton) o de una red o institución, ese es el responsable.
3. **Desactivar el análisis HTTPS del antivirus** mientras se compila (la opción se llama
   "análisis HTTPS", "SSL/TLS" o "conexiones cifradas"). Después se puede volver a activar.
   **Esto fue lo que funcionó en la primera entrega firmada (FIRMA-01, 2026-11-26):** con el
   antivirus desactivado, el APK y el AAB compilaron. Con lo ya descargado en caché, se espera
   que los builds sigan funcionando con el antivirus activo; si una dependencia nueva vuelve a
   dar este error, se repite el paso.
4. **Último recurso:** importar el certificado raíz del antivirus o de la red en el almacén
   `cacerts` de la JDK de Android Studio con `keytool -importcert`. Toca archivos de la
   instalación, necesita permisos de administrador y se pierde al actualizar Android Studio.

## 6. Otros tropiezos

| Síntoma | Causa y solución |
|---|---|
| `adb install` da `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | El teléfono tiene SafeLink con otra firma (debug ↔ release). `adb uninstall com.utez.safelink` y volver a instalar. Se borran los datos de la app en ese teléfono. `flutter run` lo hace solo |
| `npm run dev` da `EADDRINUSE ... 127.0.0.1:3000` | Ya hay una API en el puerto 3000: otro `npm run dev` abierto o el contenedor `backend-api-1`. Si `http://127.0.0.1:3000/health` responde `ok`, se puede usar esa |
| `keytool` falla con `Format specifier '%2$s'` o `Opción no permitida: .language=en` | Ver los tropiezos de `keytool` en la sección 2.1 |
| El login con `config/dev.json` dice "Correo o contraseña incorrectos" con la contraseña correcta | La base del backend no tiene la semilla: `npm run db:seed` en `backend/` |

## 7. Lista para cada entrega

1. Subir `+build` en `pubspec.yaml` (y la versión si aplica, sección 1).
2. Confirmar que existe `android/key.properties` (si no, saldría con la llave debug).
3. `flutter build apk --release --dart-define-from-file=config/prod.json`
   (y `appbundle` si se va a publicar).
4. Verificar la firma (2.4) y la versión (sección 1).
5. Instalar en un teléfono y entrar con una cuenta de prueba.
6. Respaldar el keystore y las contraseñas si cambiaron.

---

## 8. Estado del empaquetado y cómo seguir (para el equipo)

Resumen de los puntos que se acordaron para el empaquetado, qué quedó hecho en FIRMA-01
(2026-11-26) y qué necesita saber quien tome cada punto pendiente.

| Punto | Estado | Dónde está |
|---|---|---|
| Versionamiento | ✅ Hecho: `1.0.0+1` | Sección 1 |
| Keystore y firma | ✅ Hecho: el release se firma con la llave del proyecto, no con la debug | Sección 2 |
| APK y AAB | ✅ Hecho: los dos compilan y están firmados con la misma llave | Sección 3 |
| Resguardo de credenciales | ✅ Hecho: `key.properties` ignorado, keystore fuera del repo y el token de sesión ya va al almacenamiento seguro del sistema (FIRMA-02) | Sección 9 |
| HTTPS para el backend | ✖ Descartado: no se despliega el backend; el release corre en modo simulado | Sección 4 |
| Instalación y prueba | ✅ En emulador: APK release instalado, modo simulado y login con cuenta semilla. Falta un teléfono físico | Secciones 3 y 7 |
| Modos de compilación | ✅ Dev (debug) y Producción (release firmado). Sin R8, ofuscación, flavors ni profile | Sección 4 |
| Ambientes `config/dev.json` y `config/prod.json` | ✅ Probados: Dev contra el backend local en el emulador; Producción en modo simulado | Sección 4 |
| Manual del proyecto integrador | ⏳ Pendiente | Ver abajo |
| Entregable de integradora | ⏳ Pendiente hasta que publiquen la rúbrica | Ver abajo |

### Lo que cualquiera del equipo necesita saber

- **El APK que se entrega lo compila solo quien tiene el keystore.** En otra computadora, sin
  `android/key.properties`, `flutter build apk --release` funciona pero sale firmado con la
  llave **debug** (Gradle lo avisa con `ADVERTENCIA SafeLink…`). Sirve para probar, **no para
  entregar**, y no se puede instalar encima de la versión firmada (sección 6).
- **El keystore no se comparte por el repo, el chat ni el correo.** Si otra persona necesita
  firmar, se le pasa el archivo y la contraseña por un medio privado (en persona, USB) y ella
  crea su propio `android/key.properties` (sección 2.2). Nunca se genera un keystore nuevo para
  la misma app: cambiaría la identidad y las actualizaciones dejarían de instalarse.
- **Huella para comprobar cualquier build firmado:**
  `SHA256: F7:25:D7:6C:05:87:03:B2:E3:BA:D5:B7:50:2A:91:C2:4F:6E:AC:74:7D:81:05:21:84:2E:9D:97:BA:EE:E2:7C`
  (es pública; ver sección 2.4). Si un APK muestra otra, no está firmado con la llave del proyecto.
- **Cada build que se entregue sube el número tras `+`** en `pubspec.yaml` (sección 1).
- **Si Gradle falla con `PKIX path building failed`**, ver la sección 5 (en este equipo se
  resolvió desactivando el análisis HTTPS del antivirus).

### Cómo avanzar en los pendientes

**Instalación en teléfono físico.** Con depuración USB activada:
`adb devices` → `adb install -r build\app\outputs\flutter-apk\app-release.apk` → abrir la app y
entrar con `usuario@safelink.mx` / `SafeLink1` (sección 3). Si ya tenía una versión debug,
desinstalarla primero (sección 6).

**Manual del proyecto integrador.** Esta guía ya cubre el proceso técnico: versión (1), firma
(2), APK y AAB (3), ambientes (4) y problemas frecuentes (5 y 6). Para el manual faltaría,
según lo que pida la rúbrica: capturas de cada paso (Android Studio, `keytool`, resultado de
`apksigner`), una explicación breve de por qué se firma una app y la evidencia de la prueba en
el teléfono. **Nunca** incluir en capturas la contraseña del keystore ni el contenido de
`key.properties`.

**Entregable de integradora.** Cuando publiquen la rúbrica, revisar si pide algo que hoy quedó
fuera: R8 u ofuscación, *flavors*, backend con HTTPS o publicación en Google Play. Cada uno es
una tarea nueva:
- *R8 / ofuscación:* `isMinifyEnabled` e `isShrinkResources` en `buildTypes.release` y reglas de
  ProGuard para los plugins; hay que volver a probar todo en el teléfono.
- *Backend con HTTPS:* desplegar la API y poner su URL `https://` en `config/prod.json`
  (sección 4); el modo demo se apaga solo.
- *Google Play:* se sube el AAB, no el APK; Play pide una cuenta de desarrollador (cuenta externa,
  se decide en equipo).

---

## 9. Resguardo del token de sesión (FIRMA-02)

Hecho sobre lo que dejó planteado FIRMA-01.

**El problema.** El refresh token es la llave de la sesión: con él se piden access tokens
nuevos cuantas veces haga falta. Se guardaba con `shared_preferences`, que en Android es un
XML sin cifrar dentro del sandbox de la app. Basta un teléfono con root, o una copia de
seguridad, para leerlo.

**Qué cambió.** `DispositivoAlmacenTokens` (`lib/datos/almacen_tokens.dart`) usa ahora
`flutter_secure_storage`, que en Android guarda el valor cifrado con AES-GCM usando una llave
del **Keystore**, que no sale del hardware. En iOS sería el Keychain. No hubo que configurar
nada: son las opciones por defecto de la versión 11.

**Tres decisiones que conviene conocer.**

1. **Se migra lo que ya estaba guardado.** Quien tenga la sesión abierta con una versión
   anterior tiene el token en texto plano. Al leerlo por primera vez se mueve al
   almacenamiento seguro y **se borra el original**. Si no se hiciera, la persona tendría que
   iniciar sesión otra vez al actualizar y —peor— la copia sin cifrar seguiría en el teléfono.

2. **Si el almacenamiento seguro falla, NO se cae a texto plano.** Hay dispositivos con el
   Keystore roto por una actualización del sistema. En ese caso se pierde la persistencia de
   la sesión y hay que volver a iniciarla. Es lo correcto: la alternativa sería dejar la llave
   sin cifrar, que es justo lo que se vino a arreglar.

3. **Aun fallando, la copia en claro se borra.** Esto no estaba en la primera versión del
   código y lo encontró una prueba: si el Keystore fallaba, el código salía antes de limpiar y
   el token de la versión anterior se quedaba ahí para siempre.

**Pruebas.** `test/datos/almacen_tokens_seguro_test.dart`, 11 casos: que no se toque
`shared_preferences`, la migración completa, que solo migre una vez, y los cuatro caminos con
el Keystore roto.

**Lo que sigue fuera.** El access token vive en memoria a propósito (dura 15 minutos y no se
persiste). Y esto solo importa cuando se usa la API real: en el release en modo simulado no
hay tokens del servidor.
