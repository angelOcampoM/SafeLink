// U-05 (unitaria) — "dos pulsaciones seguidas disparan la alerta; una sola no".
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/regla_doble_clic.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 20, 0, 0);
  ReglaDobleClic nueva() => ReglaDobleClic(ventana: const Duration(milliseconds: 600));

  test('una sola pulsación no es un doble clic', () {
    expect(nueva().registrar(t0), isFalse);
  });

  test('dos pulsaciones dentro de la ventana sí lo son', () {
    final r = nueva();
    expect(r.registrar(t0), isFalse);
    expect(r.registrar(t0.add(const Duration(milliseconds: 300))), isTrue);
  });

  test('en el límite exacto de la ventana todavía cuenta', () {
    final r = nueva();
    r.registrar(t0);
    expect(r.registrar(t0.add(const Duration(milliseconds: 600))), isTrue);
  });

  test('dos pulsaciones demasiado separadas no son un doble clic', () {
    final r = nueva();
    r.registrar(t0);
    expect(r.registrar(t0.add(const Duration(milliseconds: 601))), isFalse);
  });

  test('tres pulsaciones seguidas son un doble clic y una suelta', () {
    final r = nueva();
    expect(r.registrar(t0), isFalse);
    expect(r.registrar(t0.add(const Duration(milliseconds: 200))), isTrue);
    expect(r.registrar(t0.add(const Duration(milliseconds: 400))), isFalse);
  });

  test('cuatro pulsaciones seguidas son dos dobles clics', () {
    final r = nueva();
    final disparos = [0, 200, 400, 600].map((ms) => r.registrar(t0.add(Duration(milliseconds: ms)))).toList();
    expect(disparos, [false, true, false, true]);
  });

  test('reiniciar olvida la pulsación pendiente', () {
    final r = nueva();
    r.registrar(t0);
    r.reiniciar();
    expect(r.registrar(t0.add(const Duration(milliseconds: 100))), isFalse);
  });
}
