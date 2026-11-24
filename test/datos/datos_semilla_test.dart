// Sección 9 — la semilla cubre lo que la demo necesita (todos los estados, roles y turnos).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/datos_semilla.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  final ahora = DateTime(2026, 10, 26, 13, 0);
  final s = DatosSemilla(ahora).construir();

  test('~8 usuarios protegidos y ~8 guardias (nocturno y dado de baja)', () {
    expect(s.usuarios.where((u) => u.rol == RolUsuario.usuarioProtegido).length, greaterThanOrEqualTo(8));
    final guardias = s.usuarios.where((u) => u.rol == RolUsuario.guardia).toList();
    expect(guardias.length, greaterThanOrEqualTo(8));
    expect(guardias.any((g) => !g.activo), isTrue);
    expect(s.perfiles.any((p) => p.inicioTurno == '22:00' && p.finTurno == '06:00'), isTrue);
  });

  test('el guardia de prueba está en turno a cualquier hora', () {
    for (final h in [0, 6, 13, 23]) {
      final t = DateTime(2026, 10, 26, h, 30);
      final p = DatosSemilla(t).construir().perfiles.firstWhere((p) => p.usuarioId == 'grd-1');
      expect(p.enTurnoA(t), isTrue, reason: 'a las $h:30');
    }
  });

  test('todos los estados y las dos razones de escalamiento, ~80 de historial en 30 días', () {
    expect({for (final a in s.alertas) a.estado}, EstadoAlerta.values.toSet());
    expect({for (final a in s.alertas) a.razonEscalamiento}.whereType<RazonEscalamiento>().toSet(), RazonEscalamiento.values.toSet());
    final historial = s.alertas.where((a) => a.id.startsWith('alt-h')).toList();
    expect(historial.length, greaterThanOrEqualTo(80));
    expect(historial.every((a) => ahora.difference(a.disparadaEn).inDays <= 30), isTrue);
  });

  test('es determinista para el mismo "ahora"', () {
    final otra = DatosSemilla(ahora).construir();
    expect(otra.alertas.map((a) => a.disparadaEn), s.alertas.map((a) => a.disparadaEn));
  });
}
