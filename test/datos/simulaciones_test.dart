// G-02 Alertas nuevas cerca del guardia · A-04 Escalamiento por tiempo (simulaciones de la demo).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  var ahora = DateTime(2026, 10, 26, 13, 0);
  late MemoriaBaseDatos db;

  setUp(() {
    ahora = DateTime(2026, 10, 26, 13, 0);
    db = MemoriaBaseDatos(reloj: () => ahora, latencia: Duration.zero, azar: Random(1), config: const Configuracion(segundosEscalamientoDemo: 90));
  });
  tearDown(() => db.dispose());

  test('una alerta nueva aparece dentro de la cobertura del guardia en sesión', () {
    expect(db.simularNuevaAlerta(), isNull, reason: 'sin guardia en sesión no hay alertas nuevas');

    db.usuarioActualId = 'grd-1';
    final a = db.simularNuevaAlerta()!;
    final p = db.perfiles['grd-1']!;

    expect(a.estado, EstadoAlerta.buscando);
    expect(ReglaGeocerca.dentroDeCobertura(p.centroCobertura!, p.radioCoberturaMetros!, a.ubicacion!), isTrue);
    expect(a.usuarioId, isNot('usr-1'));
  });

  test('si nadie acepta en N segundos pasa a escalada y llega a la bandeja', () {
    db.revisarEscalamientos(); // primera observación de cada alerta
    ahora = ahora.add(const Duration(seconds: 89));
    db.revisarEscalamientos();
    expect(db.alertaPorId('alt-101').estado, EstadoAlerta.buscando);

    ahora = ahora.add(const Duration(seconds: 1));
    db.revisarEscalamientos();
    final a = db.alertaPorId('alt-101');
    expect(a.estado, EstadoAlerta.escalada);
    expect(a.razonEscalamiento, RazonEscalamiento.sinRespuesta);
    // El guardia que llegó y no recibió confirmación también escala.
    expect(db.alertaPorId('alt-203').razonEscalamiento, RazonEscalamiento.sinConfirmacion);
    // Las que están en atención no.
    expect(db.alertaPorId('alt-202').estado, EstadoAlerta.enAtencion);
  });
}
