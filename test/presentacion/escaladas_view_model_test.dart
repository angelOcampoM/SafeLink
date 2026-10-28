// A-04 Escaladas · A-08 Falsas alarmas — ViewModel con el repositorio en memoria
// (sin red ni pantalla) para probar de verdad el contador y el bloqueo.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/escaladas_view_model.dart';

import 'espias.dart';

void main() {
  late MemoriaBaseDatos db;
  late EscaladasViewModel vm;

  setUp(() async {
    db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
    vm = EscaladasViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);
    vm.iniciar();
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    vm.dispose();
    db.dispose();
  });

  Alerta escaladaDe(String usuarioId) => vm.estado.datos!.firstWhere((a) => a.usuarioId == usuarioId);

  test('resolver como falsa alarma incrementa el contador sin bloquear bajo el límite', () async {
    // usr-6 llega con 1 falsa alarma; el límite es 3.
    final ok = await vm.resolver(escaladaDe('usr-6'), Resolucion.falsaAlarma);

    expect(ok, isTrue);
    expect(db.usuarios['usr-6']!.falsasAlarmas, 2);
    expect(db.usuarios['usr-6']!.bloqueadoEn(ahoraPrueba), isFalse);
  });

  test('al llegar al límite bloquea al usuario y la alerta sale de la bandeja', () async {
    // usr-2 llega con 2 falsas alarmas.
    final alerta = escaladaDe('usr-2');
    await vm.resolver(alerta, Resolucion.falsaAlarma);
    await Future<void>.delayed(Duration.zero);

    final u = db.usuarios['usr-2']!;
    expect(u.falsasAlarmas, 3);
    expect(u.bloqueadoEn(ahoraPrueba), isTrue);
    expect(u.bloqueadoHasta, ahoraPrueba.add(const Duration(days: 7)));
    expect(vm.estado.datos!.any((a) => a.id == alerta.id), isFalse);
    expect(vm.mensaje, 'Alerta marcada como "Falsa alarma"');
  });

  test('resolver como "Resuelta" no toca el contador', () async {
    await vm.resolver(escaladaDe('usr-2'), Resolucion.resuelta);
    expect(db.usuarios['usr-2']!.falsasAlarmas, 2);
  });
}
