// A-06 Métricas generales · A-07 Métricas por guardia.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  final t = DateTime(2026, 10, 7, 21, 0);

  test('con cero alertas todo vale 0 (sin dividir entre cero)', () {
    final m = ReglaMetricas.generales([]);
    expect(m.totalAlertas, 0);
    expect(m.promedioAceptacionSeg, 0);
    expect(m.tasaSinRespuesta, 0);
    expect(m.alertasPorHora.length, 24);

    final g = ReglaMetricas.deGuardia('g1', []);
    expect(g.atendidas, 0);
    expect(g.promedioLlegadaSeg, 0);
  });

  test('promedios, tasas y conteo por hora', () {
    final alertas = [
      Alerta(id: '1', usuarioId: 'u', guardiaId: 'g1', estado: EstadoAlerta.cerrada, metodo: MetodoDisparo.toque, disparadaEn: t, aceptadaEn: t.add(const Duration(seconds: 60)), llegadaEn: t.add(const Duration(seconds: 360))),
      Alerta(id: '2', usuarioId: 'u', guardiaId: 'g1', estado: EstadoAlerta.cerrada, metodo: MetodoDisparo.toque, disparadaEn: t, aceptadaEn: t.add(const Duration(seconds: 120)), llegadaEn: t.add(const Duration(seconds: 720))),
      Alerta(id: '3', usuarioId: 'u', estado: EstadoAlerta.escalada, razonEscalamiento: RazonEscalamiento.sinRespuesta, metodo: MetodoDisparo.toque, disparadaEn: t),
    ];
    final m = ReglaMetricas.generales(alertas);
    expect(m.promedioAceptacionSeg, 90);
    expect(m.promedioLlegadaSeg, 450);
    expect(m.tasaSinRespuesta, closeTo(1 / 3, 0.001));
    expect(m.tasaCierreConfirmado, closeTo(2 / 3, 0.001));
    expect(m.alertasPorHora[21], 3);

    final g = ReglaMetricas.deGuardia('g1', alertas);
    expect(g.atendidas, 2);
    expect(g.escaladas, 0);
  });
}
