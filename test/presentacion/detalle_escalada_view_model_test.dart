// A-04/A-08 Detalle de escalada — ViewModel con la semilla en memoria (reloj
// fijo) para la nota, la confirmación y el efecto de la falsa alarma; la
// espía cubre los errores del repositorio.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/detalle_escalada_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';

import 'espias.dart';

void main() {
  late MemoriaBaseDatos db;
  late DetalleEscaladaViewModel vm;

  setUp(() {
    db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
    vm = DetalleEscaladaViewModel(MemoriaAdminRepository(db), 'alt-301');
  });

  tearDown(() {
    vm.dispose();
    db.dispose();
  });

  test('carga la alerta escalada con su motivo', () async {
    await vm.cargar();

    expect(vm.estado.datos?.id, 'alt-301');
    expect(vm.estado.datos?.razonEscalamiento, RazonEscalamiento.sinRespuesta);
  });

  test('un id inexistente deja el estado en Vacio', () async {
    final otro = DetalleEscaladaViewModel(MemoriaAdminRepository(db), 'alt-inexistente');
    await otro.cargar();

    expect(otro.estado, isA<Vacio<Alerta>>());
    otro.dispose();
  });

  test('no resuelve sin la confirmación de revisión', () async {
    await vm.cargar();

    final ok = await vm.resolver(Resolucion.resuelta, nota: 'Se revisó la alerta');

    expect(ok, isFalse);
    expect(vm.mensaje, 'Confirma que revisaste y atendiste la alerta antes de resolver');
    expect(db.alertaPorId('alt-301').estado, EstadoAlerta.escalada);
  });

  test('no resuelve sin nota administrativa', () async {
    await vm.cargar();
    vm.cambiarRevision(true);

    final ok = await vm.resolver(Resolucion.resuelta, nota: '   ');

    expect(ok, isFalse);
    expect(vm.errorNota, 'Escribe una nota administrativa para resolver la alerta');
    expect(db.alertaPorId('alt-301').estado, EstadoAlerta.escalada);
  });

  test('resuelta guarda la nota, la resolución y la hora de cierre', () async {
    await vm.cargar();
    vm.cambiarRevision(true);

    final ok = await vm.resolver(Resolucion.resuelta, nota: '  Se contactó al usuario; sin riesgo.  ');

    final a = db.alertaPorId('alt-301');
    expect(ok, isTrue);
    expect(a.estado, EstadoAlerta.resueltaPorAdmin);
    expect(a.resolucion, Resolucion.resuelta);
    expect(a.notaAdmin, 'Se contactó al usuario; sin riesgo.');
    expect(a.cerradaEn, ahoraPrueba);
    expect(db.usuarios['usr-3']!.falsasAlarmas, 0);
  });

  test('falsa alarma incrementa el contador sin bloquear bajo el límite', () async {
    final vm6 = DetalleEscaladaViewModel(MemoriaAdminRepository(db), 'alt-303');
    await vm6.cargar();
    vm6.cambiarRevision(true);

    final ok = await vm6.resolver(Resolucion.falsaAlarma, nota: 'Se revisó la cámara; no hubo emergencia.');

    expect(ok, isTrue);
    expect(db.usuarios['usr-6']!.falsasAlarmas, 2);
    expect(db.usuarios['usr-6']!.bloqueadoEn(ahoraPrueba), isFalse);
    vm6.dispose();
  });

  test('al llegar al límite bloquea al usuario y la alerta sale de la bandeja', () async {
    final vm2 = DetalleEscaladaViewModel(MemoriaAdminRepository(db), 'alt-302');
    await vm2.cargar();
    vm2.cambiarRevision(true);

    await vm2.resolver(Resolucion.falsaAlarma, nota: 'Sin evidencia de emergencia real.');

    final u = db.usuarios['usr-2']!;
    expect(u.falsasAlarmas, 3);
    expect(u.bloqueadoHasta, ahoraPrueba.add(const Duration(days: 7)));
    final bandeja = await MemoriaAdminRepository(db).escucharEscaladas().first;
    expect(bandeja.any((a) => a.id == 'alt-302'), isFalse);
    vm2.dispose();
  });

  test('una alerta que ya no está escalada no se resuelve', () async {
    final vm304 = DetalleEscaladaViewModel(MemoriaAdminRepository(db), 'alt-304');
    await vm304.cargar();
    vm304.cambiarRevision(true);

    final ok = await vm304.resolver(Resolucion.resuelta, nota: 'Intento sobre alerta ya resuelta');

    expect(ok, isFalse);
    expect(vm304.mensaje, 'Esta alerta ya no está escalada');
    vm304.dispose();
  });

  test('la falla al cargar se vuelve ErrorVista', () async {
    final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
    final otro = DetalleEscaladaViewModel(espia, 'alt-1');

    await otro.cargar();

    expect(otro.estado, isA<ErrorVista<Alerta>>());
    otro.dispose();
  });

  test('la falla al resolver se muestra como mensaje', () async {
    final espia = AdminEspia(
      guardia: guardiaPrueba(),
      historial: [alertaPrueba(estado: EstadoAlerta.escalada)],
      fallaResolver: const ServicioNoDisponibleError(),
    );
    final otro = DetalleEscaladaViewModel(espia, 'alt-1');
    await otro.cargar();
    otro.cambiarRevision(true);

    final ok = await otro.resolver(Resolucion.resuelta, nota: 'Se revisó la alerta');

    expect(ok, isFalse);
    expect(otro.mensaje, 'No pudimos conectar con el servidor. Intenta de nuevo.');
    otro.dispose();
  });
}
