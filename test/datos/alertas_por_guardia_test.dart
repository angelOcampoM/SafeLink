// G-02 · G-03 Cada guardia tiene su propio mundo de alertas: zonas sin traslape, disponibles
// propias con variedad para probar los filtros, y simulaciones que respetan ambas cosas.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/datos_semilla.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';

final mediodia = DateTime(2026, 10, 26, 13, 0);
final noche = DateTime(2026, 10, 26, 23, 30);

bool cubre(PerfilGuardia p, PuntoGeo punto) => ReglaGeocerca.dentroDeCobertura(p.centroCobertura!, p.radioCoberturaMetros!, punto);

/// Lo que ve [guardiaId] en su listado (la base en memoria solo sabe del usuario en sesión).
Future<List<AlertaPriorizada>> disponiblesDe(MemoriaBaseDatos db, String guardiaId) {
  db.usuarioActualId = guardiaId;
  return MemoriaAlertaGuardiaRepository(db).escucharAlertasDisponibles().first;
}

void main() {
  final semilla = DatosSemilla(mediodia).construir();
  final conZona = semilla.perfiles.where((p) => p.tieneCobertura).toList();

  test('las zonas no se traslapan: al menos 500 m entre bordes', () {
    expect(conZona.map((p) => p.usuarioId), containsAll(['grd-1', 'grd-2', 'grd-3', 'grd-4', 'grd-5', 'grd-6', 'grd-7']));
    expect(semilla.perfiles.firstWhere((p) => p.usuarioId == 'grd-8').tieneCobertura, isFalse);
    for (var i = 0; i < conZona.length; i++) {
      for (var j = i + 1; j < conZona.length; j++) {
        final a = conZona[i], b = conZona[j];
        final entreBordes = ReglaGeocerca.distanciaMetros(a.centroCobertura!, b.centroCobertura!) - a.radioCoberturaMetros! - b.radioCoberturaMetros!;
        expect(entreBordes, greaterThanOrEqualTo(500), reason: '${a.usuarioId} y ${b.usuarioId}');
      }
    }
  });

  test('grd-1 conserva centro y radio', () {
    final p = semilla.perfiles.firstWhere((p) => p.usuarioId == 'grd-1');
    expect(p.centroCobertura, DatosSemilla.centroEmilianoZapata);
    expect(p.radioCoberturaMetros, 4000);
  });

  test('cada alerta sembrada "buscando" cae en la zona de exactamente un guardia', () {
    final buscando = semilla.alertas.where((a) => a.estado == EstadoAlerta.buscando).toList();
    expect(buscando, isNotEmpty);
    for (final a in buscando) {
      final duenos = [for (final p in conZona) if (cubre(p, a.ubicacion!)) p.usuarioId];
      expect(duenos, hasLength(1), reason: a.id);
    }
    String dueno(String id) => conZona.firstWhere((p) => cubre(p, semilla.alertas.firstWhere((a) => a.id == id).ubicacion!)).usuarioId;
    for (final id in ['alt-101', 'alt-102', 'alt-103', 'alt-104']) {
      expect(dueno(id), 'grd-1');
    }
    expect(dueno('alt-105'), 'grd-2');
  });

  test('las alertas con guardia caen en su zona y las que no tienen guardia en alguna zona', () {
    for (final a in semilla.alertas.where((a) => a.ubicacion != null)) {
      if (a.guardiaId != null) {
        expect(cubre(conZona.firstWhere((p) => p.usuarioId == a.guardiaId), a.ubicacion!), isTrue, reason: a.id);
      } else {
        expect(conZona.any((p) => cubre(p, a.ubicacion!)), isTrue, reason: a.id);
      }
    }
  });

  test('nadie tiene dos alertas activas a la vez y ningún bloqueado tiene una', () {
    final activas = semilla.alertas.where((a) => a.estado.activa).toList();
    final usuarios = activas.map((a) => a.usuarioId).toList();
    expect(usuarios.toSet().length, usuarios.length);
    final bloqueados = {for (final u in semilla.usuarios) if (u.bloqueadoEn(mediodia)) u.id};
    expect(usuarios.where(bloqueados.contains), isEmpty);
    expect(usuarios, isNot(contains('usr-1')), reason: 'la cuenta demo del usuario empieza sin alerta activa');
  });

  group('cada guardia en turno tiene al menos 4 disponibles con variedad', () {
    Future<void> revisar(DateTime ahora, List<String> guardias) async {
      final db = MemoriaBaseDatos(reloj: () => ahora, latencia: Duration.zero);
      addTearDown(db.dispose);
      for (final id in guardias) {
        final lista = await disponiblesDe(db, id);
        final metodos = {for (final p in lista) p.alerta.metodo};
        final d = [for (final p in lista) p.distanciaMetros];
        expect(lista.length, greaterThanOrEqualTo(4), reason: id);
        expect(metodos, MetodoDisparo.values.toSet(), reason: '$id: un método de cada tipo');
        expect(lista.any((p) => p.alerta.esUrgente), isTrue, reason: '$id: al menos una urgente');
        expect(lista.any((p) => p.alerta.fotoUrl == null), isTrue, reason: '$id: al menos una sin foto');
        expect(d.where((m) => m <= 500), isNotEmpty, reason: '$id: ≤ 500 m');
        expect(d.where((m) => m > 500 && m <= 1000), isNotEmpty, reason: '$id: ≤ 1 km');
        expect(d.where((m) => m > 1000 && m <= 3000), isNotEmpty, reason: '$id: ≤ 3 km');
        expect(d.where((m) => m > 3000), isNotEmpty, reason: '$id: más de 3 km');
      }
    }

    test('de día (grd-1, grd-2, grd-3, grd-6)', () => revisar(mediodia, ['grd-1', 'grd-2', 'grd-3', 'grd-6']));
    test('de noche también grd-4 (turno 22:00–06:00)', () => revisar(noche, ['grd-1', 'grd-4']));

    test('grd-1 conserva exactamente alt-101…104', () async {
      final db = MemoriaBaseDatos(reloj: () => mediodia, latencia: Duration.zero);
      addTearDown(db.dispose);
      expect({for (final p in await disponiblesDe(db, 'grd-1')) p.alerta.id}, {'alt-101', 'alt-102', 'alt-103', 'alt-104'});
    });
  });

  test('dos guardias nunca ven la misma alerta y aceptar una no cambia el listado de los demás', () async {
    final db = MemoriaBaseDatos(reloj: () => noche, latencia: Duration.zero);
    addTearDown(db.dispose);
    const guardias = ['grd-1', 'grd-2', 'grd-3', 'grd-4', 'grd-6'];
    final antes = {for (final g in guardias) g: {for (final p in await disponiblesDe(db, g)) p.alerta.id}};
    final todas = [for (final ids in antes.values) ...ids];
    expect(todas.toSet().length, todas.length, reason: 'ninguna alerta aparece a dos guardias');

    db.usuarioActualId = 'grd-1';
    await MemoriaAlertaGuardiaRepository(db).aceptarAlerta('alt-101');

    expect({for (final p in await disponiblesDe(db, 'grd-1')) p.alerta.id}, antes['grd-1']!.difference({'alt-101'}));
    for (final g in guardias.skip(1)) {
      expect({for (final p in await disponiblesDe(db, g)) p.alerta.id}, antes[g], reason: g);
    }
  });

  group('simulaciones', () {
    test('las alertas nuevas son de usuarios libres, no bloqueados, y solo en la zona del guardia en sesión', () {
      final db = MemoriaBaseDatos(reloj: () => mediodia, latencia: Duration.zero, azar: Random(11));
      addTearDown(db.dispose);
      db.usuarioActualId = 'grd-2';
      final grd2 = db.perfiles['grd-2']!;
      final otras = db.perfiles.values.where((p) => p.tieneCobertura && p.usuarioId != 'grd-2');
      var creadas = 0;
      for (var i = 0; i < 40; i++) {
        final libres = {
          for (final u in db.usuarios.values)
            if (u.rol == RolUsuario.usuarioProtegido && !db.tieneAlertaActiva(u.id) && !u.bloqueadoEn(mediodia)) u.id,
        };
        final a = db.simularNuevaAlerta();
        if (a == null) {
          expect(libres.difference({'usr-1'}), isEmpty, reason: 'solo deja de crear cuando no queda nadie libre');
          continue;
        }
        creadas++;
        expect(libres, contains(a.usuarioId));
        expect(a.usuarioId, isNot('usr-1'));
        expect(cubre(grd2, a.ubicacion!), isTrue);
        expect(otras.where((p) => cubre(p, a.ubicacion!)), isEmpty);
      }
      expect(creadas, greaterThan(0));
      final activas = db.alertas.where((a) => a.estado.activa).map((a) => a.usuarioId).toList();
      expect(activas.toSet().length, activas.length, reason: 'sigue sin haber dos alertas activas de un mismo usuario');
    });

    testWidgets('la respuesta simulada la da el guardia que cubre la zona', (tester) async {
      final db = MemoriaBaseDatos(reloj: () => mediodia, latencia: Duration.zero);
      db.usuarioActualId = 'usr-28';
      final a = await MemoriaAlertaUsuarioRepository(db).crearAlerta(
        metodo: MetodoDisparo.toque,
        disparadaEn: mediodia,
        ubicacion: DatosSemilla.aDistancia(DatosSemilla.centroCuernavaca, 800, 90),
      );
      await tester.pump(const Duration(seconds: 5));
      final aceptada = db.alertaPorId(a.id);
      expect(aceptada.estado, isNot(EstadoAlerta.buscando));
      expect(aceptada.guardiaId, 'grd-2');
      db.dispose();
    });

    testWidgets('si ningún guardia disponible cubre el punto, la alerta sigue buscando', (tester) async {
      final db = MemoriaBaseDatos(reloj: () => mediodia, latencia: Duration.zero);
      db.usuarioActualId = 'usr-29';
      // Cuautla es de grd-4, que a las 13:00 está fuera de turno.
      final a = await MemoriaAlertaUsuarioRepository(db).crearAlerta(
        metodo: MetodoDisparo.toque,
        disparadaEn: mediodia,
        ubicacion: DatosSemilla.aDistancia(DatosSemilla.centroCuautla, 600, 0),
      );
      await tester.pump(const Duration(seconds: 7));
      expect(db.alertaPorId(a.id).estado, EstadoAlerta.buscando);
      expect(db.alertaPorId(a.id).guardiaId, isNull);
      db.dispose();
    });

    test('la alerta del usuario demo cae en la zona de grd-1', () {
      final db = MemoriaBaseDatos(reloj: () => mediodia, latencia: Duration.zero);
      addTearDown(db.dispose);
      expect(db.guardiaQueCubre(DatosSemilla.ubicacionDispositivoUsuario, mediodia)?.usuario.id, 'grd-1');
    });
  });
}
