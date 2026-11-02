# SafeLink - Servicio de respuesta de seguridad privada bajo demanda

App móvil (Flutter) que conecta a un **usuario en riesgo** con un **guardia de
seguridad privada**. Proyecto académico UTEZ.

> **Arquitectura:** tres capas (dominio · datos · presentación) + MVVM pragmático,
> calcada de [`ecotrack_arquitectura`](https://github.com/cristiancampos-docente/ecotrack-reto-solucion).
> Todo funciona con datos simulados de Morelos; la "nube" es una API falsa.

## Primeros pasos

```bash
flutter pub get
flutter run
```

Si faltan las carpetas de plataforma: `flutter create . --org mx.edu.utez --project-name safelink --platforms android,ios`
(no sobrescribe `lib/` ni `pubspec.yaml`; si crea `test/widget_test.dart`, bórralo).

### Cuentas de prueba (contraseña `SafeLink1`)

| Correo | Rol | Qué probar |
|---|---|---|
| `usuario@safelink.mx` | Usuario protegido | Toque con cuenta regresiva, mantener y descartar, "Simular agitación", guardia y ETA simulados, "Ya fui atendido", historial |
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
    admin/                   shell, panel, guardias, editar guardia, cobertura, escaladas, historial
    dev/                     guía de estilos viva
test/
  dominio/                   una prueba por regla
  datos/                     contrato memoria = nube, semilla, simulaciones
  presentacion/              ViewModels con repositorios espía (sin pantallas, sin red)
  interfaz/                  widgets, login y recorrido de todas las pantallas por rol
  arquitectura_test.dart     verifica la regla de dependencias leyendo los imports
docs/
  GUIA_ESTILOS.md
  HISTORIAS_DE_USUARIO.md    U-01…U-09, G-01…G-07, A-01…A-08 con sus criterios y su estado
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

## Cómo cambiar a la nube

En `lib/main.dart`:

```dart
const usarNube = false; // cámbialo a true y haz hot restart.
```

Con `true`, los repositorios `Nube*` traducen entidad ↔ JSON y hablan con
`SafeLinkService` (latencia de 400–800 ms). No hay que tocar nada más.

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
| Strategy | `presentacion/usuario/estrategias_disparo.dart` (toque con cuenta regresiva, mantener con descarte, agitación) | Cada método de disparo decide cuándo enviar, sin `if` por método dentro del ViewModel |
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

```bash
flutter analyze
flutter test                      # todas
flutter test test/dominio         # solo reglas
flutter test test/presentacion    # solo ViewModels
```

## Pendiente para siguientes sprints
- API real: cambiar el cuerpo de `SafeLinkService` por HTTP; los `nube_*` no cambian.
- Cámara, GPS, brújula y servicio de agitación (U-05, U-06, U-07).
- Google Maps real y `url_launcher` (G-06), FCM para la alerta entrante (G-02).
- Mover el centro de la zona tocando el mapa (A-03).
- Los temporizadores de escalamiento los hará la API.
