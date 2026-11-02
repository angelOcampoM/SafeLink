# Revisión de código · rol Administrador (A-01 … A-08)

**Rama revisada:** `feat/A-07-metricas-por-guardia` (commit `7b6cb62`)
**Autor del código:** Leonardo Martínez Vázquez
**Revisor:** Ángel Ocampo · 30/10/2026
**Base de la revisión:** `docs/HISTORIAS_DE_USUARIO.md`, criterio por criterio

> Esta revisión va como archivo porque la rama todavía no tiene Pull Request
> abierto. En cuanto exista, conviene moverla a comentarios del PR y borrar
> este archivo: el Definition of Done pide que la revisión quede registrada
> ahí, con autor y revisor.

---

## Resumen

**30 de 34 criterios cumplidos.** `flutter analyze` sin incidencias y
**105 de 105 pruebas pasan**.

| Historia | Cumplidos | Estado |
|---|---|---|
| A-01 · Alta de guardias | 3 / 4 | Un bloqueante |
| A-02 · Edición y baja de guardias | 5 / 5 | Completa |
| A-03 · Turnos y radios de cobertura | 4 / 4 | Completa |
| A-04 · Bandeja de alertas escaladas | 4 / 5 | Un parcial |
| A-05 · Historial de alertas | 3 / 3 | Completa |
| A-06 · Métricas generales | 3 / 5 | Un bloqueante y un parcial |
| A-07 · Métricas por guardia | 4 / 4 | Completa |
| A-08 · Bloqueo por falsas alarmas | 4 / 4 | Completa |

**A-07, que es el objetivo de esta rama, está completa y es la parte mejor
resuelta del módulo:** las cuatro métricas del criterio, un `DateRangePicker`
real, protección contra respuestas fuera de orden con el contador `_peticion`,
y un resumen de últimas atendidas que degrada sin tumbar la pantalla si falla
la petición. A-02, A-03, A-05 y A-08 también están sólidas.

---

## Bloqueantes

### 1. A-06 · No existe la distribución por zona

El criterio pide *"El panel muestra la distribución de alertas por horario y
por zona"*. `MetricasGenerales` (`lib/dominio/metricas.dart`) solo tiene
`alertasPorHora`; no hay ninguna métrica por zona en dominio, datos ni
presentación. Falta la mitad del criterio, y no está modelada.

### 2. A-01 · El formulario no pide la contraseña inicial

El criterio pide *"El formulario solicita nombre, correo, teléfono y una
contraseña inicial"*. El formulario de `editar_guardia_page.dart` tiene tres
campos, y la contraseña está fija en el código:

```dart
// lib/datos/memoria_admin_repository.dart:50
_db.contrasenas[id] = 'SafeLink1';
```

Todos los guardias nacen con la misma contraseña y la pantalla la anuncia en un
snackbar. Además es una de las cadenas que GitGuardian marca como secreto en el
repositorio.

---

## Parciales

### 3. A-06 · El filtro son periodos fijos, no un rango de fechas

El criterio pide *"Las métricas pueden filtrarse por rango de fechas"*. El panel
ofrece tres chips (7 / 30 / 90 días). A-05 y A-07 ya resuelven esto con
`showDateRangePicker`: se puede reutilizar el mismo patrón.

### 4. A-04 · Desde la bandeja de escaladas no se ve la evidencia

El criterio pide *"El administrador puede consultar el detalle completo de la
alerta, incluida la evidencia"*. La hoja de resolución muestra usuario,
teléfono, guardia y hora de disparo, pero no la fotografía, y no hay forma de
llegar al detalle desde ahí.

`DetalleAlertaAdminPage` sí muestra la evidencia a través de `AlertDetailSheet`,
pero solo se alcanza desde Historial y desde Métricas por guardia. Es el arreglo
más barato de los cuatro: añadir en la tarjeta de escaladas

```dart
onTap: () => context.push(AppRoutes.adminAlertDetail(a.id)),
```

---

## Cobertura de pruebas

Tres de los siete ViewModels del módulo no tienen prueba unitaria:

| ViewModel | Prueba | Historias que cubre |
|---|---|---|
| `panel_view_model` | falta | **A-06, A-08** |
| `guardias_view_model` | falta | A-01, A-02, A-03 |
| `editar_guardia_view_model` | falta | A-01 |
| `cobertura_guardia_view_model` | sí | A-03 |
| `escaladas_view_model` | sí | A-04 |
| `historial_view_model` | sí | A-05 |
| `metricas_guardia_view_model` | sí | A-07 |
| `detalle_alerta_admin_view_model` | sí | A-04, A-05 |

Justo `panel_view_model`, donde están las dos fallas de A-06, es el que no se
prueba. La ruta nueva `/admin/alerts/:id` tampoco pasa por
`test/interfaz/recorrido_roles_test.dart`.

---

## Lo que quedó bien resuelto

Verificado contra el código, no solo contra la interfaz:

- **A-02** · Búsqueda por nombre y correo, diálogo de confirmación antes de dar
  de baja, y `MemoriaAuthRepository` rechaza el inicio de sesión con `!u.activo`.
- **A-03** · `Guardia.disponibleA()` exige las tres condiciones del criterio:
  `usuario.activo && perfil.tieneCobertura && perfil.enTurnoA(hora)`.
- **A-05** · La tarjeta muestra los cinco campos que pide el criterio (fecha,
  usuario, guardia, método y estado) y `FiltroHistorial` combina los cuatro
  filtros.
- **A-08** · El conteo y el bloqueo temporal viven en
  `ReglaAlerta.aplicarFalsaAlarma`, y el desbloqueo manual está en el panel.
