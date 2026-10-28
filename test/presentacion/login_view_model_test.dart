// U-02 Inicio de sesión — ViewModel sin pantalla y sin red.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/errores.dart';
import 'package:safelink/presentacion/auth/login_view_model.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

void main() {
  test('con credenciales vacías muestra errores y no llama al repositorio', () async {
    final auth = AuthEspia();
    final vm = LoginViewModel(SesionViewModel(auth));

    final ok = await vm.entrar('', '');

    expect(ok, isFalse);
    expect(vm.errorCorreo, 'Escribe tu correo');
    expect(vm.errorContrasena, 'Escribe tu contraseña');
    expect(auth.llamadasLogin, 0);
  });

  test('si el repositorio rechaza, muestra el mensaje del dominio', () async {
    final auth = AuthEspia(falla: const CredencialesInvalidasError());
    final sesion = SesionViewModel(auth);
    final vm = LoginViewModel(sesion);

    final ok = await vm.entrar('usuario@safelink.mx', 'incorrecta');

    expect(ok, isFalse);
    expect(vm.error, 'Correo o contraseña incorrectos');
    expect(vm.cargando, isFalse);
    expect(sesion.haySesion, isFalse);
  });

  test('con credenciales válidas abre la sesión y avisa al router', () async {
    final auth = AuthEspia();
    final sesion = SesionViewModel(auth);
    var avisos = 0;
    sesion.addListener(() => avisos++);
    final vm = LoginViewModel(sesion);

    final ok = await vm.entrar('usuario@safelink.mx', 'SafeLink1');

    expect(ok, isTrue);
    expect(vm.error, isNull);
    expect(sesion.haySesion, isTrue);
    expect(avisos, 1);
  });
}
