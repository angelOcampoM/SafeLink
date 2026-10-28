// CAPA: DOMINIO — orden del listado del guardia
// G-03 Listado por cercanía y prioridad (sección 6.3, provisional)
// 1. Primero las de agitación (urgentes).
// 2. Después, menor `puntaje = distancia − minutosEspera × metrosPorMinuto`.
// No hace: no filtra por cobertura ni por estado; ordena lo que recibe.

import 'alerta.dart';
import 'punto_geo.dart';
import 'regla_geocerca.dart';

/// Alerta + datos calculados para el listado del guardia.
class AlertaPriorizada {
  const AlertaPriorizada(this.alerta, this.distanciaMetros, this.minutosEspera, this.puntaje);
  final Alerta alerta;
  final double distanciaMetros;
  final double minutosEspera;
  final double puntaje;
}

abstract final class ReglaPrioridad {
  static List<AlertaPriorizada> ordenar({
    required List<Alerta> alertas,
    required PuntoGeo ubicacionGuardia,
    required DateTime ahora,
    int metrosPorMinutoEspera = 100,
  }) {
    final priorizadas = alertas.where((a) => a.ubicacion != null).map((a) {
      final d = ReglaGeocerca.distanciaMetros(ubicacionGuardia, a.ubicacion!);
      final w = ahora.difference(a.disparadaEn).inSeconds / 60.0;
      return AlertaPriorizada(a, d, w, d - w * metrosPorMinutoEspera);
    }).toList();

    priorizadas.sort((x, y) {
      if (x.alerta.esUrgente != y.alerta.esUrgente) return x.alerta.esUrgente ? -1 : 1;
      return x.puntaje.compareTo(y.puntaje);
    });
    return priorizadas;
  }
}
