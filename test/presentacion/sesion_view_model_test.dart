// U-02 — la sesión y los permisos vistos sobreviven al cierre de la app.
// Se usa el almacén en memoria compartido entre dos SesionViewModel: el segundo
// representa el siguiente arranque de la aplicación.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

void main() {
  late MemoriaBaseDatos db;
  late MemoriaSesionGuardada almacen;

  setUp(() {
    db = MemoriaBaseDatos(latencia: Duration.zero);
    almacen = MemoriaSesionGuardada();
  });

  tearDown(() => db.dispose());

  /// Un arranque nuevo de la app: los datos del "servidor" siguen ahí, pero el
  /// cliente olvidó quién estaba dentro. Lo único que sobrevive es el almacén.
  SesionViewModel arranque({bool reinicio = false}) {
    if (reinicio) db.usuarioActualId = null;
    return SesionViewModel(MemoriaAuthRepository(db), almacen);
  }

  test('tras iniciar sesión, el siguiente arranque la reabre sin pasar por el login', () async {
    final primera = arranque();
    await primera.iniciarSesion('usuario@safelink.mx', 'SafeLink1');
    expect(primera.usuario?.correo, 'usuario@safelink.mx');

    final segunda = arranque(reinicio: true);
    expect(segunda.haySesion, isFalse, reason: 'antes de restaurar no hay nadie');
    await segunda.restaurar();

    expect(segunda.haySesion, isTrue);
    expect(segunda.usuario?.id, 'usr-1');
  });

  test('cerrar sesión borra lo guardado: el siguiente arranque pide credenciales', () async {
    final primera = arranque();
    await primera.iniciarSesion('usuario@safelink.mx', 'SafeLink1');
    await primera.cerrarSesion();

    final segunda = arranque(reinicio: true);
    await segunda.restaurar();

    expect(segunda.haySesion, isFalse);
  });

  test('los permisos solo se explican una vez, aunque la app se reinicie', () async {
    final primera = arranque();
    await primera.iniciarSesion('usuario@safelink.mx', 'SafeLink1');
    expect(primera.permisosPendientes, isTrue, reason: 'primera vez: se explican');
    await primera.permisosVistos();

    final segunda = arranque(reinicio: true);
    await segunda.restaurar();

    expect(segunda.haySesion, isTrue);
    expect(segunda.permisosPendientes, isFalse);
  });

  test('si la cuenta fue dada de baja, no se reabre y el almacén queda limpio', () async {
    final primera = arranque();
    await primera.iniciarSesion('usuario@safelink.mx', 'SafeLink1');

    db.usuarios['usr-1'] = db.usuarios['usr-1']!.copyWith(activo: false);

    final segunda = arranque(reinicio: true);
    await segunda.restaurar();

    expect(segunda.haySesion, isFalse);
    expect(await almacen.leerUsuarioId(), isNull);
  });
}
