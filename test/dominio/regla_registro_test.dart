// U-01 Registro · A-02 Edición de guardia — reglas de datos personales.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/regla_registro.dart';

void main() {
  test('nombre', () {
    expect(ReglaRegistro.nombre(''), 'Escribe tu nombre');
    expect(ReglaRegistro.nombre('Al'), isNotNull);
    expect(ReglaRegistro.nombre('Fernanda Morales'), isNull);
  });

  test('correo', () {
    expect(ReglaRegistro.correo(''), isNotNull);
    expect(ReglaRegistro.correo('sin-arroba'), isNotNull);
    expect(ReglaRegistro.correo('fernanda@mail.com'), isNull);
  });

  test('teléfono de 10 dígitos', () {
    expect(ReglaRegistro.telefono('777123456'), 'Debe tener 10 dígitos');
    expect(ReglaRegistro.telefono('777123456a'), 'Debe tener 10 dígitos');
    expect(ReglaRegistro.telefono('7771234567'), isNull);
  });

  test('contraseña: mínimo 8 y un número', () {
    expect(ReglaRegistro.contrasena('corta1'), isNotNull);
    expect(ReglaRegistro.contrasena('sinnumeros'), isNotNull);
    expect(ReglaRegistro.contrasena('SafeLink1'), isNull);
  });

  test('confirmación de contraseña', () {
    expect(ReglaRegistro.confirmarContrasena('SafeLink1', 'otra'), isNotNull);
    expect(ReglaRegistro.confirmarContrasena('SafeLink1', 'SafeLink1'), isNull);
  });
}
