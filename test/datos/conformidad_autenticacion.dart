// BE-02 — suite de conformidad de autenticación, roles y guardias.
//
// Describe lo que el módulo debe cumplir SIN decir con qué backend. Hoy la
// pasan la implementación en memoria y la de la API falsa; cuando el equipo
// elija el backend de T-04, su implementación se agrega con una línea y esta
// misma suite dice si cumple.
//
// Cubre los siete pasos del issue #52:
//   1. Registro de usuario protegido con el rol asignado automáticamente
//   2. Rechazo de correos duplicados
//   3. Inicio de sesión para los tres roles con sesión persistente
//   4. Cuenta del administrador precargada
//   5. Alta de guardias por el administrador con contraseña inicial
//   6. Edición y baja de guardias
//   7. Un guardia dado de baja no puede iniciar sesión ni recibir alertas
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/admin_repository.dart';
import 'package:safelink/datos/alerta_guardia_repository.dart';
import 'package:safelink/datos/auth_repository.dart';
import 'package:safelink/dominio/dominio.dart';

/// Lo que cada implementación debe entregar para correr la suite.
typedef EntornoAuth = ({
  AuthRepository auth,
  AdminRepository admin,
  AlertaGuardiaRepository guardia,
  void Function() cerrar,
});

/// Contraseña de las cuentas sembradas.
const contrasenaSemilla = 'SafeLink1';

void pruebasDeAutenticacion(String implementacion, EntornoAuth Function() crear) {
  group('BE-02 · $implementacion', () {
    late EntornoAuth r;

    setUp(() => r = crear());
    tearDown(() => r.cerrar());

    // ── 1 y 2 · Registro ────────────────────────────────────────────────

    test('el registro público crea siempre un usuario protegido', () async {
      final u = await r.auth.registrar(
        nombre: 'Ana López Ruiz',
        correo: 'ana.nueva@mail.com',
        telefono: '7771234567',
        contrasena: 'SafeLink1',
      );

      expect(u.rol, RolUsuario.usuarioProtegido, reason: 'el rol no lo elige quien se registra');
      expect(u.activo, isTrue);
      expect(r.auth.usuarioActual?.id, u.id, reason: 'queda con la sesión abierta');
    });

    test('un correo ya registrado se rechaza y no crea la cuenta', () async {
      await expectLater(
        r.auth.registrar(nombre: 'Otra Persona', correo: 'usuario@safelink.mx', telefono: '7770000000', contrasena: 'SafeLink1'),
        throwsA(isA<CorreoRegistradoError>()),
      );
      expect(r.auth.usuarioActual, isNull, reason: 'no abre sesión con una cuenta que no creó');
    });

    // ── 3 y 4 · Inicio de sesión de los tres roles ──────────────────────

    test('cada rol entra con su cuenta', () async {
      for (final (correo, rol) in [
        ('usuario@safelink.mx', RolUsuario.usuarioProtegido),
        ('guardia@safelink.mx', RolUsuario.guardia),
        ('admin@safelink.mx', RolUsuario.admin),
      ]) {
        final u = await r.auth.iniciarSesion(correo: correo, contrasena: contrasenaSemilla);
        expect(u.rol, rol, reason: correo);
        await r.auth.cerrarSesion();
      }
    });

    test('la cuenta del administrador viene precargada: ninguna historia la crea', () async {
      final admin = await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);
      expect(admin.rol, RolUsuario.admin);
      expect(admin.activo, isTrue);
    });

    test('una contraseña incorrecta no abre sesión', () async {
      await expectLater(
        r.auth.iniciarSesion(correo: 'usuario@safelink.mx', contrasena: 'equivocada'),
        throwsA(isA<CredencialesInvalidasError>()),
      );
      expect(r.auth.usuarioActual, isNull);
    });

    test('un correo que no existe no revela que no existe', () async {
      await expectLater(
        r.auth.iniciarSesion(correo: 'nadie@safelink.mx', contrasena: contrasenaSemilla),
        throwsA(isA<CredencialesInvalidasError>()),
      );
    });

    test('la sesión se puede reabrir por su id y se cierra al salir', () async {
      final u = await r.auth.iniciarSesion(correo: 'usuario@safelink.mx', contrasena: contrasenaSemilla);
      await r.auth.cerrarSesion();
      expect(r.auth.usuarioActual, isNull);

      final reabierta = await r.auth.restaurarSesion(u.id);
      expect(reabierta?.id, u.id, reason: 'U-02: la sesión sobrevive al cierre de la app');
      expect(r.auth.usuarioActual?.id, u.id);
    });

    // ── 5 y 6 · Gestión de guardias ─────────────────────────────────────

    test('el administrador da de alta a un guardia con la contraseña que elige', () async {
      await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);

      final nuevo = await r.admin.crearGuardia(
        nombre: 'Nuevo Guardia Pérez',
        correo: 'nuevo.guardia@safelink.mx',
        telefono: '7770000001',
        contrasena: 'Guardia123',
      );
      expect(nuevo.usuario.rol, RolUsuario.guardia);

      final listado = await r.admin.obtenerGuardias();
      expect(listado.map((g) => g.usuario.correo), contains('nuevo.guardia@safelink.mx'));

      // La cuenta sirve: el guardia entra con esa contraseña inicial.
      await r.auth.cerrarSesion();
      final entrando = await r.auth.iniciarSesion(correo: 'nuevo.guardia@safelink.mx', contrasena: 'Guardia123');
      expect(entrando.rol, RolUsuario.guardia);
    });

    test('no se puede dar de alta un guardia con un correo ya usado', () async {
      await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);
      await expectLater(
        r.admin.crearGuardia(nombre: 'Repetido', correo: 'guardia@safelink.mx', telefono: '7770000002', contrasena: 'Guardia123'),
        throwsA(isA<CorreoRegistradoError>()),
      );
    });

    test('la edición de un guardia se refleja al volver a consultarlo', () async {
      await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);

      await r.admin.actualizarGuardia('grd-1', nombre: 'Carlos Hernández Editado', telefono: '7779998877');
      final g = await r.admin.obtenerGuardia('grd-1');

      expect(g.usuario.nombre, 'Carlos Hernández Editado');
      expect(g.usuario.telefono, '7779998877');
    });

    // ── 7 · La baja cierra la puerta ────────────────────────────────────

    test('un guardia dado de baja no puede iniciar sesión', () async {
      await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);
      await r.admin.darDeBajaGuardia('grd-1');
      await r.auth.cerrarSesion();

      await expectLater(
        r.auth.iniciarSesion(correo: 'guardia@safelink.mx', contrasena: contrasenaSemilla),
        throwsA(isA<CredencialesInvalidasError>()),
      );
    });

    test('un guardia dado de baja deja de estar disponible para recibir alertas', () async {
      await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);
      final antes = await r.admin.obtenerGuardia('grd-1');
      expect(antes.disponibleA(DateTime.now()), isTrue, reason: 'estaba en turno y con zona');

      await r.admin.darDeBajaGuardia('grd-1');
      final despues = await r.admin.obtenerGuardia('grd-1');

      expect(despues.usuario.activo, isFalse);
      expect(despues.disponibleA(DateTime.now()), isFalse, reason: 'ya no entra al despacho');
    });

    test('la baja es lógica: el guardia sigue en el listado y conserva su historial', () async {
      await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: contrasenaSemilla);
      final historialAntes = await r.admin.obtenerHistorial(const FiltroHistorial(guardiaId: 'grd-1'));

      await r.admin.darDeBajaGuardia('grd-1');

      final listado = await r.admin.obtenerGuardias();
      expect(listado.map((g) => g.usuario.id), contains('grd-1'), reason: 'A-02: no se borra');
      final historialDespues = await r.admin.obtenerHistorial(const FiltroHistorial(guardiaId: 'grd-1'));
      expect(historialDespues.length, historialAntes.length, reason: 'sus alertas atendidas se conservan');
    });
  });
}
