// A-06 Métricas generales · A-08 Bloqueados — periodo, rango personalizado,
// distribución por zona y desbloqueo. Memoria para el cálculo real; espía para
// las llamadas al repositorio y sus errores.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/panel_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

void main() {
  test('la distribución por zona agrupa por el guardia que atendió', () async {
    final db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
    final vm = PanelViewModel(MemoriaAdminRepository(db), SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);

    await vm.cargar();

    final m = vm.metricas.datos!;
    expect(m.totalAlertas, greaterThan(0));
    expect(m.alertasPorZona.any((z) => z.zona == 'Emiliano Zapata'), isTrue);
    expect(m.alertasPorZona.any((z) => z.zona == 'Cuernavaca'), isTrue);
    expect(m.alertasPorZona.any((z) => z.zona == ReglaMetricas.sinZona), isTrue);
    expect(m.alertasPorZona.fold<int>(0, (s, z) => s + z.total), m.totalAlertas);
    vm.dispose();
    db.dispose();
  });

  test('el periodo por defecto son 30 días y cada cambio se pasa al repositorio', () async {
    final espia = AdminEspia(guardia: guardiaPrueba());
    final vm = PanelViewModel(espia, SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);

    await vm.cargar();
    expect(vm.periodo, PeriodoPanel.dias30);
    expect(espia.llamadasMetricas.last.desde, ahoraPrueba.subtract(const Duration(days: 30)));
    expect(espia.llamadasMetricas.last.hasta, ahoraPrueba);

    await vm.cambiarPeriodo(PeriodoPanel.dias7);
    expect(espia.llamadasMetricas.last.desde, ahoraPrueba.subtract(const Duration(days: 7)));

    await vm.cambiarPeriodo(PeriodoPanel.dias90);
    expect(espia.llamadasMetricas.last.desde, ahoraPrueba.subtract(const Duration(days: 90)));
    vm.dispose();
  });

  test('el rango personalizado fija desde/hasta y sale de los chips', () async {
    final espia = AdminEspia(guardia: guardiaPrueba());
    final vm = PanelViewModel(espia, SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);
    await vm.cargar();

    await vm.cambiarRango(DateTime(2026, 10, 1), DateTime(2026, 10, 15));

    expect(vm.periodo, isNull);
    expect(vm.desde, DateTime(2026, 10, 1));
    expect(vm.hasta, DateTime(2026, 10, 15, 23, 59, 59));
    expect(espia.llamadasMetricas.last.desde, DateTime(2026, 10, 1));
    expect(espia.llamadasMetricas.last.hasta, DateTime(2026, 10, 15, 23, 59, 59));

    await vm.limpiarRango();
    expect(vm.periodo, PeriodoPanel.dias30);
    expect(vm.desde, isNull);
    expect(vm.hasta, isNull);
    vm.dispose();
  });

  test('con cero alertas en el periodo queda Vacio', () async {
    final vm = PanelViewModel(AdminEspia(guardia: guardiaPrueba()), SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);

    await vm.cargar();

    expect(vm.metricas, isA<Vacio<MetricasGenerales>>());
    vm.dispose();
  });

  test('la falla al cargar métricas se vuelve ErrorVista', () async {
    final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
    final vm = PanelViewModel(espia, SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);

    await vm.cargar();

    expect(vm.metricas, isA<ErrorVista<MetricasGenerales>>());
    vm.dispose();
  });

  test('desbloquear retira el bloqueo y deja mensaje', () async {
    final espia = AdminEspia(guardia: guardiaPrueba());
    final vm = PanelViewModel(espia, SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);
    await vm.cargar();
    final u = usuarioPrueba(bloqueadoHasta: ahoraPrueba.add(const Duration(days: 1)));

    await vm.desbloquear(u);

    expect(espia.desbloqueados, ['u-1']);
    expect(vm.mensaje, 'Se retiró el bloqueo de Fernanda Morales Gil');
    vm.consumirMensaje();
    expect(vm.mensaje, isNull);
    vm.dispose();
  });
}
