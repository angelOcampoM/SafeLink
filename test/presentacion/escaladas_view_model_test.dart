// A-04 Bandeja de escaladas — ViewModel con la semilla en memoria para el
// orden de la bandeja y con la espía para el error del stream.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/escaladas_view_model.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';

import 'espias.dart';

void main() {
  test('la bandeja lista solo las escaladas, las más antiguas primero', () async {
    final db = MemoriaBaseDatos(reloj: () => ahoraPrueba, latencia: Duration.zero);
    final vm = EscaladasViewModel(MemoriaAdminRepository(db), reloj: () => ahoraPrueba);

    vm.iniciar();
    await Future<void>.delayed(Duration.zero);

    final lista = vm.estado.datos!;
    // Se afirma la propiedad, no una lista fija de ids: la semilla crece y la
    // bandeja debe seguir cumpliendo lo mismo (solo escaladas, más antiguas primero).
    expect(lista, isNotEmpty);
    expect(lista.every((a) => a.estado == EstadoAlerta.escalada), isTrue);
    expect(
      lista.map((a) => a.disparadaEn).toList(),
      orderedEquals([...lista.map((a) => a.disparadaEn)]..sort()),
      reason: 'las más antiguas primero',
    );
    expect(lista.map((a) => a.id), containsAll(['alt-301', 'alt-302', 'alt-303']));

    vm.dispose();
    db.dispose();
  });

  test('la falla del stream se vuelve ErrorVista', () async {
    final espia = AdminEspia(guardia: guardiaPrueba(), falla: const ServicioNoDisponibleError());
    final vm = EscaladasViewModel(espia, reloj: () => ahoraPrueba);

    vm.iniciar();
    await Future<void>.delayed(Duration.zero);

    expect(vm.estado, isA<ErrorVista<List<Alerta>>>());
    vm.dispose();
  });
}
