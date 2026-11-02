// U-03 Toque con cuenta regresiva · U-04 Mantener con zona de descarte · U-05 Agitación
// El intervalo de la cuenta se inyecta (10 ms) para no esperar segundos reales.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';
import 'package:safelink/presentacion/usuario/inicio_view_model.dart';

import 'espias.dart';

void main() {
  const tick = Duration(milliseconds: 10);
  late AlertaUsuarioEspia alertas;

  InicioViewModel crear({Usuario? usuario, Duration intervalo = tick}) {
    alertas = AlertaUsuarioEspia();
    return InicioViewModel(
      alertas,
      SesionViewModel(AuthEspia(usuarioActual: usuario ?? usuarioPrueba()), MemoriaSesionGuardada(), reloj: () => ahoraPrueba),
      config: const Configuracion(segundosCuentaRegresiva: 3),
      ubicacionDispositivo: () => puntoAlerta,
      reloj: () => ahoraPrueba,
      intervaloCuenta: intervalo,
    );
  }

  Future<void> esperarTicks(int n) => Future<void>.delayed(tick * n + const Duration(milliseconds: 20));

  test('la cuenta regresiva se cancela y no crea la alerta', () async {
    // Intervalo largo: cancelamos a media cuenta sin depender de la precisión del timer.
    const lento = Duration(milliseconds: 200);
    final vm = crear(intervalo: lento);

    vm.tocar();
    expect(vm.cuentaRegresiva, 3);
    await Future<void>.delayed(lento * 1.5);
    expect(vm.cuentaRegresiva, 2);
    vm.cancelarCuenta();
    await Future<void>.delayed(lento * 4);

    expect(vm.cuentaRegresiva, isNull);
    expect(alertas.creadas, isEmpty);
    expect(vm.irAMiAlerta, isFalse);
    vm.dispose();
  });

  test('si no se cancela, al llegar a 0 crea la alerta por toque', () async {
    final vm = crear();

    vm.tocar();
    await esperarTicks(5);

    expect(alertas.creadas, [MetodoDisparo.toque]);
    expect(vm.irAMiAlerta, isTrue);
    vm.dispose();
  });

  test('soltar en la zona de descarte no crea la alerta', () async {
    final vm = crear();

    vm.empezarMantener();
    vm.moverMantener(sobreDescarte: true);
    vm.soltarMantener();
    await esperarTicks(1);

    expect(alertas.creadas, isEmpty);
    expect(vm.mensaje, 'Alerta descartada');
    expect(vm.manteniendo, isFalse);
  });

  test('soltar fuera de la zona de descarte crea la alerta por mantener', () async {
    final vm = crear();

    vm.empezarMantener();
    vm.moverMantener(sobreDescarte: true);
    vm.moverMantener(sobreDescarte: false);
    vm.soltarMantener();
    await esperarTicks(1);

    expect(alertas.creadas, [MetodoDisparo.mantener]);
  });

  test('la agitación envía al instante solo si está activa', () async {
    final inactiva = crear();
    inactiva.agitar();
    await esperarTicks(1);
    expect(alertas.creadas, isEmpty);

    final activa = crear(usuario: usuarioPrueba().copyWith(agitacionActiva: true));
    activa.agitar();
    await esperarTicks(1);
    expect(alertas.creadas, [MetodoDisparo.agitacion]);
  });

  test('un usuario bloqueado no puede enviar (regla del dominio)', () async {
    final vm = crear(usuario: usuarioPrueba(bloqueadoHasta: ahoraPrueba.add(const Duration(days: 1))));

    vm.empezarMantener();
    vm.soltarMantener();
    await esperarTicks(1);

    expect(alertas.creadas, isEmpty);
    expect(vm.mensaje, 'Tu cuenta está bloqueada temporalmente');
  });
}
