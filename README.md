# SafeLink - Servicio de respuesta de seguridad privada bajo demanda

App móvil (Flutter) que conecta a un **usuario en riesgo** con un **guardia de
seguridad privada**. Proyecto académico UTEZ.

> **Sprint 2:** sistema de diseño global + estructura base con datos mock para
> que el equipo construya las vistas en paralelo. No hay consumo de API todavía.

## Primeros pasos

Este repositorio contiene solo `lib/`, `test/` y la configuración del proyecto.
La primera vez, genera las carpetas de plataforma:

```bash
flutter create . --org mx.edu.utez --project-name safelink --platforms android,ios
flutter pub get
flutter run
```

> `flutter create .` no sobrescribe `lib/` ni `pubspec.yaml`. Si crea
> `test/widget_test.dart`, bórralo.

### Cuentas de prueba (contraseña `SafeLink1`)

| Correo | Rol | Qué probar |
|---|---|---|
| `usuario@safelink.mx` | Usuario protegido | Disparar alerta (toque o mantener), ver guardia y ETA simulados, "Ya fui atendido" |
| `bloqueado@safelink.mx` | Usuario protegido | Pantalla de cuenta bloqueada |
| `guardia@safelink.mx` | Guardia | Listado ordenado, detalle con foto y rumbo, aceptar, "Simular acercamiento" y "Llegué" |
| `admin@safelink.mx` | Administrador | Métricas, guardias, escaladas (resolver), historial, desbloquear |

En el login hay botones para rellenar cada cuenta y otro para abrir la
**guía de estilos viva** (solo en modo debug).

## Estructura

```
lib/
  main.dart · app.dart
  core/
    theme/        tokens (colores, tipografía, espaciado), tema Material 3, estilo por estado
    constants/    AppConfig: valores configurables de la sección 5
    router/       rutas y redirección por rol (go_router)
    utils/        lógica pura: geocerca, orden de alertas, turnos, métricas, reglas, validadores, formato
  data/
    models/       User, GuardProfile, Alert, GeoPoint, métricas, enums
    repositories/ interfaces (Auth, UserAlert, GuardAlert, Admin) + errores de dominio
    mock/         backend en memoria, datos de Morelos y repositorios mock
    dependencies.dart  ← único lugar donde se elige mock o API real
  features/
    auth/   login, registro, sesión
    user/   home (botón), alert_status, settings, blocked
    guard/  alert_list, alert_detail, navigation
    admin/  shell (barra inferior), dashboard, guards, escalated, history
    dev/    style_guide_page (catálogo de componentes)
  shared/widgets/  componentes reutilizables (SlButton, SlCard, StatusChip, MapPlaceholder…)
test/
  unitaria/  <id>_<tema>_test.dart
  interfaz/  <id>_<tema>_test.dart
docs/
  GUIA_ESTILOS.md
```

Antes de crear una vista, lee **[docs/GUIA_ESTILOS.md](docs/GUIA_ESTILOS.md)**.

## Comandos

```bash
flutter analyze
flutter test                 # todas
flutter test test/unitaria   # solo unitarias
```

## Pendiente para siguientes sprints
- Repositorios reales contra la API (`AppDependencies`, `USE_MOCK=false`).
- Cámara, GPS, brújula y servicio de agitación (U-05, U-06, U-07).
- Google Maps real y `url_launcher` (G-06), FCM y pantalla de alerta entrante (G-02).
- Edición de turno y radio en mapa (A-03) y filtros completos del historial (A-05).
- Temporizadores de escalamiento (los hará la API).
