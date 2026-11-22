// U-05 — el atajo se vuelve a enganchar en CADA arranque, no solo al tocar el interruptor.
//
// Esto lo encontró la primera prueba en un teléfono real: el servicio nativo seguía
// filtrando teclas, pero en Flutter nadie las escuchaba, así que el doble clic no creaba
// ninguna alerta y la app seguía mostrando el interruptor encendido. Un botón de pánico que
// se apaga solo y en silencio es el peor fallo posible de este módulo.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/servicio_disparo_rapido_simulado.dart';
import 'package:safelink/main.dart';

import 'espias.dart';

void main() {
  late ServicioDisparoRapidoSimulado servicio;

  /// Arma la app completa como lo hace `main()`, con un usuario que ya tenía el atajo
  /// encendido o apagado, y devuelve las dependencias ya construidas.
  Dependencias arrancar({required bool atajoEncendido}) {
    servicio = ServicioDisparoRapidoSimulado();
    return Dependencias(
      auth: AuthEspia(conDobleClicVolumen: atajoEncendido),
      alertasUsuario: AlertaUsuarioEspia(),
      alertasGuardia: AlertaGuardiaEspia(alerta: alertaPrueba(), guardia: guardiaPrueba()),
      admin: AdminEspia(guardia: guardiaPrueba()),
      servicioDisparoRapido: servicio,
    );
  }

  tearDown(() => servicio.dispose());

  test('al entrar alguien que lo tenía encendido, el servicio arranca solo', () async {
    final deps = arrancar(atajoEncendido: true);
    expect(deps.disparoRapido.activo, isFalse, reason: 'todavía no hay sesión');

    await deps.sesion.iniciarSesion('quien.sea@safelink.mx', 'SafeLink1');
    await Future<void>.delayed(Duration.zero);

    expect(
      deps.disparoRapido.activo,
      isTrue,
      reason: 'sin esto el nativo escucha pero Flutter no, y el doble clic no hace nada',
    );
  });

  test('si lo tenía apagado, no se enciende solo', () async {
    final deps = arrancar(atajoEncendido: false);
    await deps.sesion.iniciarSesion('quien.sea@safelink.mx', 'SafeLink1');
    await Future<void>.delayed(Duration.zero);

    expect(deps.disparoRapido.activo, isFalse);
  });

  test('al cerrar sesión el servicio se apaga: ya no es de nadie', () async {
    final deps = arrancar(atajoEncendido: true);
    await deps.sesion.iniciarSesion('quien.sea@safelink.mx', 'SafeLink1');
    await Future<void>.delayed(Duration.zero);
    expect(deps.disparoRapido.activo, isTrue);

    await deps.sesion.cerrarSesion();
    await Future<void>.delayed(Duration.zero);

    expect(deps.disparoRapido.activo, isFalse);
  });
}
