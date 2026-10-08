// U-01 Registro — validadores de formulario.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/core/utils/validators.dart';

void main() {
  test('correo', () {
    expect(Validators.email(''), isNotNull);
    expect(Validators.email('sin-arroba'), isNotNull);
    expect(Validators.email('fernanda@mail.com'), isNull);
  });

  test('teléfono de 10 dígitos', () {
    expect(Validators.phone('777123456'), 'Debe tener 10 dígitos');
    expect(Validators.phone('777123456a'), 'Debe tener 10 dígitos');
    expect(Validators.phone('7771234567'), isNull);
  });

  test('contraseña: mínimo 8 y un número', () {
    expect(Validators.password('corta1'), isNotNull);
    expect(Validators.password('sinnumeros'), isNotNull);
    expect(Validators.password('SafeLink1'), isNull);
  });

  test('confirmación de contraseña', () {
    final v = Validators.confirmPassword(() => 'SafeLink1');
    expect(v('otra'), isNotNull);
    expect(v('SafeLink1'), isNull);
  });
}
