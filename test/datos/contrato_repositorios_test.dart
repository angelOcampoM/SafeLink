// Repository + Adapter: `memoria_` y `nube_` cumplen el MISMO contrato.
// El mismo escenario (mismos datos, mismo reloj) da el mismo resultado; la nube
// además pasa por JSON (entidad -> Map -> entidad) en cada paso.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/admin_repository.dart';
import 'package:safelink/datos/alerta_guardia_repository.dart';
import 'package:safelink/datos/alerta_usuario_repository.dart';
import 'package:safelink/datos/auth_repository.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/datos/nube_admin_repository.dart';
import 'package:safelink/datos/nube_alerta_guardia_repository.dart';
import 'package:safelink/datos/nube_alerta_usuario_repository.dart';
import 'package:safelink/datos/nube_auth_repository.dart';
import 'package:safelink/datos/safelink_service.dart';
import 'package:safelink/dominio/dominio.dart';

final ahora = DateTime(2026, 10, 26, 13, 0);

typedef Repos = ({
  AuthRepository auth,
  AlertaUsuarioRepository usuario,
  AlertaGuardiaRepository guardia,
  AdminRepository admin,
  void Function() cerrar,
});

MemoriaBaseDatos nuevaDb() => MemoriaBaseDatos(reloj: () => ahora, latencia: Duration.zero);

Repos memoria() {
  final db = nuevaDb();
  return (
    auth: MemoriaAuthRepository(db),
    usuario: MemoriaAlertaUsuarioRepository(db),
    guardia: MemoriaAlertaGuardiaRepository(db),
    admin: MemoriaAdminRepository(db),
    cerrar: db.dispose,
  );
}

Repos nube() {
  final s = SafeLinkService(servidor: nuevaDb(), latenciaMin: Duration.zero, latenciaMax: Duration.zero);
  return (
    auth: NubeAuthRepository(s),
    usuario: NubeAlertaUsuarioRepository(s),
    guardia: NubeAlertaGuardiaRepository(s),
    admin: NubeAdminRepository(s),
    cerrar: s.dispose,
  );
}

/// Corre el escenario y anota lo observable en una lista de textos.
Future<List<String>> escenario(Repos r) async {
  final log = <String>[];
  Future<void> paso(String nombre, Future<Object?> Function() f) async {
    try {
      final v = await f();
      log.add('$nombre: $v');
    } on ErrorDominio catch (e) {
      log.add('$nombre: ERROR ${e.codigo}');
    }
  }

  // Sesión
  await paso('login malo', () => r.auth.iniciarSesion(correo: 'guardia@safelink.mx', contrasena: 'x'));
  await paso('login guardia', () async => (await r.auth.iniciarSesion(correo: 'guardia@safelink.mx', contrasena: 'SafeLink1')).rol);

  // Guardia
  await paso('perfil', () async => (await r.guardia.obtenerMiPerfil()).perfil.radioCoberturaMetros);
  final disponibles = await r.guardia.escucharAlertasDisponibles().first;
  log.add('disponibles: ${disponibles.map((p) => '${p.alerta.id}@${p.distanciaMetros.round()}').join(',')}');
  final id = disponibles.first.alerta.id;
  await paso('detalle', () async => (await r.guardia.obtenerAlerta(id)).metodo);
  await paso('aceptar', () async => (await r.guardia.aceptarAlerta(id)).estado);
  await paso('aceptar otra vez', () => r.guardia.aceptarAlerta(id));
  await paso('llegar lejos', () => r.guardia.marcarLlegada(id));
  final destino = (await r.guardia.obtenerAlerta(id)).ubicacion!;
  await paso('mover', () async {
    await r.guardia.actualizarMiUbicacion(destino);
    return 'ok';
  });
  await paso('llegar', () async => (await r.guardia.marcarLlegada(id)).estado);
  await paso('ignorar', () async {
    await r.guardia.ignorarAlerta(disponibles[1].alerta.id);
    return (await r.guardia.escucharAlertasDisponibles().first).length;
  });
  await paso('mi historial', () async => (await r.guardia.obtenerMiHistorial()).length);
  await paso('mis métricas', () async => (await r.guardia.obtenerMisMetricas()).atendidas);
  await r.auth.cerrarSesion();

  // Administrador
  await r.auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: 'SafeLink1');
  await paso('guardias', () async => (await r.admin.obtenerGuardias(busqueda: 'a')).map((g) => g.usuario.id).join(','));
  await paso('historial cerradas', () async => (await r.admin.obtenerHistorial(const FiltroHistorial(estado: EstadoAlerta.cerrada))).length);
  await paso('historial 7 días grd-1', () async => (await r.admin.obtenerHistorial(FiltroHistorial(desde: ahora.subtract(const Duration(days: 7)), guardiaId: 'grd-1'))).length);
  await paso('historial usuario', () async => (await r.admin.obtenerHistorial(const FiltroHistorial(usuarioId: 'usr-1'))).length);
  await paso('usuarios', () async => (await r.admin.obtenerUsuarios()).map((u) => u.id).join(','));
  await paso('métricas', () async {
    final m = await r.admin.obtenerMetricas(desde: ahora.subtract(const Duration(days: 30)), hasta: ahora);
    return '${m.totalAlertas} ${m.promedioAceptacionSeg.toStringAsFixed(2)} ${m.alertasPorHora}';
  });
  await paso('métricas guardia', () async {
    final m = await r.admin.obtenerMetricasGuardia('grd-1', desde: ahora.subtract(const Duration(days: 7)), hasta: ahora);
    return '${m.atendidas} ${m.promedioAceptacionSeg.toStringAsFixed(2)} ${m.promedioLlegadaSeg.toStringAsFixed(2)} ${m.escaladas}';
  });
  await paso('escaladas', () async => (await r.admin.escucharEscaladas().first).map((a) => a.id).join(','));
  await paso('resolver falsa alarma', () async {
    final a = await r.admin.resolverAlerta('alt-302', Resolucion.falsaAlarma, nota: '  Revisado con la usuaria.  ');
    return '${a.estado} ${a.notaAdmin}';
  });
  await paso('resolver sin nota', () => r.admin.resolverAlerta('alt-303', Resolucion.resuelta, nota: '   '));
  await paso('resolver otra vez', () => r.admin.resolverAlerta('alt-302', Resolucion.resuelta, nota: 'Intento repetido'));
  await paso('bloqueados', () async => (await r.admin.obtenerUsuariosBloqueados()).map((u) => '${u.id}:${u.falsasAlarmas}').join(','));
  await paso('correo repetido', () => r.admin.crearGuardia(nombre: 'Otro', correo: 'guardia@safelink.mx', telefono: '7770000000'));
  await paso('cobertura', () async =>
      (await r.admin.actualizarCobertura('grd-8', inicioTurno: '22:00', finTurno: '06:00', centro: const PuntoGeo(18.84, -99.18), radioMetros: 2500)).perfil.radioCoberturaMetros,);
  await paso('editar', () async => (await r.admin.actualizarGuardia('grd-8', telefono: '7771112233')).usuario.telefono);
  await paso('desbloquear', () async {
    await r.admin.desbloquearUsuario('usr-4');
    return (await r.admin.obtenerUsuariosBloqueados()).length;
  });
  await r.auth.cerrarSesion();

  // Usuario protegido
  await r.auth.iniciarSesion(correo: 'usuario@safelink.mx', contrasena: 'SafeLink1');
  await paso('crear alerta', () async => (await r.usuario.crearAlerta(metodo: MetodoDisparo.mantener, disparadaEn: ahora, ubicacion: const PuntoGeo(18.845, -99.177))).estado);
  await paso('activa', () async => (await r.usuario.escucharAlertaActiva().first)?.metodo);
  await paso('confirmar antes de tiempo', () async {
    final a = await r.usuario.escucharAlertaActiva().first;
    return r.usuario.confirmarAtencion(a!.id);
  });
  await paso('mi historial', () async => (await r.usuario.obtenerHistorial()).length);
  await paso('agitación', () async => (await r.auth.actualizarAgitacion(activa: false)).agitacionActiva);

  r.cerrar();
  return log;
}

void main() {
  test('memoria y nube dan el mismo resultado para el mismo escenario', () async {
    final enMemoria = await escenario(memoria());
    final enNube = await escenario(nube());

    expect(enNube, enMemoria);

    // Y el escenario realmente ejercita las reglas:
    expect(enMemoria, contains('login malo: ERROR INVALID_CREDENTIALS'));
    expect(enMemoria, contains('aceptar otra vez: ERROR ALERT_TAKEN'));
    expect(enMemoria, contains('llegar lejos: ERROR OUTSIDE_GEOFENCE'));
    expect(enMemoria, contains('llegar: EstadoAlerta.guardiaEnLugar'));
    expect(enMemoria, contains('resolver otra vez: ERROR INVALID_STATE'));
    expect(enMemoria, contains('resolver falsa alarma: EstadoAlerta.resueltaPorAdmin Revisado con la usuaria.'));
    expect(enMemoria, contains('resolver sin nota: ERROR INVALID_STATE'));
    expect(enMemoria, contains('correo repetido: ERROR EMAIL_TAKEN'));
    expect(enMemoria, contains('confirmar antes de tiempo: ERROR INVALID_STATE'));
    expect(enMemoria.any((l) => l.startsWith('métricas guardia:')), isTrue);
    expect(enMemoria.any((l) => l.startsWith('métricas guardia: ERROR')), isFalse);
    expect(enMemoria.any((l) => l.startsWith('historial usuario: ERROR')), isFalse);
    expect(enMemoria.any((l) => l.startsWith('usuarios: ERROR')), isFalse);
  });

  test('el servicio con tasaFallo = 1 siempre responde "servicio no disponible"', () async {
    final s = SafeLinkService(servidor: nuevaDb(), tasaFallo: 1, latenciaMin: Duration.zero, latenciaMax: Duration.zero);
    final auth = NubeAuthRepository(s);

    expect(
      () => auth.iniciarSesion(correo: 'admin@safelink.mx', contrasena: 'SafeLink1'),
      throwsA(isA<ServicioNoDisponibleError>()),
    );
    s.dispose();
  });
}
