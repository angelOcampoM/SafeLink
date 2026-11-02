// A-05 Historial con filtros — ViewModel con la semilla en memoria (reloj fijo)
// para probar los filtros combinables, y con la espía para el estado de error.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/historial_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';

import 'espias.dart';

void main() {
  group('con la semilla en memoria', () {
    late MemoriaBaseDatos db;
    late HistorialViewModel vm;

    setUp(() async {
      db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
      vm = HistorialViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);
      await vm.iniciar();
    });

    tearDown(() {
      vm.dispose();
      db.dispose();
    });

    test('inicia con guardias, usuarios protegidos y el historial completo', () {
      expect(vm.guardias, isNotEmpty);
      expect(vm.usuarios, isNotEmpty);
      expect(vm.usuarios.map((u) => u.rol), everyElement(RolUsuario.usuarioProtegido));
      expect(vm.estado.datos, isNotNull);
      expect(vm.estado.datos!, isNotEmpty);
    });

    test('el filtro de usuario deja solo sus alertas', () async {
      final completo = vm.estado.datos!.length;

      await vm.cambiarUsuario('usr-1');

      final lista = vm.estado.datos!;
      expect(lista, isNotEmpty);
      expect(lista.every((a) => a.usuarioId == 'usr-1'), isTrue);
      expect(lista.length, lessThan(completo));
      expect(vm.nombreUsuario, 'Fernanda Morales Gil');
      expect(vm.hayFiltros, isTrue);
    });

    test('los filtros de usuario y estado se combinan', () async {
      await vm.cambiarUsuario('usr-1');
      await vm.cambiarEstado(EstadoAlerta.cerrada);

      final lista = vm.estado.datos!;
      expect(lista.every((a) => a.usuarioId == 'usr-1' && a.estado == EstadoAlerta.cerrada), isTrue);
    });

    test('limpiarFiltros quita todos los filtros y devuelve el historial completo', () async {
      final completo = vm.estado.datos!.length;
      await vm.cambiarUsuario('usr-1');
      await vm.cambiarEstado(EstadoAlerta.cerrada);

      await vm.limpiarFiltros();

      expect(vm.usuarioId, isNull);
      expect(vm.estadoFiltro, isNull);
      expect(vm.hayFiltros, isFalse);
      expect(vm.estado.datos!.length, completo);
    });
  });

  group('con la espía', () {
    test('la falla del repositorio se vuelve ErrorVista', () async {
      final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
      final vm = HistorialViewModel(espia, reloj: () => ahoraPrueba);

      await vm.iniciar();

      expect(vm.estado, isA<ErrorVista<List<Alerta>>>());
      vm.dispose();
    });
  });
}
