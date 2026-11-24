# SafeLink — Plan de pruebas

Cada caso del esquema de pruebas del equipo, con la prueba automatizada que lo
cubre. **83 casos: 29 de Usuario, 27 de Guardia y 27 de Administrador.**

Estado al 02/11/2026 · rama `feat/pruebas-tres-roles` · **309 pruebas pasan**,
`flutter analyze` sin incidencias.

| | Significado |
|---|---|
| ✅ | Cubierto por una prueba automatizada que corre en `flutter test` |
| 📱 | Solo verificable en dispositivo físico: **no automatizable hoy** |

---

## Usuario protegido — 29 casos · 29 cubiertos

| Historia | Qué comprueba | Tipo | | Prueba |
|---|---|---|---|---|
| U-01 | Errores de validación junto a cada campo | Interfaz | ✅ | `u01_registro_test` |
| U-01 | Validadores de correo, teléfono y contraseña | Unitaria | ✅ | `regla_registro_test` |
| U-01 | Rol correcto y correos no duplicados | Integración | ✅ | `u01_registro_test` |
| U-02 | Mensaje de error y solicitud de permisos | Interfaz | ✅ | `u02_login_test`, `u01_permisos_test` |
| U-02 | Redirección según el rol | Unitaria | ✅ | `redireccion_rol_test` |
| U-02 | Inicio de sesión y persistencia | Integración | ✅ | `u02_sesion_persistente_test`, `sesion_view_model_test` |
| U-03 | Cuenta regresiva y botón Cancelar | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-03 | Lógica del temporizador | Unitaria | ✅ | `inicio_view_model_test` |
| U-03 | Envío al terminar la cuenta | Integración | ✅ | `inicio_view_model_test` |
| U-04 | Aparición y resaltado de la zona de descarte | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-04 | Soltar dentro o fuera de la zona | Unitaria | ✅ | `inicio_view_model_test` |
| U-04 | Sin límite de tiempo al mantener | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-04 | Registro según la acción final | Integración | ✅ | `inicio_view_model_test` |
| U-05 | Detección del doble clic | Unitaria | ✅ | `regla_doble_clic_test` |
| U-05 | Registro de la alerta y vibración | Integración | ✅ | `disparo_rapido_test` |
| U-05 | Configuración y notificación persistente | Interfaz | ✅ | `disparo_rapido_test` |
| U-06 | Captura completa al disparar | Integración | ✅ | `inicio_view_model_test` |
| U-06 | Origen de los datos de la evidencia | Unitaria | ✅ | `inicio_view_model_test` |
| U-06 | Comportamiento cuando la foto no se genera | Integración | ✅ | `inicio_view_model_test` |
| U-06 | Aviso cuando no hay coordenadas válidas | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-07 | Indicador de ubicación compartida | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-07 | Inicio y fin de la transmisión | Unitaria | ✅ | `seguimiento_ubicacion_test` |
| U-07 | Transmisión mientras la alerta está activa | Integración | ✅ | `seguimiento_ubicacion_test` |
| U-08 | Estados de la pantalla de espera | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-08 | Cálculo del tiempo estimado | Unitaria | ✅ | `regla_eta_test` |
| U-08 | Actualización en vivo y privacidad del guardia | Integración | ✅ | `u03_u08_usuario_test` |
| U-09 | Habilitación del botón "Ya fui atendido" | Interfaz | ✅ | `u03_u08_usuario_test` |
| U-09 | Reglas de cierre de la alerta | Unitaria | ✅ | `regla_alerta_test` |
| U-09 | Escalamiento por falta de confirmación | Integración | ✅ | `regla_alerta_test`, `simulaciones_test` |

---

## Guardia de respuesta — 27 casos · 23 cubiertos · 4 📱

| Historia | Qué comprueba | Tipo | | Prueba |
|---|---|---|---|---|
| G-01 | Pantalla de inicio de sesión y rechazo de accesos | Interfaz | ✅ | `u02_login_test` |
| G-01 | Redirección según el rol | Unitaria | ✅ | `redireccion_rol_test` |
| G-01 | Acceso solo con cuentas creadas por el administrador | Integración | ✅ | `editar_guardia_view_model_test`, `contrato_repositorios_test` |
| G-02 | Filtro de guardias que reciben la notificación | Unitaria | ✅ | `alertas_por_guardia_test` |
| G-02 | Apertura del detalle desde la notificación | Interfaz | 📱 | Requiere FCM |
| G-02 | Envío solo a los guardias que corresponden | Integración | ✅ | `alertas_por_guardia_test` |
| G-02 | Recepción en Android con el teléfono en silencio | Integración | 📱 | Requiere dispositivo |
| G-02 | Recepción en iOS | Integración | 📱 | Requiere dispositivo |
| G-03 | Función de ordenamiento de alertas | Unitaria | ✅ | `regla_prioridad_test` |
| G-03 | Información e indicadores de cada tarjeta | Interfaz | ✅ | `g03_filtros_listado_test`, `ds_componentes_test` |
| G-03 | Estado vacío del listado | Interfaz | ✅ | `g03_recarga_guardia_test` |
| G-03 | Filtro del listado por radio y turno | Integración | ✅ | `alertas_por_guardia_test` |
| G-03 | Actualización del listado en tiempo real | Integración | ✅ | `listado_alertas_view_model_test` |
| G-04 | Elementos de la pantalla de detalle | Interfaz | ✅ | `guardia_detalle_navegacion_test` |
| G-04 | Conversión del rumbo a la orientación en el mapa | Unitaria | ✅ | `regla_geocerca_test` |
| G-04 | Carga de los datos de la alerta seleccionada | Integración | ✅ | `detalle_alerta_view_model_test` |
| G-04 | Indicación de evidencia incompleta | Interfaz | ✅ | `guardia_detalle_navegacion_test` |
| G-05 | Botón de aceptar y cambio de estado | Interfaz | ✅ | `guardia_detalle_navegacion_test` |
| G-05 | Reglas de aceptación | Unitaria | ✅ | `regla_alerta_test` |
| G-05 | Aceptación simultánea desde dos dispositivos | Integración | ✅ | `detalle_alerta_view_model_test` |
| G-06 | Elementos de la pantalla de navegación | Interfaz | ✅ | `guardia_detalle_navegacion_test` |
| G-06 | Cálculo de la distancia restante | Unitaria | ✅ | `regla_geocerca_test` |
| G-06 | Actualización de la ruta cuando el usuario se mueve | Integración | ✅ | `navegacion_view_model_test` |
| G-06 | Apertura de la ruta en Google Maps | Integración | 📱 | Requiere `url_launcher` y app externa |
| G-07 | Validación de la geocerca | Unitaria | ✅ | `regla_geocerca_test` |
| G-07 | Estado del botón "Llegué" | Interfaz | ✅ | `guardia_detalle_navegacion_test` |
| G-07 | Registro de la llegada | Integración | ✅ | `guardia_detalle_navegacion_test`, `navegacion_view_model_test` |

---

## Administrador — 27 casos · 27 cubiertos

| Historia | Qué comprueba | Tipo | | Prueba |
|---|---|---|---|---|
| A-01 | Mensajes de validación del formulario | Interfaz | ✅ | `admin_pantallas_test` |
| A-01 | Validadores de los datos del guardia | Unitaria | ✅ | `editar_guardia_view_model_test`, `regla_registro_test` |
| A-01 | Creación de la cuenta del guardia | Integración | ✅ | `editar_guardia_view_model_test` |
| A-02 | Búsqueda y diálogo de confirmación | Interfaz | ✅ | `admin_pantallas_test` |
| A-02 | Búsqueda por nombre sin importar acentos | Unitaria | ✅ | `texto_busqueda_test`, `guardias_view_model_test` |
| A-02 | Edición de los datos del guardia | Integración | ✅ | `editar_guardia_view_model_test` |
| A-02 | Efectos de la baja de un guardia | Integración | ✅ | `guardias_view_model_test`, `historial_por_guardia_test` |
| A-03 | Selector de horario y radio en el mapa | Interfaz | ✅ | `admin_pantallas_test` |
| A-03 | Función que determina si un guardia está en turno | Unitaria | ✅ | `regla_turno_test` |
| A-03 | Efecto del turno y el radio en la recepción | Integración | ✅ | `alertas_por_guardia_test` |
| A-04 | Reglas de escalamiento | Unitaria | ✅ | `regla_alerta_test` |
| A-04 | Llegada automática de alertas a la bandeja | Integración | ✅ | `simulaciones_test` |
| A-04 | Detalle y acciones de resolución | Interfaz | ✅ | `admin_pantallas_test`, `detalle_escalada_view_model_test` |
| A-05 | Información del listado y del detalle | Interfaz | ✅ | `admin_pantallas_test` |
| A-05 | Función de filtrado | Unitaria | ✅ | `filtro_historial_test` |
| A-05 | Registro de alertas cerradas en el historial | Integración | ✅ | `historial_por_guardia_test` |
| A-06 | Cálculo de promedios y porcentajes | Unitaria | ✅ | `regla_metricas_test` |
| A-06 | Elementos del panel de métricas | Interfaz | ✅ | `admin_pantallas_test` |
| A-06 | El panel cuando no hay datos | Interfaz | ✅ | `admin_pantallas_test`, `panel_view_model_test` |
| A-06 | Filtro por rango de fechas | Integración | ✅ | `panel_view_model_test` |
| A-07 | Cálculo de métricas de un solo guardia | Unitaria | ✅ | `regla_metricas_test` |
| A-07 | Elementos de la pantalla de métricas por guardia | Interfaz | ✅ | `admin_pantallas_test` |
| A-07 | Actualización con nuevas alertas y filtro de fechas | Integración | ✅ | `metricas_guardia_view_model_test` |
| A-08 | Regla de bloqueo | Unitaria | ✅ | `regla_alerta_test` |
| A-08 | Aviso al usuario bloqueado | Interfaz | ✅ | `recorrido_roles_test` |
| A-08 | Bloqueo a partir de la bandeja | Integración | ✅ | `detalle_escalada_view_model_test` |
| A-08 | Retiro manual del bloqueo | Integración | ✅ | `admin_pantallas_test`, `panel_view_model_test` |

---

## Los 4 casos que no se pueden automatizar

Son los marcados 📱 en la tabla del guardia. Necesitan servicios externos que el
proyecto todavía no tiene: notificaciones push reales (FCM), la app de Google Maps
instalada y un teléfono iOS, que además no existe (no hay carpeta `ios/`).

| Historia | Caso | Qué hace falta |
|---|---|---|
| G-02 | Apertura del detalle desde la notificación | Un proyecto de Firebase |
| G-02 | Recepción en Android con el teléfono en silencio | Un proyecto de Firebase |
| G-02 | Recepción en iOS | No hay app de iOS |
| G-06 | Apertura de la ruta en Google Maps | Clave de Google Maps y `url_launcher` |

**Acuerdo del equipo:** quedan marcados como *prueba manual en dispositivo*. Se
ejecutan una vez cuando existan esas credenciales y se adjunta la captura como
evidencia. Si se dejaran como pruebas automatizadas estarían en rojo para siempre
sin que eso signifique nada.

**Lo que sí se verificó en un teléfono** (vivo V2441, Android 16, el 22/11/2026):
los permisos del sistema, la cámara, el GPS, el rumbo y el doble clic de volumen
con la pantalla apagada y bloqueada. Ese paso encontró cuatro fallos que ninguna
prueba automática podía ver, porque viven en la frontera con el sistema operativo
(ver D53 en `DECISIONES.md`). Detalle y pasos en `CONEXION_DISPOSITIVO.md` §11-§12.

## Backend, tarjeta BE-04 (despacho de alertas al guardia)

Casos del backend que cubren, del lado del servidor, las historias G-02, G-03, G-05 (HU-11, HU-12 y HU-24 del issue #54, D33) y las de soporte G-04, G-06 y G-07. Se ejecutan con `npm test` desde `backend/` (Vitest). Las pruebas de integración usan Postgres real (`safelink_test`; ver `backend/README.md`); las unitarias no necesitan base. Rutas de archivo relativas a `backend/tests/`. Este bloque no cuenta en los 83 casos del front. Ninguna de estas pruebas toca FCM real (D43).

| Historia | Qué comprueba | Tipo | Prueba |
|---|---|---|---|
| G-02 / HU-11 | El push se envía al crear la alerta con ubicación o al llegar la primera ubicación; no por movimiento; no si ya no está en `searching` o no hay guardias con token | Integración | `integration/despacho/push-alerta.test.ts` |
| G-02 | Destinatarios: solo guardias en radio, en turno, activos, sin ignorar y con sesión viva (revocada o vencida no reciben); un solo envío con tokens sin repetidos | Integración | `integration/despacho/push-alerta.test.ts` |
| G-02 | Tope `PUSH_MAX_TOKENS_PER_ALERT` (los más cercanos) y su validación de rango | Integración y unitaria | `integration/despacho/push-alerta.test.ts`, `unit/be04-despacho-env.test.ts` |
| G-02 | El push no retrasa ni rompe la respuesta HTTP; los fallos se absorben; los logs solo llevan ids y conteos | Integración | `integration/despacho/push-alerta.test.ts` |
| G-02 | Formato FCM v1 (datos en texto, bloque `android` y `apns`), OAuth con JWT RS256, reintentos, `Retry-After`, redirecciones | Unitaria (con `fetch` simulado) | `unit/be04-push.test.ts` |
| G-02 | Tokens inválidos: solo `404 UNREGISTERED` o `400` con `message.token`; salvaguarda cuando todos salen inválidos; no se borran tokens ajenos | Unitaria e integración | `unit/be04-push.test.ts`, `integration/despacho/push-alerta.test.ts` |
| G-02 | Cuenta de servicio inválida (la API no arranca, el error no muestra su contenido); `none` por defecto; no-op y doble de pruebas | Unitaria | `unit/be04-push.test.ts`, `unit/be04-server-arranque.test.ts` |
| G-02 | Token de dispositivo: registro idempotente y reasignación, validación (400), solo `guard` (401/403), rate limit (429), logout y revocación borran los tokens, token no aparece en respuestas ni logs | Integración | `integration/dispositivos/device-token.test.ts`, `device-token-limite.test.ts`, `device-token-logs.test.ts` |
| G-02 | Apertura del detalle desde la notificación; recepción en Android en silencio y en iOS | 📱 | Requiere FCM y dispositivo (D45): **no automatizable hoy** |
| G-03 / HU-12 | Canal `guard/alerts`: permisos antes de abrir el stream, snapshot por guardia, visibilidad, `userPhone` nulo, orden y cifras, cambios en vivo, límite de conexiones por (usuario, canal) | Integración | `integration/guardia/canal-guard-alerts.test.ts`, `unit/be04-sse-multicanal.test.ts` |
| G-03 | Orden del listado (urgentes primero, luego `score`), equivalente a `regla_prioridad.dart` | Unitaria | `unit/be04-prioridad.test.ts` |
| G-03 | `ignore`: idempotente, desaparece solo para ese guardia, 404 idéntico para lo no visible, alerta propia asignada sin efecto, permisos, tiempo real | Integración | `integration/guardia/guardia-ignorar.test.ts` |
| G-04 | `GET /guard/alerts/:id`: alertas visibles y 404 con el mismo cuerpo para lo demás; canal `guard/alerts/:id` (asignada, disponible, ajena, `:id` no UUID, seguridad de datos) | Integración | `integration/guardia/guardia-lectura.test.ts`, `integration/guardia/canal-guard-alerta-detalle.test.ts` |
| G-01 / extra | `GET /guard/me`, `/guard/history` y `/guard/metrics`; sin `passwordHash`; minimización de datos (D23) y cálculo de métricas | Integración y unitaria | `integration/guardia/guardia-lectura.test.ts`, `unit/be04-metricas-y-vista-guardia.test.ts` |
| G-05 / HU-24 | `accept`: éxito, 404 idéntico, `ALERT_TAKEN`, "ya atiendes otra" (D36), permisos, el guardia no cierra la alerta, aceptación simultánea (concurrencia), tiempo real | Integración | `integration/guardia/guardia-aceptar.test.ts` |
| G-05 | Restricciones de base: `alerts_guard_absent_chk` y `alerts_one_active_per_guard_idx` | Integración (BD) | `integration/db/restricciones-asignacion.test.ts` |
| G-06 | `PUT /guard/location`: éxito, validación, permisos, el dueño recibe el ETA nuevo, rate limit por guardia, logs sin coordenadas | Integración | `integration/guardia/guardia-ubicacion.test.ts`, `integration/guardia/guardia-ubicacion-limite.test.ts` |
| G-07 | `arrive`: éxito, 404, 409 si ya no está en `in_progress`, 422 `OUTSIDE_GEOFENCE` con `remainingMeters` (y `null` sin ubicación), permisos, concurrencia, tiempo real | Integración | `integration/guardia/guardia-llegada.test.ts` |
| U-08 / D47 | ETA del dueño redondeado y ajustado a la celda; guardia y admin ven el exacto; ubicaciones falsas solo revelan la celda | Unitaria e integración | `unit/be04-llegada-eta.test.ts`, `integration/guardia/guardia-llegada.test.ts` |
| G-02 a G-07, U-03, U-09 | Flujo completo de una alerta con las rutas reales del guardia | Integración | `integration/flujo/flujo-completo.test.ts` |
| Permisos | Matriz rol × ruta (incluye las rutas y canales de BE-04 y el token de dispositivo) y paridad de la política con el contrato | Integración y unitaria | `integration/seguridad/matriz-permisos.test.ts`, `unit/politicas-contrato.test.ts` |

## Historial de decisiones

- **01/11/2026 · G-01.** El equipo decidió que el guardia no ve pantalla de
  permisos. La fila del esquema se reemplazó por "La pantalla de inicio de
  sesión y el rechazo de accesos", que sí describe lo que la app hace.
- **02/11/2026 · G-04.** El esquema pide los avisos literales "Fotografía no
  disponible" y "Rumbo no disponible". La app decía "Evidencia incompleta: sin
  foto" y omitía la fila del rumbo; se alineó el código al esquema.
- **02/11/2026 · A-06.** El esquema pide que un periodo sin alertas muestre las
  métricas en cero. El panel mostraba solo un aviso; ahora pinta las tarjetas
  en cero además del aviso.
- **02/11/2026 · A-02.** El esquema pide que la búsqueda devuelva *únicamente
  los guardias cuyo nombre coincide*. La búsqueda también encontraba por correo
  y el campo decía "Buscar por nombre o correo"; se retiró el correo para
  cumplir el criterio al pie de la letra. La normalización de mayúsculas y
  acentos se conserva: el esquema ya no la pide, pero tampoco la prohíbe y
  evita que "hernandez" deje fuera a Hernández.
