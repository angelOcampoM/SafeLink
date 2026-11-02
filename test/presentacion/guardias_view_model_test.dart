// A-01 · A-02 · A-03 — listado, búsqueda, chip de turno y baja lógica.
// Con memoria para la semilla real; espía para el error del repositorio.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/guardias_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';

import 'espias.dart';

void main() {
  late MemoriaBaseDatos db;

  setUp(() {
    db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
  });

  tearDown(() => db.dispose());

  test('lista los guardias y busca por nombre', () async {
    final vm = GuardiasViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);
    await vm.cargar();
    expect(vm.estado.datos, isNotEmpty);

    await vm.buscar('Carlos');
    expect(vm.estado.datos!.map((g) => g.usuario.id), ['grd-1']);
    vm.dispose();
  });

  test('el chip dice si está en turno, fuera de turno o dado de baja', () async {
    final vm = GuardiasViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);
    await vm.cargar();
    Guardia porId(String id) => vm.estado.datos!.firstWhere((g) => g.usuario.id == id);

    expect(vm.estadoDe(porId('grd-1')).etiqueta, 'En turno');
    expect(vm.estadoDe(porId('grd-4')).etiqueta, 'Fuera de turno');
    expect(vm.estadoDe(porId('grd-5')).etiqueta, 'Dado de baja');
    vm.dispose();
  });

  test('dar de baja lo desactiva, avisa y refresca el listado', () async {
    final vm = GuardiasViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);
    await vm.cargar();
    final g = vm.estado.datos!.firstWhere((g) => g.usuario.id == 'grd-1');

    final ok = await vm.darDeBaja(g);

    expect(ok, isTrue);
    expect(vm.mensaje, 'Carlos Hernández López quedó dado de baja');
    expect(db.usuarios['grd-1']!.activo, isFalse);
    expect(vm.estado.datos!.firstWhere((g) => g.usuario.id == 'grd-1').usuario.activo, isFalse);
    vm.consumirMensaje();
    expect(vm.mensaje, isNull);
    vm.dispose();
  });

  test('seleccionar carga las métricas del guardia', () async {
    final vm = GuardiasViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);
    await vm.cargar();

    await vm.seleccionar(vm.estado.datos!.firstWhere((g) => g.usuario.id == 'grd-1'));

    expect(vm.metricasSeleccion.datos, isNotNull);
    vm.dispose();
  });

  test('la falla del repositorio se vuelve ErrorVista', () async {
    final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
    final vm = GuardiasViewModel(espia, reloj: () => ahoraPrueba);

    await vm.cargar();

    expect(vm.estado, isA<ErrorVista<List<Guardia>>>());
    vm.dispose();
  });
}
