# SafeLink - Servicio de respuesta de seguridad privada bajo demanda

App móvil (Flutter) que conecta a un **usuario en riesgo** con un **guardia de
seguridad privada**. Proyecto académico UTEZ.

> **Arquitectura:** tres capas (dominio · datos · presentación) + MVVM pragmático,
> calcada de [`ecotrack_arquitectura`](https://github.com/cristiancampos-docente/ecotrack-reto-solucion).

El repositorio tiene **dos proyectos**: la app Flutter (`lib/`) y el backend
(`backend/`: Node 24, Fastify, Prisma y PostgreSQL, con las 38 rutas del contrato
implementadas).

## Primeros pasos

La app arranca sola, sin backend ni base de datos, con datos simulados de Morelos:

```bash
flutter pub get
flutter run
```

### Los tres modos

| Modo | Cómo se arranca | Para qué sirve |
|---|---|---|
| **Memoria** (por defecto) | `flutter run` | Demo y desarrollo de pantallas: todo en RAM, sin red |
| **Nube simulada** | `--dart-define=USAR_NUBE=true` | Igual, pero con latencia y errores de red fingidos (ver `tasaFallo`) |
| **Backend real** | `--dart-define=API_URL=http://127.0.0.1:3000/api/v1` | Contra el servidor de verdad |

En un teléfono, los sensores (cámara, GPS, rumbo) y el doble clic de volumen son
**reales en los tres modos**: lo decide `enTelefono` en `main.dart`, no el modo.
En web y escritorio siguen siendo simulados.

Para levantar el backend y conectar un teléfono: **`docs/CONEXION_DISPOSITIVO.md`**.

```bash
cd backend
cp .env.example .env     # define JWT_SECRET (32+ caracteres) y la contraseña de Postgres
npm install
npm run db:up            # Postgres en 127.0.0.1:5433 (necesita Docker)
npm run db:deploy        # migraciones
npm run db:seed          # datos de demostración
npm run dev              # API en http://127.0.0.1:3000
```

Si faltan las carpetas de plataforma: `flutter create . --org mx.edu.utez --project-name safelink --platforms android,ios`
(no sobrescribe `lib/` ni `pubspec.yaml`; si crea `test/widget_test.dart`, bórralo).

### Cuentas de prueba (contraseña `SafeLink1`)

| Correo | Rol | Qué probar |
|---|---|---|
| `usuario@safelink.mx` | Usuario protegido | Toque con cuenta regresiva, mantener y descartar, doble clic de volumen, guardia y ETA, "Ya fui atendido", historial |
| `rosa.diaz@mail.com` | Usuario protegido | Tiene 2 falsas alarmas: una más y queda bloqueada |
| `bloqueado@safelink.mx` | Usuario protegido | Pantalla de cuenta bloqueada |
| `guardia@safelink.mx` | Guardia | Listado ordenado, banner "Alerta entrante" cada 20–40 s, detalle, aceptar, "Simular acercamiento", "Llegué", historial con métricas |
| `guardia.noche@safelink.mx` | Guardia | Turno 22:00 → 06:00 (fuera de turno de día) |
| `admin@safelink.mx` | Administrador | Métricas por periodo, guardias (alta, edición, turno y radio, baja), escaladas, historial con filtros, desbloquear |

En el login hay chips para rellenar cada cuenta y, en modo debug, un botón a la
**guía de estilos viva**.

## Estructura

```
lib/
  main.dart                  raíz de composición: usarNube, tasaFallo, Dependencias, SafeLinkApp
  dominio/                   entidades y reglas de negocio en Dart puro (sin Flutter)
  datos/                     contratos, implementaciones memoria_ y nube_, servicio falso y semilla
  presentacion/
    comun/                   EstadoVista, ViewModel base, formato (Fmt)
      tema/                  tokens de diseño, tema Material 3, estilo por estado
      widgets/               componentes Sl* y compartidos (widgets.dart)
      rutas/                 AppRoutes, router (go_router) y FabricaViewModels
    sesion/                  SesionViewModel (sesión global; el router lo escucha)
    auth/                    login y registro
    usuario/                 inicio (botón), estado de alerta, configuración, bloqueado, historial
    guardia/                 listado, alerta entrante, detalle, navegación, historial
    admin/                   shell, panel, guardias, editar guardia, cobertura, métricas por guardia, escaladas, historial
    dev/                     guía de estilos viva
test/
  dominio/                   una prueba por regla
  datos/                     contrato memoria = nube, semilla, simulaciones
  presentacion/              ViewModels con repositorios espía (sin pantallas, sin red)
  interfaz/                  widgets, login y recorrido de todas las pantallas por rol
  arquitectura_test.dart     verifica la regla de dependencias leyendo los imports
backend/
  src/
    domain/                  reglas puras del servidor (geocerca, turnos, métricas, zona horaria)
    modules/                 auth, alerts, guard, admin, escalation, devices, events (SSE)
    security/policies.ts     tabla de permisos por ruta: deny por defecto
  prisma/                    esquema, migraciones y semilla
  tests/unit/                sin base de datos
  tests/integration/         contra Postgres (las corre CI)
docs/
  GUIA_ESTILOS.md
  HISTORIAS_DE_USUARIO.md    U-01…U-09, G-01…G-07, A-01…A-08 con sus criterios y su estado
  PLAN_DE_PRUEBAS.md         los 83 casos del esquema y la prueba que cubre cada uno
  API_CONTRATO.md            las 38 rutas, sus cuerpos, sus errores y quién las implementó
  MODELO_DATOS.md            tablas, relaciones y restricciones
  PERMISOS.md                qué rol puede llamar a qué
  DECISIONES.md              D1…D53: cada decisión de diseño y por qué se tomó
  CONEXION_DISPOSITIVO.md    levantar el backend y probar en un teléfono físico
  PLAN_CONSUMO_REAL.md       banco de tareas para que todo use la API real (sin simulados)
  CONTRATO_AUTENTICACION.md  BE-02: lo que el backend debe cumplir, sea cual sea
```

## Regla de dependencias

```
presentacion  →  datos  →  dominio
```

- **dominio** no depende de nadie: no importa `package:flutter`, ni `datos/`, ni `presentacion/`.
- **datos** conoce el dominio, pero no la presentación ni Flutter.
- **presentación**: la **View** (`*_page.dart`) solo habla con su **ViewModel**, y el
  ViewModel habla con el repositorio. Los ViewModels importan solo `foundation`
  (nunca `material.dart`).
- **`main.dart`** es el único archivo que conoce las implementaciones `memoria_` y `nube_`.

`test/arquitectura_test.dart` falla si alguien rompe estas reglas.

## Cómo cambiar de modo

Sin tocar código, al arrancar:

```bash
flutter run --dart-define=USAR_NUBE=true                             # nube simulada
flutter run --dart-define=API_URL=http://127.0.0.1:3000/api/v1       # backend real
```

También se puede cambiar `const usarNube` en `lib/main.dart` y hacer hot restart.

En los dos casos los repositorios `Nube*` traducen entidad ↔ JSON; lo único que
cambia es si detrás hay un `SafeLinkService` simulado (latencia de 400–800 ms) o
`HttpSafeLinkService` hablando con el servidor. Ningún otro archivo cambia: esa es
la razón de ser de la capa de datos.

En release y profile solo se acepta `https://`; con `http://` la app se queda en
modo simulado y lo avisa por consola.

### Probar los estados de error: `tasaFallo`

En `lib/main.dart`, con `usarNube = true`:

```dart
const tasaFallo = 0.3; // 3 de cada 10 peticiones fallan
```

Cada pantalla muestra entonces su estado **Error**: un `SlBanner` con "Reintentar"
(y en las listas también pull-to-refresh). `0.0` = nunca falla y `1.0` = siempre.
En modo memoria no aplica.

## Patrones de diseño

| Patrón | Dónde está | Qué problema resuelve |
|---|---|---|
| Repository | `datos/*_repository.dart` (contratos) + `memoria_*` y `nube_*` | La presentación pide datos en lenguaje del dominio, sin saber si vienen de una lista o de una API |
| Adapter / Mapper | `datos/nube_mapeadores.dart` (`AlertaJson.desdeJson` / `aJson`, …) | Traduce JSON ↔ entidad en un solo lugar; el dominio no conoce JSON ni los códigos de la API |
| Service (Gateway) | `datos/safelink_service.dart` | Es el único punto que "habla" con la API (latencia, errores, `tasaFallo`) |
| MVVM + Observer | `presentacion/**/*_view_model.dart` (`ChangeNotifier`), Views con `ListenableBuilder`, `Stream` en los repositorios | Separa estado y orquestación de la pintura; el tiempo real (ETA, alertas nuevas, escaladas) llega solo |
| Inyección de dependencias / Composition Root | `main.dart` (`Dependencias`), constructores de cada ViewModel | Todo se arma en un lugar y se pasa por constructor; las pruebas inyectan espías |
| Strategy | `presentacion/usuario/estrategias_disparo.dart` (toque con cuenta regresiva, mantener con descarte, doble clic de volumen) | Cada método de disparo decide cuándo enviar, sin `if` por método dentro del ViewModel |
| State | `presentacion/comun/estado_vista.dart` (`Cargando`, `Vacio`, `ErrorVista`, `Listo`) + `SlStateView` | Cada pantalla cubre siempre los cuatro estados; el `switch` sobre la sealed class obliga a no olvidar ninguno |
| Factory | `presentacion/comun/rutas/fabrica_view_models.dart` y `desdeJson` de los mapeadores | El router crea el ViewModel de cada ruta sin conocer implementaciones; el JSON se convierte en entidades en un solo lugar |

## Simulaciones de la demo

Viven en `datos/memoria_base_datos.dart` y arrancan desde `SafeLinkApp`:

- **Alertas nuevas:** cada 20–40 s aparece una alerta `buscando` cerca del guardia
  en sesión (listado y banner "Alerta entrante").
- **Respuesta del guardia:** cuando el usuario envía una alerta, un guardia la
  acepta, la ETA baja y llega.
- **Confirmación del usuario:** 8 s después de que el guardia marca "Llegué".
- **Escalamiento:** si nadie acepta en `segundosEscalamientoDemo` (90 s), o si el
  usuario no confirma, la alerta pasa a `escalada` y aparece en la bandeja del admin.

Los tiempos se cambian en `dominio/configuracion.dart`.

## Comandos

App:

```bash
flutter analyze
flutter test                      # todas (422)
flutter test test/dominio         # solo reglas
flutter test test/presentacion    # solo ViewModels
flutter build apk --release
```

Backend (desde `backend/`):

```bash
npm run typecheck
npm run lint
npx vitest run tests/unit         # sin base de datos
npm test                          # todas: las de integración necesitan Postgres
```

CI (`.github/workflows/calidad.yml`) corre los dos en cada PR hacia `develop`.

## Estado

Implementado y probado: **las 38 rutas** del contrato, el tiempo real por SSE, los
sensores reales del teléfono y el doble clic de volumen con la pantalla apagada
(verificado en un vivo V2441 con Android 16; ver D53).

Lo que falta **no es código**, son credenciales o una decisión del equipo:

| Pendiente | Qué hace falta |
|---|---|
| Mapas de verdad (G-06, A-03) | Una clave de Google Maps y `google_maps_flutter`; hoy se ve `MapPlaceholder` con los mismos datos |
| Aviso push al guardia (G-02) | Un proyecto de Firebase (`google-services.json`) y `PUSH_PROVIDER=fcm` |
| Gráficas del panel (A-06) | Decidir si se usa `fl_chart`; hoy los números se muestran sin gráfica |
| App de iOS | No hay carpeta `ios/`: el atajo de volumen con la pantalla bloqueada tampoco es posible ahí (limitación de Apple) |

Los 4 casos del plan de pruebas marcados 📱 dependen de esos tres puntos.
