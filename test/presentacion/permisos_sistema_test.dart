// U-01 · U-02 — los permisos del sistema se piden al tocar "Continuar", después de haber
// explicado para qué sirven, y negarse NO deja a nadie sin botón de pánico.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/datos/permisos_sistema.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

/// Sistema de permisos falso: se le dice qué va a contestar y cuenta las veces que preguntan.
class PermisosEspia implements PermisosSistema {
  PermisosEspia({this.respuesta = (camara: true, ubicacion: true, notificaciones: true)});

  EstadoPermisos respuesta;
  int vecesPedidos = 0;
  int vecesConsultados = 0;

  @override
  Future<EstadoPermisos> pedirLosDeLaAlerta() async {
    vecesPedidos++;
    return respuesta;
  }

  @override
  Future<EstadoPermisos> estado() async {
    vecesConsultados++;
    return respuesta;
  }
}

void main() {
  late MemoriaBaseDatos db;
  late MemoriaSesionGuardada almacen;
  late PermisosEspia permisos;

  setUp(() {
    db = MemoriaBaseDatos(latencia: Duration.zero);
    almacen = MemoriaSesionGuardada();
    permisos = PermisosEspia();
  });

  tearDown(() => db.dispose());

  SesionViewModel sesion() =>
      SesionViewModel(MemoriaAuthRepository(db), almacen, permisos: permisos);

  Future<SesionViewModel> conSesionIniciada() async {
    final s = sesion();
    await s.iniciarSesion('usuario@safelink.mx', 'SafeLink1');
    return s;
  }

  test('no se piden antes de explicarlos: entrar a la app no dispara el diálogo', () async {
    await conSesionIniciada();
    expect(permisos.vecesPedidos, 0, reason: 'primero la pantalla explica para qué son');
  });

  test('"Continuar" se los pide al sistema y guarda qué quedó concedido', () async {
    final s = await conSesionIniciada();
    await s.permisosVistos();

    expect(permisos.vecesPedidos, 1);
    expect(s.estadoPermisos, (camara: true, ubicacion: true, notificaciones: true));
  });

  test('negarse NO bloquea la app: la pantalla se cierra igual', () async {
    permisos.respuesta = (camara: false, ubicacion: false, notificaciones: false);
    final s = await conSesionIniciada();
    await s.permisosVistos();

    expect(s.permisosPendientes, isFalse, reason: 'nadie puede quedarse atrapado ahí');
    expect(s.estadoPermisos?.camara, isFalse);
  });

  test('conceder solo una parte se refleja tal cual', () async {
    permisos.respuesta = (camara: false, ubicacion: true, notificaciones: false);
    final s = await conSesionIniciada();
    await s.permisosVistos();

    expect(s.estadoPermisos, (camara: false, ubicacion: true, notificaciones: false));
  });

  test('revisar el estado NO vuelve a preguntar: solo consulta', () async {
    final s = await conSesionIniciada();
    await s.revisarPermisosDelSistema();

    expect(permisos.vecesConsultados, 1);
    expect(permisos.vecesPedidos, 0, reason: 'Configuración no debe soltar diálogos sola');
    expect(s.estadoPermisos, isNotNull);
  });

  test('la pantalla queda marcada como vista aunque los permisos se nieguen', () async {
    permisos.respuesta = (camara: false, ubicacion: false, notificaciones: false);
    final primera = await conSesionIniciada();
    await primera.permisosVistos();

    // Siguiente arranque: no se vuelve a explicar.
    db.usuarioActualId = null;
    final segunda = sesion();
    await segunda.restaurar();
    expect(segunda.permisosPendientes, isFalse);
  });

  test('sin inyectar nada, todo está concedido: la demo y las pruebas no cambian', () async {
    final s = SesionViewModel(MemoriaAuthRepository(db), almacen);
    await s.iniciarSesion('usuario@safelink.mx', 'SafeLink1');
    await s.permisosVistos();
    expect(s.estadoPermisos, (camara: true, ubicacion: true, notificaciones: true));
  });
}
