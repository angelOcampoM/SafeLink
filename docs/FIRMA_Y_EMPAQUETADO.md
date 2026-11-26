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

## 5. Lista para cada entrega

1. Subir `+build` en `pubspec.yaml` (y la versión si aplica, sección 1).
2. Confirmar que existe `android/key.properties` (si no, saldría con la llave debug).
3. `flutter build apk --release --dart-define-from-file=config/prod.json`
   (y `appbundle` si se va a publicar).
4. Verificar la firma (2.4) y la versión (sección 1).
5. Instalar en un teléfono y entrar con una cuenta de prueba.
6. Respaldar el keystore y las contraseñas si cambiaron.
