// CR-F02 — con un guardia en sesión, su GPS viaja a la API espaciado; con otro
// rol o sin sesión no se manda nada.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/datos/sensores.dart';
import 'package:safelink/datos/sensores_simulados.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/guardia/seguimiento_guardia.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

/// GPS que se controla desde la prueba: la lectura inicial se resuelve cuando se quiere, y
/// cada llamada a `seguir()` entrega un flujo nuevo (como el real tras pedir permiso).
class UbicacionControlada implements Ubicacion {
  final lecturaInicial = Completer<PuntoGeo?>();
  final flujos = <StreamController<PuntoGeo>>[];

  @override
  Future<PuntoGeo?> posicionActual() => lecturaInicial.future;

  @override
  Stream<PuntoGeo> seguir() {
    final c = StreamController<PuntoGeo>();
    flujos.add(c);
    return c.stream;
  }
}

/// Auth cuyo cierre de sesión en el servidor falla.
class AuthQueFallaAlSalir extends AuthEspia {
  AuthQueFallaAlSalir({super.usuarioActual});

  @override
  Future<void> cerrarSesion() async {
    usuarioActual = null;
    throw Exception('sin red');
  }
}

void main() {
  late AlertaGuardiaEspia alertas;
  late SesionViewModel sesion;
  late SeguimientoGuardia seguimiento;

  SeguimientoGuardia crear({
    required Ubicacion ubicacion,
    RolUsuario rol = RolUsuario.guardia,
    Duration intervalo = Duration.zero,
    AuthEspia? auth,
  }) {
    alertas = AlertaGuardiaEspia(alerta: alertaPrueba(), guardia: guardiaPrueba());
    sesion = SesionViewModel(auth ?? AuthEspia(usuarioActual: usuarioPrueba(rol: rol)), MemoriaSesionGuardada());
    return seguimiento = SeguimientoGuardia(alertas: alertas, ubicacion: ubicacion, sesion: sesion, intervalo: intervalo)
      ..iniciar();
  }

  group('con el GPS simulado', () {
    late UbicacionSimulada ubicacion;

    setUp(() => ubicacion = UbicacionSimulada(inicial: puntoAlerta));
    tearDown(() {
      seguimiento.dispose();
      ubicacion.dispose();
    });

    test('al entrar el guardia manda su posición actual aunque no se mueva', () {
      fakeAsync((async) {
        crear(ubicacion: ubicacion);
        async.flushMicrotasks();

        expect(seguimiento.siguiendo, isTrue);
        expect(alertas.ubicaciones, [puntoAlerta]);
        expect(seguimiento.ultimaPosicion, puntoAlerta);
      });
    });

    test('cada posición del GPS se publica y se manda a la API', () {
      fakeAsync((async) {
        crear(ubicacion: ubicacion);
        async.flushMicrotasks();
        final recibidas = <PuntoGeo>[];
        seguimiento.posiciones.listen(recibidas.add);

        ubicacion
          ..mover()
          ..mover();
        async.flushMicrotasks();

        expect(recibidas, hasLength(2));
        expect(alertas.ubicaciones, hasLength(3), reason: 'la inicial y las dos del GPS');
        expect(seguimiento.ultimaPosicion, recibidas.last);
      });
    });

    test('con intervalo, una ráfaga del GPS no satura la API', () {
      fakeAsync((async) {
        crear(ubicacion: ubicacion, intervalo: const Duration(seconds: 5));
        async.flushMicrotasks();

        for (var i = 0; i < 5; i++) {
          ubicacion.mover();
        }
        async.elapse(const Duration(seconds: 4));
        expect(alertas.ubicaciones, hasLength(1), reason: 'solo la inicial: las demás esperan el intervalo');

        async.elapse(const Duration(seconds: 2));
        expect(alertas.ubicaciones, hasLength(2), reason: 'de la ráfaga solo sale la última');
        expect(alertas.ubicaciones.last, seguimiento.ultimaPosicion);
      });
    });

    for (final rol in [RolUsuario.usuarioProtegido, RolUsuario.admin]) {
      test('con rol ${rol.name} no se manda ubicación de guardia', () {
        fakeAsync((async) {
          crear(ubicacion: ubicacion, rol: rol);
          async.flushMicrotasks();
          ubicacion.mover();
          async.flushMicrotasks();

          expect(seguimiento.siguiendo, isFalse);
          expect(alertas.ubicaciones, isEmpty);
        });
      });
    }

    test('al cerrar sesión deja de mandar', () {
      fakeAsync((async) {
        crear(ubicacion: ubicacion);
        async.flushMicrotasks();
        expect(alertas.ubicaciones, hasLength(1));

        unawaited(sesion.cerrarSesion());
        async.flushMicrotasks();
        ubicacion.mover();
        async.flushMicrotasks();

        expect(seguimiento.siguiendo, isFalse);
        expect(seguimiento.ultimaPosicion, isNull);
        expect(alertas.ubicaciones, hasLength(1), reason: 'nada después del cierre de sesión');
      });
    });

    test('aunque el cierre de sesión falle en el servidor, el GPS se apaga', () {
      fakeAsync((async) {
        crear(ubicacion: ubicacion, auth: AuthQueFallaAlSalir(usuarioActual: usuarioPrueba(rol: RolUsuario.guardia)));
        async.flushMicrotasks();

        unawaited(sesion.cerrarSesion().catchError((Object _) {}));
        async.flushMicrotasks();
        ubicacion.mover();
        async.flushMicrotasks();

        expect(seguimiento.siguiendo, isFalse);
        expect(alertas.ubicaciones, hasLength(1));
      });
    });
  });

  group('con el GPS controlado', () {
    late UbicacionControlada gps;

    setUp(() => gps = UbicacionControlada());
    tearDown(() => seguimiento.dispose());

    test('una lectura inicial que llega después del logout no se manda', () {
      fakeAsync((async) {
        crear(ubicacion: gps, auth: AuthGuardia());
        async.flushMicrotasks();

        unawaited(sesion.cerrarSesion());
        async.flushMicrotasks();
        gps.lecturaInicial.complete(puntoAlerta); // el GPS respondió tarde
        async.flushMicrotasks();

        expect(alertas.ubicaciones, isEmpty);
        expect(seguimiento.ultimaPosicion, isNull);
      });
    });

    test('si el flujo del GPS termina (permiso negado) se vuelve a intentar al reentrar', () {
      fakeAsync((async) {
        crear(ubicacion: gps, auth: AuthGuardia());
        async.flushMicrotasks();
        expect(gps.flujos, hasLength(1));

        unawaited(gps.flujos.first.close()); // seguir() sin permiso termina sin emitir
        async.flushMicrotasks();

        // Cualquier aviso de la sesión (aquí: volver a entrar) lo reintenta.
        unawaited(sesion.cerrarSesion());
        async.flushMicrotasks();
        unawaited(sesion.iniciarSesion('guardia@safelink.mx', 'x'));
        async.flushMicrotasks();

        expect(gps.flujos, hasLength(2), reason: 'se volvió a suscribir al GPS');
      });
    });

    test('un error del GPS no detiene el seguimiento', () {
      fakeAsync((async) {
        crear(ubicacion: gps, auth: AuthGuardia());
        async.flushMicrotasks();

        gps.flujos.first
          ..addError(Exception('GPS interrumpido'))
          ..add(puntoAlerta);
        async.flushMicrotasks();

        expect(alertas.ubicaciones, [puntoAlerta]);
      });
    });
  });
}

/// Auth que, al iniciar sesión, devuelve un guardia (el espía base devuelve un usuario protegido).
class AuthGuardia extends AuthEspia {
  AuthGuardia() : super(usuarioActual: usuarioPrueba(rol: RolUsuario.guardia));

  @override
  Future<Usuario> iniciarSesion({required String correo, required String contrasena}) async =>
      usuarioActual = usuarioPrueba(rol: RolUsuario.guardia);
}
