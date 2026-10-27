# SafeLink — Guía de estilos y reglas para trabajar en paralelo

> Fuente de verdad visual del proyecto. Todo lo que aparece aquí ya está
> implementado en `lib/presentacion/comun/tema/` y `lib/presentacion/comun/widgets/`, y se puede ver
> funcionando en la app: **Login → "Ver guía de estilos"** (solo en debug).

---

## 1. Reglas de oro (léelas antes de abrir tu primera vista)

1. **Nada de valores sueltos.** Prohibido en las vistas (`presentacion/**/*_page.dart`):
   `Color(0xFF...)`, `Colors.red`, `fontSize: 17`, `EdgeInsets.all(13)`,
   `BorderRadius.circular(10)`. Usa siempre los tokens.
2. **Una sola importación para estilos y otra para widgets:**
   ```dart
   import 'package:safelink/presentacion/comun/tema/theme.dart';
   import 'package:safelink/presentacion/comun/widgets/widgets.dart';
   ```
   (Dentro de `lib/` también vale la ruta relativa: `../comun/tema/theme.dart`.)
   Otras rutas de uso frecuente:
   ```dart
   import 'package:safelink/dominio/dominio.dart';                      // entidades y reglas
   import 'package:safelink/presentacion/comun/formato.dart';           // Fmt
   import 'package:safelink/presentacion/comun/estado_vista.dart';      // Cargando, Vacio, ErrorVista, Listo
   import 'package:safelink/presentacion/comun/rutas/app_routes.dart';  // AppRoutes
   ```
3. **Antes de crear un widget, busca en `presentacion/comun/widgets/`.** Si lo que
   necesitas sirve a más de una pantalla, va en `comun/widgets/` (no en la carpeta
   de tu rol) y se agrega a la guía de estilos viva (`presentacion/dev/guia_estilos_page.dart`).
4. **Los widgets nativos ya vienen estilizados.** `TextField`, `Card`,
   `FilledButton`, `Switch`, `ChoiceChip`, `NavigationBar`, `SnackBar`,
   `BottomSheet` y `Dialog` toman el estilo del tema global: no les pases
   colores ni bordes.
5. **El rojo `emergency` es sagrado:** solo botón de alerta y alertas activas.
   Para errores y acciones destructivas usa `danger`.
6. **La View solo habla con su ViewModel; el ViewModel habla con el repositorio.**
   La View recibe el ViewModel por constructor, lo escucha con `ListenableBuilder`
   y le pasa intenciones (`vm.aceptar()`, `vm.guardar(...)`). No valida, no llama
   repositorios y no sabe si los datos vienen de memoria o de la nube. El
   ViewModel importa solo `package:flutter/foundation.dart`, nunca `material.dart`.
7. **Textos visibles en español (México).** Las capas (dominio, datos, ViewModels)
   también se nombran en español; el sistema de diseño (`SlButton`, `AppColors`…)
   conserva sus nombres.
8. **Si cambias un token, avisa al equipo** (afecta a todas las pantallas).

---

## 2. Color — `AppColors`

| Token | Hex | Uso |
|---|---|---|
| `background` | `#0F172A` | Fondo de todas las pantallas |
| `surface` | `#1E293B` | Tarjetas, campos de texto, hojas inferiores |
| `surfaceElevated` | `#273449` | Elemento sobre tarjeta, deshabilitado |
| `border` | `#334155` | Bordes y divisores |
| `textPrimary` | `#F8FAFC` | Títulos y texto principal |
| `textSecondary` | `#94A3B8` | Descripciones, metadatos |
| `textMuted` | `#64748B` | Placeholder, deshabilitado |
| `emergency` | `#EF4444` | **Solo** botón de alerta y alertas activas |
| `warning` | `#F59E0B` | Urgente (agitación), pendiente, escalada |
| `success` | `#22C55E` | Confirmado, en turno, seguro, "Llegué" |
| `info` | `#3B82F6` | Acción principal, mapas, navegación, enlaces |
| `danger` | `#F87171` | Errores de formulario, dar de baja, falsa alarma |

Fondos tenues para chips y banners: `AppColors.tint(color)` (15 %) y
`AppColors.tintBorder(color)` (40 %).

### Color por estado de alerta
No elijas colores para estados a mano. Usa la extensión:
```dart
final s = alerta.estado.style;   // s.color, s.icon, s.label
StatusChip(alerta.estado);       // o directamente el chip
TriggerChip(alerta.metodo);
```

| Estado | Color |
|---|---|
| Pendiente de ubicación | warning |
| Buscando guardia | emergency |
| En atención | info |
| Guardia en el lugar · Atendida | success |
| Sin respuesta · Escalada | warning |
| Resuelta por administrador | textSecondary |

---

## 3. Tipografía — Inter

Accede con `context.text.<estilo>`.

| Estilo | Tamaño / peso | Uso |
|---|---|---|
| `displayLarge` | 56 / 800 | Cuenta regresiva |
| `displaySmall` | 32 / 700 | Cifras: ETA, distancia, métricas |
| `headlineMedium` | 24 / 700 | Título principal de pantalla |
| `headlineSmall` | 22 / 600 | Estado grande ("Buscando guardia") |
| `titleLarge` | 20 / 600 | AppBar, título de hoja inferior |
| `titleMedium` | 16 / 600 | Título de tarjeta, nombre de persona |
| `bodyLarge` | 16 / 400 | Texto de lectura, campos |
| `bodyMedium` | 14 / 400 | Descripciones (color secundario) |
| `bodySmall` | 12 / 400 | Hora, distancia, metadatos |
| `labelLarge` | 16 / 600 | Texto de botones |
| `labelSmall` | 11 / 600 | Encabezados de sección (MAYÚSCULAS) |

Para variar color: `context.text.titleMedium?.copyWith(color: AppColors.info)`.

---

## 4. Espaciado, radios y tamaños

| `AppSpacing` | px | | `AppRadius` | px |
|---|---|---|---|---|
| `xxs` | 4 | | `sm` / `brSm` | 8 |
| `xs` | 8 | | `md` / `brMd` | **16 (estándar)** |
| `sm` | 12 | | `pill` / `brPill` | 999 |
| `md` | 16 | | | |
| `lg` | 24 | | | |
| `xl` | 32 | | | |
| `xxl` | 48 | | | |

- Márgenes de pantalla: `AppSpacing.screen` · relleno de tarjeta: `AppSpacing.card`.
- Separadores listos: `AppSpacing.gapXs`, `gapSm`, `gapMd`, `gapLg`…
- `AppSizes.touchTarget = 56`: alto mínimo de botones y filas tocables.
- `AppDurations.fast / normal / slow` para animaciones.

---

## 5. Componentes compartidos (`presentacion/comun/widgets/`)

| Componente | Para qué | Ejemplo |
|---|---|---|
| `SlButton` | Todos los botones. Variantes: `primary`, `success`, `emergency`, `danger`, `secondary`, `ghost`. Soporta `loading`, `icon`, `expand`. | `SlButton(label: 'Aceptar alerta', icon: Icons.check, loading: vm.aceptando, onPressed: _alAceptar)` |
| `SlTextField` | Campos con etiqueta arriba, ícono, contraseña con mostrar/ocultar, solo dígitos, máx. longitud. `errorText` muestra el error que da el ViewModel | `SlTextField(label: 'Teléfono', digitsOnly: true, maxLength: 10, errorText: vm.errorTelefono)` |
| `SlCard` | Contenedor base; `accent` agrega franja y borde de color | `SlCard(accent: AppColors.warning, onTap: ..., child: ...)` |
| `SlChip` / `StatusChip` / `TriggerChip` | Etiquetas de color no interactivas | `StatusChip(alerta.estado)` |
| `SlBanner` | Mensaje en línea: `info`, `success`, `warning`, `danger`, con `action` opcional | `SlBanner(type: SlBannerType.warning, message: '...')` |
| `SlStateView` | Pinta un `EstadoVista`: Cargando → `LoadingView`, Vacío → `EmptyState`, Error → `SlBanner` con "Reintentar", Listo → `builder`. Con `onRefresh` agrega pull-to-refresh | `SlStateView<List<Alerta>>(estado: vm.estado, onRetry: vm.cargar, onRefresh: vm.cargar, builder: ...)` |
| `SectionHeader` | Título de sección en mayúsculas con acción opcional | `SectionHeader('Usuarios bloqueados')` |
| `EmptyState` | Listado vacío, fuera de turno, sin resultados | `EmptyState(icon: ..., title: 'Todo tranquilo', message: ...)` |
| `LoadingView` | Cargando centrado | `const LoadingView(message: 'Enviando alerta…')` |
| `InfoRow` | Fila ícono · etiqueta · valor | `InfoRow(icon: Icons.schedule, label: 'Hora', value: '18:17')` |
| `InitialsAvatar` | Avatar con iniciales | `InitialsAvatar(usuario.iniciales)` |
| `MetricTile` | Cifra grande + etiqueta | `MetricTile(label: 'Llegada promedio', value: '7 min')` |
| `AlertCard` | Tarjeta de alerta (listado del guardia, escaladas, historiales) | `AlertCard(alert: a, now: vm.ahora, distanceMeters: 640)` |
| `AlertDetailSheet` | Hoja inferior con el detalle de una alerta del historial | `showModalBottomSheet(..., builder: (_) => AlertDetailSheet(alert: a))` |
| `EmergencyButton` | Botón circular de alerta (solo visual + gestos) | ver `usuario/inicio_page.dart` |
| `MapPlaceholder` | Mapa simulado con marcadores, ruta, geocerca/radio (`radiusFraction`) y cono de rumbo. Se reemplazará por `GoogleMap` con el mismo tamaño | `MapPlaceholder(showRoute: true, markers: [...])` |

Utilidades de formato (`presentacion/comun/formato.dart`): `Fmt.distance(640)` → "640 m",
`Fmt.duration(130)` → "2 min", `Fmt.ago(t, now)` → "hace 3 min", `Fmt.time`, `Fmt.date`,
`Fmt.phone`, `Fmt.percent`. Mensajes rápidos: `context.showSnack('...')`.

---

## 6. Patrones de pantalla

**Estructura base**
```dart
Scaffold(
  appBar: AppBar(title: const Text('Título')),
  body: ListenableBuilder(
    listenable: vm,
    builder: (context, _) => ListView(
      padding: AppSpacing.screen,
      children: [ /* contenido con gaps entre bloques */ ],
    ),
  ),
)
```

**Acción principal fija abajo** (Aceptar alerta, Llegué): `Column` con
`Expanded(ListView)` + `SafeArea(top: false, child: Padding(padding: AppSpacing.screen, child: SlButton(...)))`.

**Datos asíncronos:** el ViewModel expone un `EstadoVista<T>` y la View lo pinta con
`SlStateView`, que cubre los cuatro estados (Cargando, Vacío, Error con "Reintentar"
y Listo). Las listas usan `onRefresh` (pull-to-refresh) y `AlwaysScrollableScrollPhysics`.

**Formularios:** `SlTextField` + `errorText: vm.errorCampo`. La View le pasa los textos
al ViewModel (`vm.guardar(nombre: ..., correo: ...)`), y el ViewModel valida con las
reglas del dominio (`ReglaRegistro.*`). El error del servidor va en un `SlBanner`
arriba del formulario y el botón usa `loading: vm.guardando`.

**Mensajes y navegación:** el ViewModel deja un evento de un solo uso (`vm.mensaje`,
`vm.irAMiAlerta`); la View lo escucha con `addListener`, muestra el SnackBar o navega
y llama `vm.consumirEventos()`.

**Bajo estrés** (usuario protegido): una sola acción principal por pantalla, textos cortos, cifras grandes (`displaySmall`), nada importante a menos de 56 px de alto.

---

## 7. Cómo crear una pantalla nueva

1. **Dominio** (`lib/dominio/`): si hace falta, agrega la entidad o la regla. Es Dart
   puro (nada de `package:flutter`). Cada regla vive en un solo lugar y devuelve el
   motivo del rechazo o `null`:
   ```dart
   static String? validarRadio(int metros, {required int minimo, required int maximo}) { ... }
   ```
2. **Datos** (`lib/datos/`): agrega el método al **contrato** (`*_repository.dart`) en
   lenguaje del dominio, impleméntalo en `memoria_*` y en `nube_*` (con su ruta en
   `safelink_service.dart` y su mapeador en `nube_mapeadores.dart`). La prueba
   `test/datos/contrato_repositorios_test.dart` te avisa si las dos no coinciden.
3. **ViewModel** (`presentacion/<rol>/<pantalla>_view_model.dart`): extiende
   `ViewModel` (de `comun/view_model.dart`), recibe el contrato por constructor,
   guarda un `EstadoVista<T>` y expone intenciones (`cargar()`, `guardar()`…).
   Solo importa `foundation`.
4. **Page** (`presentacion/<rol>/<pantalla>_page.dart`): `StatefulWidget` que recibe
   `viewModel`, llama `vm.cargar()` en `initState`, `vm.dispose()` en `dispose` y pinta
   con `ListenableBuilder` + `SlStateView`. Solo tokens y componentes `Sl*`.
5. **Ruta**: constante en `comun/rutas/app_routes.dart`, método en
   `comun/rutas/fabrica_view_models.dart` y `GoRoute` en `comun/rutas/app_router.dart`.
6. **Prueba del ViewModel** en `test/presentacion/` con un `RepositorioEspia` (ver
   `test/presentacion/espias.dart`) y reloj inyectable `DateTime Function()`: sin
   abrir pantallas y sin red.

Cada archivo empieza con un comentario de cabecera: capa, IDs de historia, qué hace
y qué **no** hace.

---

## 8. Cómo repartirse el trabajo sin pisarse

- Cada quien trabaja en **la carpeta de su rol en `presentacion/`** y en su rama
  `feat/<ID>-<descripcion>` desde `develop` (ej. `feat/G-04-detalle-alerta`).
- `dominio/`, `datos/` y `presentacion/comun/` son **compartidos**: cambios ahí en
  PR pequeño y aparte, revisado por otra persona.
- Las pantallas ya existen con datos simulados y comentarios `TODO(<ID>)` donde falta
  algo. Toma la pantalla de tu historia y complétala; no la vuelvas a crear.
- Si necesitas un dato que el repositorio no da, agrégalo al **contrato** y a las
  dos implementaciones (`memoria_` y `nube_`) en el mismo PR.
- Pruebas: `test/dominio/regla_<tema>_test.dart`, `test/presentacion/<pantalla>_view_model_test.dart`
  y `test/interfaz/<id>_<tema>_test.dart`.
