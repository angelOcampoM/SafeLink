# SafeLink — Guía de estilos y reglas para trabajar en paralelo

> Fuente de verdad visual del proyecto. Todo lo que aparece aquí ya está
> implementado en `lib/core/theme/` y `lib/shared/widgets/`, y se puede ver
> funcionando en la app: **Login → "Ver guía de estilos"** (solo en debug).

---

## 1. Reglas de oro (léelas antes de abrir tu primera vista)

1. **Nada de valores sueltos.** Prohibido en `features/`:
   `Color(0xFF...)`, `Colors.red`, `fontSize: 17`, `EdgeInsets.all(13)`,
   `BorderRadius.circular(10)`. Usa siempre los tokens.
2. **Una sola importación para estilos y otra para widgets:**
   ```dart
   import 'package:safelink/core/theme/theme.dart';
   import 'package:safelink/shared/widgets/widgets.dart';
   ```
   (Dentro de `lib/` también vale la ruta relativa.)
3. **Antes de crear un widget, busca en `shared/widgets/`.** Si lo que
   necesitas sirve a más de una pantalla, va en `shared/` (no en tu feature) y
   se agrega a la guía de estilos viva (`features/dev/style_guide_page.dart`).
4. **Los widgets nativos ya vienen estilizados.** `TextField`, `Card`,
   `FilledButton`, `Switch`, `ChoiceChip`, `NavigationBar`, `SnackBar`,
   `BottomSheet` y `Dialog` toman el estilo del tema global: no les pases
   colores ni bordes.
5. **El rojo `emergency` es sagrado:** solo botón de alerta y alertas activas.
   Para errores y acciones destructivas usa `danger`.
6. **Las vistas nunca llaman a la API ni a datos mock directamente.** Piden la
   interfaz del repositorio: `context.read<GuardAlertRepository>()`.
7. **Textos visibles en español (México); código en inglés.**
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
final s = alert.status.style;   // s.color, s.icon, s.label
StatusChip(alert.status);       // o directamente el chip
TriggerChip(alert.triggerMethod);
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

## 5. Componentes compartidos (`shared/widgets/`)

| Componente | Para qué | Ejemplo |
|---|---|---|
| `SlButton` | Todos los botones. Variantes: `primary`, `success`, `emergency`, `danger`, `secondary`, `ghost`. Soporta `loading`, `icon`, `expand`. | `SlButton(label: 'Aceptar alerta', icon: Icons.check, loading: _busy, onPressed: _accept)` |
| `SlTextField` | Campos con etiqueta arriba, ícono, contraseña con mostrar/ocultar, solo dígitos, máx. longitud | `SlTextField(label: 'Teléfono', digitsOnly: true, maxLength: 10, validator: Validators.phone)` |
| `SlCard` | Contenedor base; `accent` agrega franja y borde de color | `SlCard(accent: AppColors.warning, onTap: ..., child: ...)` |
| `SlChip` / `StatusChip` / `TriggerChip` | Etiquetas de color no interactivas | `StatusChip(alert.status)` |
| `SlBanner` | Mensaje en línea: `info`, `success`, `warning`, `danger` | `SlBanner(type: SlBannerType.warning, message: '...')` |
| `SectionHeader` | Título de sección en mayúsculas con acción opcional | `SectionHeader('Usuarios bloqueados')` |
| `EmptyState` | Listado vacío, fuera de turno, sin resultados | `EmptyState(icon: ..., title: 'Todo tranquilo', message: ...)` |
| `LoadingView` | Cargando centrado | `const LoadingView(message: 'Enviando alerta…')` |
| `InfoRow` | Fila ícono · etiqueta · valor | `InfoRow(icon: Icons.schedule, label: 'Hora', value: '18:17')` |
| `InitialsAvatar` | Avatar con iniciales | `InitialsAvatar(user.initials)` |
| `MetricTile` | Cifra grande + etiqueta (admin) | `MetricTile(label: 'Llegada promedio', value: '7 min')` |
| `AlertCard` | Tarjeta de alerta (guardia, escaladas, historial) | `AlertCard(alert: a, now: now, distanceMeters: 640)` |
| `EmergencyButton` | Botón circular de alerta (solo visual + gestos) | ver `user_home_page.dart` |
| `MapPlaceholder` | Mapa simulado con marcadores, ruta, geocerca y cono de rumbo. Se reemplazará por `GoogleMap` con el mismo tamaño | `MapPlaceholder(showRoute: true, markers: [...])` |

Utilidades de formato (`core/utils/formatters.dart`): `Fmt.distance(640)` → "640 m",
`Fmt.duration(130)` → "2 min", `Fmt.ago(t, now)` → "hace 3 min", `Fmt.time`, `Fmt.date`,
`Fmt.phone`, `Fmt.percent`. Mensajes rápidos: `context.showSnack('...')`.

---

## 6. Patrones de pantalla

**Estructura base**
```dart
Scaffold(
  appBar: AppBar(title: const Text('Título')),
  body: ListView(
    padding: AppSpacing.screen,
    children: [ /* contenido con gaps entre bloques */ ],
  ),
)
```

**Acción principal fija abajo** (Aceptar alerta, Llegué): `Column` con
`Expanded(ListView)` + `SafeArea(top: false, child: Padding(padding: AppSpacing.screen, child: SlButton(...)))`.

**Datos asíncronos:** `FutureBuilder` / `StreamBuilder` con estos tres estados siempre cubiertos:
cargando → `LoadingView`, vacío → `EmptyState`, error → `SlBanner(type: danger)` o `showSnack`.

**Formularios:** `Form` + `SlTextField` + `Validators.*`; error del servidor en `SlBanner` arriba del formulario; botón con `loading`.

**Bajo estrés** (usuario protegido): una sola acción principal por pantalla, textos cortos, cifras grandes (`displaySmall`), nada importante a menos de 56 px de alto.

---

## 7. Cómo repartirse el trabajo sin pisarse

- Cada quien trabaja en **su carpeta de `features/`** y en su rama
  `feat/<ID>-<descripcion>` desde `develop` (ej. `feat/G-04-detalle-alerta`).
- `core/theme/`, `shared/widgets/`, `data/models/` y `data/repositories/` son
  **compartidos**: cambios ahí en PR pequeño y aparte, revisado por otra persona.
- Las pantallas ya existen con datos mock y comentarios `TODO(<ID>)` donde falta
  algo. Toma la pantalla de tu historia y complétala; no la vuelvas a crear.
- Si necesitas un dato que el repositorio no da, agrégalo a la **interfaz** y al
  **mock** (`data/mock/`) en el mismo PR.
- Pruebas: `test/unitaria/<id>_<tema>_test.dart` y `test/interfaz/<id>_<tema>_test.dart`.
