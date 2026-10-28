// G-02 Recepción (banner "Alerta entrante") · G-03 Listado — con la base en memoria.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/guardia/listado_alertas_view_model.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

void main() {
  test('cuando llega una alerta nueva aparece como "entrante" y el listado se actualiza solo', () async {
    final db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero, azar: Random(3));
    db.usuarioActualId = 'grd-1';
    final vm = ListadoAlertasViewModel(MemoriaAlertaGuardiaRepository(db), SesionViewModel(MemoriaAuthRepository(db)), reloj: () => ahoraPrueba);

    await vm.iniciar();
    await Future<void>.delayed(Duration.zero);
    final antes = vm.estado.datos!.length;
    expect(vm.entrante, isNull, reason: 'lo que ya estaba al abrir no es "entrante"');

    final nueva = db.simularNuevaAlerta()!;
    await Future<void>.delayed(Duration.zero);

    expect(vm.estado, isA<Listo>());
    expect(vm.estado.datos!.length, antes + 1);
    expect(vm.entrante?.alerta.id, nueva.id);

    vm.descartarEntrante();
    expect(vm.entrante, isNull);
    vm.dispose();
    db.dispose();
  });

  test('un guardia fuera de turno no se suscribe y ve el motivo', () async {
    final db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
    db.usuarioActualId = 'grd-7';
    final vm = ListadoAlertasViewModel(MemoriaAlertaGuardiaRepository(db), SesionViewModel(MemoriaAuthRepository(db)), reloj: () => ahoraPrueba);

    await vm.iniciar();

    expect(vm.motivoNoDisponible, contains('Tu turno es de'));
    expect(vm.estado, isA<Cargando>());
    vm.dispose();
    db.dispose();
  });
}
