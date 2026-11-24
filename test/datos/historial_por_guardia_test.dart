// G-03 Historial simulado por guardia: fechas repartidas por cubeta (hoy, ayer, 2–7, 8–30 y
// más de 30 días), resultados y métodos variados, tiempos coherentes y nada en el futuro.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/datos_semilla.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';

enum Cubeta { hoy, ayer, d2a7, d8a30, mas30 }

Cubeta cubeta(DateTime t, DateTime ahora) {
  final dias = DateTime.utc(ahora.year, ahora.month, ahora.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  return switch (dias) {
    0 => Cubeta.hoy,
    1 => Cubeta.ayer,
    <= 7 => Cubeta.d2a7,
    <= 30 => Cubeta.d8a30,
    _ => Cubeta.mas30,
  };
}

Future<List<Alerta>> historialDe(MemoriaBaseDatos db, String guardiaId) {
  db.usuarioActualId = guardiaId;
  return MemoriaAlertaGuardiaRepository(db).obtenerMiHistorial();
}

void main() {
  const conHistorial = ['grd-1', 'grd-2', 'grd-3', 'grd-4', 'grd-6', 'grd-7'];

  final relojes = {
    'media tarde': DateTime(2026, 10, 26, 16, 45),
    'de madrugada': DateTime(2026, 10, 27, 1, 10),
    'recién pasada la medianoche': DateTime(2026, 10, 27, 0, 20),
  };

  for (final MapEntry(key: nombre, value: ahora) in relojes.entries) {
    group('con el reloj $nombre ($ahora)', () {
      late MemoriaBaseDatos db;
      setUp(() => db = MemoriaBaseDatos(reloj: () => ahora, latencia: Duration.zero));
      tearDown(() => db.dispose());

      final cabeHoy = ahora.difference(DateTime(ahora.year, ahora.month, ahora.day)) >= const Duration(minutes: 30);

      test('mínimos por cubeta de fecha para cada guardia con historial', () async {
        for (final g in conHistorial) {
          final h = await historialDe(db, g);
          final porCubeta = {for (final c in Cubeta.values) c: h.where((a) => cubeta(a.disparadaEn, ahora) == c).length};
          if (cabeHoy) {
            expect(porCubeta[Cubeta.hoy], greaterThanOrEqualTo(2), reason: '$g hoy');
            expect(porCubeta[Cubeta.ayer], greaterThanOrEqualTo(2), reason: '$g ayer');
          } else {
            // Las de hoy no caben y pasan a ayer.
            expect(porCubeta[Cubeta.ayer], greaterThanOrEqualTo(4), reason: '$g ayer');
          }
          expect(porCubeta[Cubeta.d2a7], greaterThanOrEqualTo(3), reason: '$g 2–7 días');
          expect(porCubeta[Cubeta.d8a30], greaterThanOrEqualTo(3), reason: '$g 8–30 días');
          expect(porCubeta[Cubeta.mas30], greaterThanOrEqualTo(2), reason: '$g más de 30 días');
          expect(h.every((a) => ahora.difference(a.disparadaEn).inDays <= 120), isTrue, reason: '$g dentro de 120 días');
        }
      });

      test('resultados, métodos y evidencia variados para cada guardia', () async {
        for (final g in conHistorial) {
          final h = await historialDe(db, g);
          final cerradas = h.where((a) => a.estado == EstadoAlerta.cerrada).length;
          expect(cerradas, greaterThan(h.length / 2), reason: '$g: la mayoría cerradas');
          expect(
            h.where((a) => a.estado == EstadoAlerta.escalada && a.guardiaId == g && a.razonEscalamiento == RazonEscalamiento.sinConfirmacion),
            isNotEmpty,
            reason: '$g: una escalada sin confirmación',
          );
          expect(h.where((a) => a.estado == EstadoAlerta.resueltaPorAdmin && a.resolucion != null), isNotEmpty, reason: '$g: una resuelta por admin');
          expect({for (final a in h) a.metodo}, MetodoDisparo.values.toSet(), reason: '$g: los tres métodos');
          expect(h.any((a) => a.fotoUrl == null), isTrue, reason: '$g: sin foto');
          expect(h.any((a) => a.fotoUrl != null), isTrue, reason: '$g: con foto');
        }
      });

      test('grd-5 solo trae antiguas y grd-8 no trae nada', () async {
        final grd5 = await historialDe(db, 'grd-5');
        expect(grd5, isNotEmpty);
        expect(grd5.every((a) => cubeta(a.disparadaEn, ahora) == Cubeta.mas30), isTrue);
        expect(grd5.every((a) => a.id.startsWith('alt-v')), isTrue);
        expect(await historialDe(db, 'grd-8'), isEmpty);
      });

      test('tiempos en orden y nada en el futuro', () {
        for (final a in db.alertas) {
          final tiempos = [a.disparadaEn, a.aceptadaEn, a.llegadaEn, a.cerradaEn].whereType<DateTime>().toList();
          for (var i = 1; i < tiempos.length; i++) {
            expect(tiempos[i - 1].isBefore(tiempos[i]), isTrue, reason: '${a.id}: $tiempos');
          }
          expect(tiempos.last.isAfter(ahora), isFalse, reason: '${a.id} en el futuro');
          if (a.llegadaEn != null) expect(a.aceptadaEn, isNotNull, reason: a.id);
          if (a.aceptadaEn != null) expect(a.guardiaId, isNotNull, reason: a.id);
        }
      });

      test('ids: alt-h para ≤ 30 días (≥ 80) y alt-v para las más antiguas', () {
        final h = db.alertas.where((a) => a.id.startsWith('alt-h')).toList();
        expect(h.length, greaterThanOrEqualTo(80));
        expect(h.every((a) => ahora.difference(a.disparadaEn).inDays <= 30), isTrue);
        final v = db.alertas.where((a) => a.id.startsWith('alt-v')).toList();
        expect(v, isNotEmpty);
        expect(v.every((a) => ahora.difference(a.disparadaEn).inDays > 30), isTrue);
      });
    });
  }

  test('las "sin respuesta" no tienen guardia: no llegan al historial de nadie, pero sí al del admin', () async {
    final ahora = relojes['media tarde']!;
    final db = MemoriaBaseDatos(reloj: () => ahora, latencia: Duration.zero);
    addTearDown(db.dispose);
    final sinRespuesta = db.alertas.where((a) => a.razonEscalamiento == RazonEscalamiento.sinRespuesta).toList();
    expect(sinRespuesta.where((a) => a.id.startsWith('alt-h')), isNotEmpty);
    expect(sinRespuesta.every((a) => a.guardiaId == null), isTrue);
    final ids = {for (final a in sinRespuesta) a.id};
    for (final g in [...conHistorial, 'grd-5', 'grd-8']) {
      expect((await historialDe(db, g)).where((a) => ids.contains(a.id)), isEmpty, reason: g);
    }

    db.usuarioActualId = 'adm-1';
    final admin = MemoriaAdminRepository(db);
    final todo = await admin.obtenerHistorial(const FiltroHistorial());
    expect(todo.map((a) => a.id), containsAll(ids));
    expect(todo.where((a) => a.id.startsWith('alt-v')), isNotEmpty, reason: 'el admin ve también las antiguas');
    expect(ReglaMetricas.generales(todo).tasaSinRespuesta, greaterThan(0));
  });

  test('con grd-1, cada filtro (fecha, resultado y método) da un resultado distinto', () async {
    final ahora = relojes['media tarde']!;
    final db = MemoriaBaseDatos(reloj: () => ahora, latencia: Duration.zero);
    addTearDown(db.dispose);
    final h = await historialDe(db, 'grd-1');
    Set<String> ids(FiltroMiHistorial f) => {for (final a in f.aplicar(h)) a.id};
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final porFecha = [
      ids(FiltroMiHistorial(desde: hoy)),
      ids(FiltroMiHistorial(desde: hoy.subtract(const Duration(days: 30)), hasta: hoy)),
      ids(FiltroMiHistorial(desde: hoy.subtract(const Duration(days: 365)), hasta: hoy.subtract(const Duration(days: 31)))),
    ];
    final porResultado = [for (final e in FiltroMiHistorial.estadosPresentes(h)) ids(FiltroMiHistorial(estado: e))];
    final porMetodo = [for (final m in MetodoDisparo.values) ids(FiltroMiHistorial(metodo: m))];

    expect(FiltroMiHistorial.estadosPresentes(h), [EstadoAlerta.cerrada, EstadoAlerta.escalada, EstadoAlerta.resueltaPorAdmin]);
    for (final grupo in [porFecha, porResultado, porMetodo]) {
      for (final s in grupo) {
        expect(s, isNotEmpty);
        expect(s.length, lessThan(h.length));
      }
      for (var i = 0; i < grupo.length; i++) {
        for (var j = i + 1; j < grupo.length; j++) {
          expect(grupo[i].intersection(grupo[j]), isEmpty, reason: 'cada opción deja ver alertas distintas');
        }
      }
    }
  });

  test('es determinista y el historial vive dentro de la zona de cada guardia', () {
    final ahora = relojes['media tarde']!;
    final a = DatosSemilla(ahora).construir();
    final b = DatosSemilla(ahora).construir();
    expect(a.alertas.map((x) => (x.id, x.disparadaEn, x.usuarioId)), b.alertas.map((x) => (x.id, x.disparadaEn, x.usuarioId)));
    final zonas = {for (final p in a.perfiles) p.usuarioId: p};
    for (final x in a.alertas.where((x) => x.guardiaId != null)) {
      final p = zonas[x.guardiaId]!;
      expect(ReglaGeocerca.dentroDeCobertura(p.centroCobertura!, p.radioCoberturaMetros!, x.ubicacion!), isTrue, reason: x.id);
    }
  });
}
