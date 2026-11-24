// G-07 Registro de llegada — "Llegué" solo dentro de la geocerca.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/guardia/navegacion_view_model.dart';

import 'espias.dart';

void main() {
  const config = Configuracion(radioGeocercaMetros: 50);
  const lejos = PuntoGeo(18.8500, -99.1800); // ~1.1 km
  const cerca = PuntoGeo(18.8403, -99.1800); // ~33 m

  Future<(NavegacionViewModel, AlertaGuardiaEspia)> crear(PuntoGeo ubicacion) async {
    final repo = AlertaGuardiaEspia(alerta: alertaPrueba(estado: EstadoAlerta.enAtencion), guardia: guardiaPrueba(ubicacion: ubicacion));
    final vm = NavegacionViewModel(repo, 'alt-1', config: config);
    await vm.iniciar();
    await Future<void>.delayed(Duration.zero); // primer evento del stream
    return (vm, repo);
  }

  test('"Llegué" deshabilitado fuera de la geocerca y no llama al repositorio', () async {
    final (vm, repo) = await crear(lejos);

    expect(vm.dentroDeGeocerca, isFalse);
    expect(vm.puedeMarcarLlegada, isFalse);
    expect(vm.metrosRestantes, greaterThan(1000));

    await vm.marcarLlegada();
    expect(repo.llegadas, isEmpty);
    expect(vm.mensaje, 'Aún no estás en el punto de la alerta');
    vm.dispose();
  });

  test('dentro de la geocerca se habilita y registra la llegada', () async {
    final (vm, repo) = await crear(cerca);

    expect(vm.puedeMarcarLlegada, isTrue);
    await vm.marcarLlegada();
    expect(repo.llegadas, ['alt-1']);
    vm.dispose();
  });

  test('simular acercamiento avanza la ubicación hacia la alerta', () async {
    final (vm, repo) = await crear(lejos);
    final antes = vm.distancia!;

    await vm.simularAcercamiento();

    expect(repo.ubicaciones, hasLength(1));
    expect(vm.distancia, closeTo(antes * 0.4, 5));
    vm.dispose();
  });
}
