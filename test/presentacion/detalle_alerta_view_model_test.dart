// G-04 Detalle · G-05 Aceptación — ViewModel con repositorio espía.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/guardia/detalle_alerta_view_model.dart';

import 'espias.dart';

void main() {
  test('carga la alerta y calcula la distancia con el dominio', () async {
    final repo = AlertaGuardiaEspia(alerta: alertaPrueba(), guardia: guardiaPrueba(ubicacion: const PuntoGeo(18.8410, -99.1800)));
    final vm = DetalleAlertaViewModel(repo, 'alt-1', reloj: () => ahoraPrueba);

    await vm.cargar();

    expect(vm.estado, isA<Listo<DetalleAlerta>>());
    expect(vm.distancia, closeTo(111, 1));
    expect(vm.puedeAceptar, isTrue);
  });

  test('aceptar una alerta que otro guardia ya tomó muestra el error', () async {
    final repo = AlertaGuardiaEspia(alerta: alertaPrueba(), guardia: guardiaPrueba(), fallaAceptar: const AlertaTomadaError());
    final vm = DetalleAlertaViewModel(repo, 'alt-1');
    await vm.cargar();

    final ok = await vm.aceptar();

    expect(ok, isFalse);
    expect(vm.error, 'Otro guardia ya aceptó esta alerta');
    expect(vm.alertaTomada, isTrue);
    expect(vm.aceptando, isFalse);
  });

  test('si la alerta ya no busca guardia, ni siquiera llama al repositorio', () async {
    final repo = AlertaGuardiaEspia(alerta: alertaPrueba(estado: EstadoAlerta.enAtencion), guardia: guardiaPrueba());
    final vm = DetalleAlertaViewModel(repo, 'alt-1');
    await vm.cargar();

    expect(vm.puedeAceptar, isFalse);
    final ok = await vm.aceptar();

    expect(ok, isFalse);
    expect(vm.error, 'Otro guardia ya aceptó esta alerta');
    expect(repo.aceptadas, isEmpty);
  });

  test('aceptar con éxito', () async {
    final repo = AlertaGuardiaEspia(alerta: alertaPrueba(), guardia: guardiaPrueba());
    final vm = DetalleAlertaViewModel(repo, 'alt-1');
    await vm.cargar();

    expect(await vm.aceptar(), isTrue);
    expect(repo.aceptadas, ['alt-1']);
    expect(vm.error, isNull);
  });
}
