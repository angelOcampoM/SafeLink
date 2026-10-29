// CAPA: DOMINIO — filtros del listado de alertas disponibles del guardia
// G-03 Listado por cercanía y prioridad: filtros por tipo de disparo, distancia y evidencia, y orden.
// Todas las disponibles están "buscando guardia", por eso no se filtra por estado.
// Con orden "Prioridad" se respeta tal cual el orden de ReglaPrioridad (sección 6.3).
// No hace: no busca alertas ni calcula distancias; trabaja sobre lo que recibe.

import 'enums.dart';
import 'regla_prioridad.dart';

enum OrdenAlertasDisponibles {
  prioridad('Prioridad'),
  cercanas('Más cercanas'),
  antiguas('Más antiguas');

  const OrdenAlertasDisponibles(this.etiqueta);
  final String etiqueta;
}

enum FiltroEvidencia {
  todas('Todas'),
  conFoto('Con foto'),
  sinFoto('Sin foto');

  const FiltroEvidencia(this.etiqueta);
  final String etiqueta;
}

class FiltroAlertasDisponibles {
  const FiltroAlertasDisponibles({
    this.metodo,
    this.distanciaMaxMetros,
    this.evidencia = FiltroEvidencia.todas,
    this.orden = OrdenAlertasDisponibles.prioridad,
  });

  /// Opciones de distancia máxima que ofrece la interfaz.
  static const distancias = [500, 1000, 3000];

  final MetodoDisparo? metodo;
  final int? distanciaMaxMetros;
  final FiltroEvidencia evidencia;
  final OrdenAlertasDisponibles orden;

  /// Algo distinto de lo predeterminado (incluido el orden).
  bool get hayFiltros =>
      metodo != null || distanciaMaxMetros != null || evidencia != FiltroEvidencia.todas || orden != OrdenAlertasDisponibles.prioridad;

  /// Solo los criterios que pueden dejar fuera alertas (el orden no).
  bool get filtraAlertas => metodo != null || distanciaMaxMetros != null || evidencia != FiltroEvidencia.todas;

  bool cumple(AlertaPriorizada p) {
    final a = p.alerta;
    final sinFoto = a.fotoUrl == null || a.evidenciaIncompleta;
    return (metodo == null || a.metodo == metodo) &&
        (distanciaMaxMetros == null || p.distanciaMetros <= distanciaMaxMetros!) &&
        switch (evidencia) {
          FiltroEvidencia.todas => true,
          FiltroEvidencia.conFoto => !sinFoto,
          FiltroEvidencia.sinFoto => sinFoto,
        };
  }

  /// Filtra y ordena. Con [OrdenAlertasDisponibles.prioridad] conserva el orden recibido.
  List<AlertaPriorizada> aplicar(List<AlertaPriorizada> alertas) {
    final r = alertas.where(cumple).toList();
    switch (orden) {
      case OrdenAlertasDisponibles.prioridad:
        break;
      case OrdenAlertasDisponibles.cercanas:
        r.sort((x, y) => x.distanciaMetros.compareTo(y.distanciaMetros));
      case OrdenAlertasDisponibles.antiguas:
        r.sort((x, y) => x.alerta.disparadaEn.compareTo(y.alerta.disparadaEn));
    }
    return r;
  }
}
