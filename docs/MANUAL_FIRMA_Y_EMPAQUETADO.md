# Manual de firma y empaquetado — SafeLink

**Proyecto integrador · Desarrollo Móvil · UTEZ**
App: `com.utez.safelink` · Versión documentada: `1.0.0+1` · Flutter 3.47.4

> Este manual explica **qué se hizo, por qué y cómo repetirlo**. El procedimiento técnico
> detallado, con los comandos exactos y los problemas que nos encontramos, está en
> [`FIRMA_Y_EMPAQUETADO.md`](FIRMA_Y_EMPAQUETADO.md); aquí no se duplica, se referencia.
>
> **Estado: avance.** La sección 9 dice con precisión qué está terminado y qué no. Lo que
> falta no se presenta como hecho.

---

## 1. Por qué una app tiene que ir firmada

Android no instala un APK sin firma. La firma es un certificado digital que responde dos
preguntas:

- **¿Quién publicó esto?** El sistema guarda la huella del certificado la primera vez que se
  instala la app.
- **¿Es la misma app de antes?** Una actualización solo se instala encima si viene firmada con
  **la misma llave**. Si la huella cambia, Android la rechaza, porque para él es otra app que
  intenta hacerse pasar por la instalada.

De ahí salen las dos consecuencias que mandan sobre todo lo demás:

1. **La llave no se puede perder ni cambiar.** Si se pierde, no hay forma de publicar una
   actualización de esa app: habría que publicarla de cero con otro identificador y los
   usuarios tendrían que desinstalar y reinstalar.
2. **La llave no se puede filtrar.** Quien la tenga puede firmar un APK y hacerlo pasar por
   una actualización legítima de SafeLink.

Por eso el keystore vive **fuera del repositorio** y su contraseña nunca entra en Git, en el
chat del equipo ni en una captura de pantalla.

---

## 2. Versionamiento

La versión sale de una sola línea de `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

| Parte | En Android | Para qué sirve |
|---|---|---|
| `1.0.0` | `versionName` | Lo que lee una persona en Ajustes → Apps |
| `1` (tras el `+`) | `versionCode` | El número con el que Android decide si un APK es más nuevo |

**Lo que importa entender:** Android **no compara** `1.0.0` con `1.0.1`. Compara el entero de
después del `+`. Un APK con `versionCode` igual o menor que el instalado **no se instala
encima**. Por eso la regla del equipo es que ese número sube en cada build que se entregue a
alguien, aunque el nombre de versión no cambie.

La política completa (cuándo sube MAYOR, MENOR o PARCHE) está en la sección 1 de la guía
técnica.

---

## 3. Keystore y firma

El keystore es el archivo que contiene la llave privada. Se crea **una sola vez en la vida del
proyecto** con `keytool`, y se protege con contraseña.

Cómo está montado en SafeLink:

```
android/key.properties        ← datos de la llave · IGNORADO por Git
android/key.properties.example ← plantilla, sin valores reales · SÍ versionada
<fuera del repositorio>        ← el archivo .jks con la llave
```

`android/app/build.gradle.kts` lee `key.properties` si existe y firma el release con esa llave.
**Si no existe** —por ejemplo, en la computadora de otra persona del equipo— Gradle avisa y
firma con la llave de depuración, para que `flutter build --release` siga funcionando.

> ⚠️ **Ese APK sirve para probar, no para entregar.** Y no se puede instalar encima de uno
> firmado con la llave del proyecto: Android lo rechaza por lo explicado en la sección 1.

### Comprobar con qué llave quedó firmado un APK

En macOS:

```bash
~/Library/Android/sdk/build-tools/*/apksigner verify --print-certs app-release.apk
```

La huella del proyecto es pública y se puede comparar sin riesgo:

```
SHA-256: F7:25:D7:6C:05:87:03:B2:E3:BA:D5:B7:50:2A:91:C2:4F:6E:AC:74:7D:81:05:21:84:2E:9D:97:BA:EE:E2:7C
```

Si sale otra huella, ese APK **no** está firmado con la llave del proyecto. Por ejemplo, un
build hecho sin `key.properties` devuelve:

```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
```

📷 **Captura 1** — la salida de `apksigner` mostrando la huella del proyecto, hecha en la
computadora que tiene el keystore.
*Pie:* «Verificación de la firma del APK de entrega.»

---

## 4. APK o AAB

Se generan los dos, con la misma llave:

| Formato | Qué es | Cuándo se usa |
|---|---|---|
| **APK** | El paquete instalable directo | Entregar al profesor, instalar por USB o pasar por archivo |
| **AAB** | Un paquete que Google Play abre para generar el APK de cada teléfono | Solo si se publica en Play |

Para esta entrega lo que se usa es el **APK**. El AAB se genera para demostrar que el proyecto
está listo para publicarse, no porque haga falta hoy.

Evidencia del build (26/11/2026):

```
build/app/outputs/flutter-apk/app-release.apk      59M
build/app/outputs/bundle/release/app-release.aab   58M
```

---

## 5. Modos de compilación y ambientes

El pizarrón pedía «configuración de ambiente adicional al dev» y «modo de compilación para
producción». Se resolvió con dos archivos de configuración y dos comandos, **sin tocar la
lógica de la app**.

```
config/dev.json    { "API_URL": "http://127.0.0.1:3000/api/v1" }
config/prod.json   { "API_URL": "", "USAR_NUBE": "false" }
```

| Modo | Comando | Qué hace |
|---|---|---|
| **Dev** | `flutter run --debug --dart-define-from-file=config/dev.json` | Se conecta al backend local por `adb reverse`. Firma de depuración |
| **Producción** | `flutter build apk --release --dart-define-from-file=config/prod.json` | Firmado con la llave del proyecto, optimizado, sin `API_URL` |

### Por qué producción va en modo simulado

Porque **el backend no está desplegado**. La app rechaza a propósito una `API_URL` con `http://`
cuando se compila en release: los tokens de sesión no pueden viajar sin cifrar por una red.
Como no hay un servidor con `https://`, el release funciona con datos locales.

No es una limitación escondida, es una decisión de seguridad. El día que se despliegue el
backend, basta poner su URL `https://` en `config/prod.json` y el modo simulado se apaga solo:
no hay que cambiar código.

> ⚠️ **Lo más fácil de equivocarse.** Si alguien compila en **release** apuntando a
> `http://`, la app **se va a modo simulado sin avisar**. Parece funcionar y muestra datos
> falsos. Para demostrar la app contra el backend hay que usar **debug**.

---

## 6. Resguardo de credenciales

Hay dos tipos de credencial en juego y conviene no confundirlos.

### a) La llave de firma (del equipo)

- `android/key.properties` está en `.gitignore`: nunca se sube.
- El `.jks` vive fuera del repositorio, con respaldo aparte.
- Se comparte **en persona o por USB**, nunca por chat ni correo.
- `key.properties.example` documenta qué campos hacen falta, sin valores reales.

### b) El token de sesión (de cada usuario)

Cuando la app usa el backend real guarda un *refresh token*, que es la llave de la sesión: con
él se piden accesos nuevos indefinidamente.

**Antes** se guardaba con `shared_preferences`, que en Android es un XML **sin cifrar** dentro
del sandbox de la app. Con un teléfono con root o una copia de seguridad, se lee.

**Ahora** va al **Keystore de Android**, cifrado con AES-GCM y una llave que no sale del
hardware del teléfono. Tres detalles que se cuidaron:

1. Quien ya tenía sesión abierta con la versión anterior, **se migra** y la copia sin cifrar se
   borra.
2. Si el Keystore falla —existen teléfonos con él roto por una actualización del sistema— la
   app **no vuelve a guardar en claro**: se pierde la sesión y hay que entrar otra vez. Es
   preferible.
3. Incluso fallando, la copia antigua se borra.

Está cubierto por 11 pruebas automáticas (`test/datos/almacen_tokens_seguro_test.dart`).

> 🔒 **Al tomar capturas para este manual, nunca incluyas el contenido de `key.properties` ni
> la contraseña del keystore.**

---

## 7. Instalación del release

```bash
adb devices                                  # el teléfono debe salir como "device"
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Si el teléfono ya tenía instalada una versión de depuración, hay que **desinstalarla primero**:
tienen firmas distintas y Android no deja reemplazar una por otra.

Para entrar: `usuario@safelink.mx`, `guardia@safelink.mx` o `admin@safelink.mx`, contraseña
`SafeLink1` (son cuentas de demostración, solo de desarrollo).

📷 **Captura 2** — la app ya instalada, abierta en el teléfono.
*Pie:* «APK de release instalado y funcionando en un dispositivo físico.»

📷 **Captura 3** — Ajustes → Apps → SafeLink, donde se ve la versión `1.0.0`.
*Pie:* «Versión declarada, visible en el sistema.»

---

## 8. Cómo reproducir todo desde cero

Para alguien que llega nuevo al proyecto y tiene el keystore:

```bash
# 1. Dependencias
flutter pub get

# 2. Datos de la llave (a partir de la plantilla)
cp android/key.properties.example android/key.properties
#    …y llenarlo con la ruta del .jks y las contraseñas

# 3. Subir el número de build en pubspec.yaml   (1.0.0+1 → 1.0.0+2)

# 4. Compilar
flutter build apk --release --dart-define-from-file=config/prod.json
flutter build appbundle --release --dart-define-from-file=config/prod.json

# 5. Verificar la firma
~/Library/Android/sdk/build-tools/*/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

📷 **Captura 4** — la terminal con el build terminado (`✓ Built …app-release.apk`).
*Pie:* «Compilación del paquete de producción.»

---

## 9. Estado de este entregable

Lo que **sí** está hecho y comprobado:

| Punto del pizarrón | Estado | Evidencia |
|---|---|---|
| Versionamiento | ✅ | `pubspec.yaml` → `1.0.0+1` |
| Keystore y firma | ✅ | Huella SHA-256 del proyecto, sección 3 |
| APK vs AAB | ✅ | Los dos compilan firmados con la misma llave |
| Configuración de ambiente adicional al dev | ✅ | `config/dev.json` y `config/prod.json` |
| Modo de compilación para producción | ✅ | Sección 5 |
| Resguardo de credenciales | ✅ | Llave fuera del repo + token en el Keystore |
| Manual del proyecto integrador | ◐ | Este documento, a falta de las capturas |

Lo que **no** está hecho, dicho sin adornos:

| Pendiente | Por qué |
|---|---|
| **Instalación probada en un teléfono físico** | Se verificó en emulador. Falta repetirlo en un dispositivo real y capturar la evidencia |
| **Capturas 1 a 4** | Marcadas arriba. La 1 solo puede hacerla quien tiene el keystore |
| **Entregable final de integradora** | A la espera de la rúbrica |
| R8, ofuscación y *flavors* | Fuera de alcance salvo que la rúbrica los pida |
| Publicación en Google Play | Requiere cuenta de desarrollador; decisión del equipo |

### Quién hizo qué

- **FIRMA-01** (Astrid): versionado, creación del keystore, configuración de firma en Gradle,
  APK y AAB, archivos de ambiente y la guía técnica.
- **FIRMA-02** (Ángel): resguardo del token de sesión en el almacenamiento seguro del sistema,
  con sus pruebas, y este manual.
