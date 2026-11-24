// CAPA: DATOS — el contrato de alertas del guardia
// G-02 Recepción · G-03 Listado · G-04 Detalle · G-05 Aceptación · G-06 Ruta
// G-07 Llegada · Historial de atendidas y métricas personales
// Habla en lenguaje del dominio. No sabe si hay push, sockets o una lista.

import '../dominio/alerta.dart';
import '../dominio/guardia.dart';
import '../dominio/metricas.dart';
import '../dominio/punto_geo.dart';
import '../dominio/regla_prioridad.dart';

abstract interface class AlertaGuardiaRepository {
  /// Perfil del guardia en sesión (turno, radio, última ubicación).
  Future<Guardia> obtenerMiPerfil();

  /// Alertas disponibles en mi zona, ya ordenadas (sección 6.3). Se vuelve a
  /// emitir cuando llega una nueva o alguien toma una.
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles();

  Future<Alerta> obtenerAlerta(String alertaId);

  /// Seguimiento de una alerta (estado + ubicación del usuario).
  Stream<Alerta> escucharAlerta(String alertaId);

  /// Lanza `AlertaTomadaError`.
  Future<Alerta> aceptarAlerta(String alertaId);

  /// G-02: la oculta de mi listado (los demás guardias la siguen viendo).
  Future<void> ignorarAlerta(String alertaId);

  Future<void> actualizarMiUbicacion(PuntoGeo ubicacion);

  /// Lanza `FueraDeGeocercaError`.
  Future<Alerta> marcarLlegada(String alertaId);

  /// Alertas que atendí, las más recientes primero.
  Future<List<Alerta>> obtenerMiHistorial();

  Future<MetricasGuardia> obtenerMisMetricas();
}
