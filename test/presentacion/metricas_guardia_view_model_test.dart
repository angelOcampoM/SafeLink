// A-07 Métricas por guardia — ViewModel con la semilla en memoria (reloj fijo)
// para probar el filtro por rango, y con la espía para verificar lo que se le
// pide al repositorio (rango inclusivo y errores).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/metricas_guardia_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';

import 'espias.dart';

void main() {
  group('con la semilla en memoria', () {
    late MemoriaBaseDatos db;
    late MetricasGuardiaViewModel vm;

    setUp(() async {
      db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
      vm = MetricasGuardiaViewModel(MemoriaAdminRepository(db), 'grd-1', reloj: () => ahoraPrueba);
      await vm.iniciar();
    });

    tearDown(() {
      vm.dispose();
      db.dispose();
    });

    test('carga el perfil del guardia y sus últimas atendidas', () {
      expect(vm.nombreGuardia, 'Carlos Hernández López');
      expect(vm.guardia?.usuario.correo, 'guardia@safelink.mx');
      // La más reciente con llegada en la semilla es alt-302 (hace 48 min).
      expect(vm.ultimasAtendidas, hasLength(3));
      expect(vm.ultimasAtendidas.first.id, 'alt-302');
      expect(vm.ultimasAtendidas.every((a) => a.llegadaEn != null), isTrue);
    });

    test('carga las métricas del guardia', () {
      expect(vm.nombreGuardia, 'Carlos Hernández López');
      final m = vm.estado.datos!;
      // grd-1 atendió alt-302 y alt-304 (con llegada) además de su historial.
      expect(m.atendidas, greaterThan(0));
      // Las dos vienen de una escalada por sin confirmación.
      expect(m.escaladas, greaterThanOrEqualTo(2));
      expect(m.promedioAceptacionSeg, greaterThan(0));
      expect(m.promedioLlegadaSeg, greaterThan(0));
    });

    test('un periodo sin alertas deja el estado Vacio', () async {
      // Un rango futuro no tiene alertas: [mañana, pasado mañana).
      final manana = ahoraPrueba.add(const Duration(days: 1));
      await vm.cambiarRango(manana, manana.add(const Duration(days: 1)));
      expect(vm.estado, isA<Vacio<MetricasGuardia>>());
    });

    test('acotar el rango a un periodo sin alertas y limpiar lo devuelve a todas', () async {
      final todas = vm.estado.datos!.atendidas;

      final manana = ahoraPrueba.add(const Duration(days: 1));
      await vm.cambiarRango(manana, manana.add(const Duration(days: 1)));
      expect(vm.estado, isA<Vacio<MetricasGuardia>>()); // el rango acotado queda sin alertas

      await vm.limpiarRango();
      expect(vm.desde, isNull);
      expect(vm.hasta, isNull);
      expect(vm.estado.datos!.atendidas, todas);
    });
  });

  group('con la espía', () {
    test('pasa desde y hasta (+1 día) al repositorio', () async {
      final espia = AdminEspia(
        guardia: guardiaPrueba(),
        metricasGuardia: const MetricasGuardia(atendidas: 3, promedioAceptacionSeg: 30, promedioLlegadaSeg: 120, escaladas: 1),
      );
      final vm = MetricasGuardiaViewModel(espia, 'u-1', reloj: () => ahoraPrueba);

      await vm.cambiarRango(DateTime(2026, 10, 1), DateTime(2026, 10, 5));

      final llamada = espia.llamadasMetricasGuardia.single;
      expect(llamada.id, 'u-1');
      expect(llamada.desde, DateTime(2026, 10, 1));
      expect(llamada.hasta, DateTime(2026, 10, 6)); // inclusivo en el dominio
      expect(vm.estado.datos!.atendidas, 3);
      vm.dispose();
    });

    test('sin rango no envía fechas al repositorio', () async {
      final espia = AdminEspia(guardia: guardiaPrueba());
      final vm = MetricasGuardiaViewModel(espia, 'u-1', reloj: () => ahoraPrueba);

      await vm.iniciar();

      final llamada = espia.llamadasMetricasGuardia.single;
      expect(llamada.desde, isNull);
      expect(llamada.hasta, isNull);
      expect(vm.estado, isA<Vacio<MetricasGuardia>>()); // la espía devuelve vacías
      vm.dispose();
    });

    test('la falla del repositorio se vuelve ErrorVista', () async {
      final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
      final vm = MetricasGuardiaViewModel(espia, 'u-1', reloj: () => ahoraPrueba);

      await vm.iniciar();

      expect(vm.estado, isA<ErrorVista<MetricasGuardia>>());
      expect((vm.estado as ErrorVista<MetricasGuardia>).mensaje, 'No pudimos conectar con el servidor. Intenta de nuevo.');
      vm.dispose();
    });
  });
}
