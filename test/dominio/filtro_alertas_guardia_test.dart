// G-03 Filtros del listado de alertas disponibles del guardia.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  final ahora = DateTime(2026, 10, 26, 13, 0);

  AlertaPriorizada p(String id, double metros, int minutosAtras, {MetodoDisparo m = MetodoDisparo.toque, bool sinFoto = false}) =>
      AlertaPriorizada(
        Alerta(
          id: id,
          usuarioId: 'u',
          estado: EstadoAlerta.buscando,
          metodo: m,
          disparadaEn: ahora.subtract(Duration(minutes: minutosAtras)),
          fotoUrl: sinFoto ? null : 'https://foto/$id',
          evidenciaIncompleta: sinFoto,
        ),
        metros,
        minutosAtras.toDouble(),
        0,
      );

  // Orden de prioridad tal como lo entrega ReglaPrioridad.
  final lista = [
    p('urgente', 2500, 1, m: MetodoDisparo.agitacion),
    p('toque-cerca', 300, 5),
    p('mantener', 900, 10, m: MetodoDisparo.mantener, sinFoto: true),
    p('toque-lejos', 1800, 2),
  ];
  List<String> ids(List<AlertaPriorizada> r) => [for (final x in r) x.alerta.id];

  test('sin filtros devuelve todo en el mismo orden (prioridad)', () {
    const f = FiltroAlertasDisponibles();
    expect(ids(f.aplicar(lista)), ['urgente', 'toque-cerca', 'mantener', 'toque-lejos']);
    expect(f.hayFiltros, isFalse);
    expect(f.filtraAlertas, isFalse);
  });

  test('por tipo de disparo', () {
    expect(ids(const FiltroAlertasDisponibles(metodo: MetodoDisparo.agitacion).aplicar(lista)), ['urgente']);
    expect(ids(const FiltroAlertasDisponibles(metodo: MetodoDisparo.toque).aplicar(lista)), ['toque-cerca', 'toque-lejos']);
    expect(ids(const FiltroAlertasDisponibles(metodo: MetodoDisparo.mantener).aplicar(lista)), ['mantener']);
  });

  test('por distancia máxima (incluye el límite)', () {
    expect(ids(const FiltroAlertasDisponibles(distanciaMaxMetros: 500).aplicar(lista)), ['toque-cerca']);
    expect(ids(const FiltroAlertasDisponibles(distanciaMaxMetros: 1000).aplicar(lista)), ['toque-cerca', 'mantener']);
    expect(const FiltroAlertasDisponibles(distanciaMaxMetros: 900).cumple(lista[2]), isTrue);
  });

  test('por evidencia', () {
    expect(ids(const FiltroAlertasDisponibles(evidencia: FiltroEvidencia.sinFoto).aplicar(lista)), ['mantener']);
    expect(ids(const FiltroAlertasDisponibles(evidencia: FiltroEvidencia.conFoto).aplicar(lista)), ['urgente', 'toque-cerca', 'toque-lejos']);
  });

  test('filtros combinados', () {
    const f = FiltroAlertasDisponibles(metodo: MetodoDisparo.toque, distanciaMaxMetros: 3000, evidencia: FiltroEvidencia.conFoto);
    expect(ids(f.aplicar(lista)), ['toque-cerca', 'toque-lejos']);
    expect(ids(const FiltroAlertasDisponibles(metodo: MetodoDisparo.agitacion, distanciaMaxMetros: 500).aplicar(lista)), isEmpty);
  });

  test('orden: más cercanas y más antiguas', () {
    expect(ids(const FiltroAlertasDisponibles(orden: OrdenAlertasDisponibles.cercanas).aplicar(lista)),
        ['toque-cerca', 'mantener', 'toque-lejos', 'urgente'],);
    expect(ids(const FiltroAlertasDisponibles(orden: OrdenAlertasDisponibles.antiguas).aplicar(lista)),
        ['mantener', 'toque-cerca', 'toque-lejos', 'urgente'],);
  });

  test('el orden cuenta como filtro activo pero no deja fuera alertas', () {
    const f = FiltroAlertasDisponibles(orden: OrdenAlertasDisponibles.cercanas);
    expect(f.hayFiltros, isTrue);
    expect(f.filtraAlertas, isFalse);
    expect(f.aplicar(lista), hasLength(4));
  });

  test('lista vacía', () {
    expect(const FiltroAlertasDisponibles(metodo: MetodoDisparo.toque, orden: OrdenAlertasDisponibles.antiguas).aplicar(const []), isEmpty);
  });

  test('no modifica la lista recibida', () {
    final copia = [...lista];
    const FiltroAlertasDisponibles(orden: OrdenAlertasDisponibles.cercanas).aplicar(lista);
    expect(ids(lista), ids(copia));
  });
}
