# BE-02 · Contrato de autenticación, roles y guardias

Lo que el backend debe cumplir para el módulo de autenticación, **sin decidir
cuál es el backend**. Mientras T-04 no se cierre, este documento es el
compromiso: cualquier implementación que lo cumpla deja la app funcionando sin
tocar una línea de la interfaz.

> **Estado:** el contrato está definido y probado contra dos implementaciones
> (en memoria y la API falsa). Falta la real, que depende de BE-01.
> **Prueba que lo verifica:** `test/datos/conformidad_autenticacion.dart`.

---

## Por qué el backend se puede cambiar sin tocar la app

La app no conoce al backend. Habla con dos contratos de la capa de datos:

```
presentación  →  AuthRepository     (sesión)
                 AdminRepository    (guardias)
                        ↑
          memoria_ · nube_ · <el que elijan en T-04>
```

`lib/main.dart` es el único archivo que sabe cuál se enchufa. Cambiar de
backend es cambiar ahí qué implementación se construye.

---

## Operaciones

### `AuthRepository`

| Operación | Entra | Sale | Errores |
|---|---|---|---|
| `registrar` | nombre, correo, teléfono, contraseña | `Usuario` con rol **usuario protegido** y sesión abierta | `EMAIL_TAKEN` |
| `iniciarSesion` | correo, contraseña | `Usuario` con su rol | `INVALID_CREDENTIALS` |
| `restaurarSesion` | id de usuario | `Usuario` o `null` si ya no existe o fue dado de baja | — |
| `cerrarSesion` | — | — | — |
| `refrescarSesion` | — | `Usuario` al día (bloqueo, falsas alarmas) | `UNAUTHORIZED` |
| `actualizarDobleClicVolumen` | activo | `Usuario` actualizado | `UNAUTHORIZED` |
| `usuarioActual` | — | `Usuario` en sesión o `null` | — |

### `AdminRepository`, parte de guardias

| Operación | Entra | Sale | Errores |
|---|---|---|---|
| `crearGuardia` | nombre, correo, teléfono, contraseña inicial | `Guardia` con rol **guardia** | `EMAIL_TAKEN` |
| `actualizarGuardia` | id, nombre?, correo?, teléfono? | `Guardia` actualizado | `EMAIL_TAKEN`, `NOT_FOUND` |
| `darDeBajaGuardia` | id | — | `NOT_FOUND` |
| `obtenerGuardias` | búsqueda por nombre | lista, los dados de baja al final | — |

---

## Reglas que el backend debe garantizar

Estas no son detalles de interfaz: si el backend no las aplica, la app no
puede cumplir sus historias por más que valide en el cliente.

1. **El rol nunca lo elige quien se registra.** El registro público crea
   siempre un usuario protegido. No hay endpoint público que cree guardias ni
   administradores.
2. **El correo es único** en todo el sistema, sin importar el rol.
3. **La cuenta del administrador viene precargada.** Ninguna historia la crea;
   se siembra al preparar el entorno.
4. **Solo el administrador crea guardias**, y elige su contraseña inicial. La
   contraseña nunca se fija en el código.
5. **La baja es lógica, no borrado.** El guardia dado de baja:
   - no puede iniciar sesión (mismo error genérico que una contraseña mala),
   - no entra al despacho de alertas,
   - sigue en el listado del administrador,
   - conserva las alertas que atendió en el historial.
6. **El error de credenciales no revela qué dato falló.** Un correo inexistente
   y una contraseña incorrecta devuelven lo mismo.
7. **La sesión sobrevive al cierre de la app** hasta que el usuario la cierre.

---

## Permisos por rol (insumo para BE-01)

| | Usuario protegido | Guardia | Administrador |
|---|---|---|---|
| Su propio perfil | lee y escribe | lee y escribe | lee y escribe |
| Perfiles ajenos | no | no | lee todos |
| Crear guardias | no | no | sí |
| Editar o dar de baja guardias | no | no | sí |
| Turnos y radios | no | lee el suyo | lee y escribe todos |
| Ver usuarios bloqueados | no | no | sí |

El guardia **nunca** ve la lista de usuarios protegidos, y el usuario protegido
**nunca** ve la ubicación ni los datos de los guardias salvo el nombre del que
lo atiende (U-08).

---

## Errores

El contrato habla en códigos del dominio (`lib/dominio/errores.dart`), no en
códigos HTTP. Quien implemente el backend traduce su error al de aquí:

| Código | Cuándo |
|---|---|
| `INVALID_CREDENTIALS` | correo o contraseña incorrectos, o cuenta dada de baja |
| `EMAIL_TAKEN` | el correo ya está registrado |
| `USER_BLOCKED` | el usuario está bloqueado por falsas alarmas |
| `UNAUTHORIZED` | no hay sesión abierta |
| `NOT_FOUND` | el recurso no existe |
| `SERVICE_UNAVAILABLE` | el backend no respondió |

---

## Cómo se agrega el backend real

1. Crear la implementación de `AuthRepository` y `AdminRepository`.
2. Enchufarla en `lib/main.dart`.
3. Agregar su entorno en `test/datos/conformidad_autenticacion_test.dart`:

```dart
pruebasDeAutenticacion('contra <backend>', () => (
      auth: <Backend>AuthRepository(...),
      admin: <Backend>AdminRepository(...),
      guardia: <Backend>AlertaGuardiaRepository(...),
      cerrar: ...,
    ));
```

Si las 13 pruebas pasan, BE-02 está cumplido para ese backend.
