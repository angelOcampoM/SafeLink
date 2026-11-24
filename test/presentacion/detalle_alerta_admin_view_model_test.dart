// A-05 Detalle de alerta del admin — ViewModel con la semilla en memoria para
// encontrar la alerta por id y con la espía para el estado de error.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/detalle_alerta_admin_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';

import 'espias.dart';

void main() {
  group('con la semilla en memoria', () {
    late MemoriaBaseDatos db;

    setUp(() {
      db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
    });

    tearDown(() => db.dispose());

    test('encuentra la alerta del historial por id', () async {
      final vm = DetalleAlertaAdminViewModel(MemoriaAdminRepository(db), 'alt-302', reloj: () => ahoraPrueba);

      await vm.cargar();

      final alerta = vm.estado.datos;
      expect(alerta, isNotNull);
      expect(alerta!.id, 'alt-302');
      expect(alerta.usuarioId, isNotEmpty);
      expect(vm.ahora, ahoraPrueba);
      vm.dispose();
    });

    test('un id inexistente deja el estado en Vacio', () async {
      final vm = DetalleAlertaAdminViewModel(MemoriaAdminRepository(db), 'alt-inexistente', reloj: () => ahoraPrueba);

      await vm.cargar();

      expect(vm.estado, isA<Vacio<Alerta>>());
      vm.dispose();
    });
  });

  test('la falla del repositorio se vuelve ErrorVista', () async {
    final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
    final vm = DetalleAlertaAdminViewModel(espia, 'alt-302', reloj: () => ahoraPrueba);

    await vm.cargar();

    expect(vm.estado, isA<ErrorVista<Alerta>>());
    vm.dispose();
  });
}
