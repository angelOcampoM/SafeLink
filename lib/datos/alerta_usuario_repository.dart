// CAPA: DATOS — el contrato de alertas del usuario protegido
// U-03 Toque · U-04 Mantener · U-06 Evidencia · U-07 Ubicación · U-08 ETA
// U-09 Confirmación · Historial de mis alertas
// Habla en lenguaje del dominio. No sabe si hay WebSocket, FCM o una lista.

import '../dominio/alerta.dart';
import '../dominio/enums.dart';
import '../dominio/punto_geo.dart';

abstract interface class AlertaUsuarioRepository {
  /// Si [ubicacion] es null queda en `pendienteUbicacion`.
  /// Si [rutaFoto] es null se marca `evidenciaIncompleta`.
  /// Lanza `UsuarioBloqueadoError`.
  Future<Alerta> crearAlerta({
    required MetodoDisparo metodo,
    required DateTime disparadaEn,
    PuntoGeo? ubicacion,
    int? rumbo,
    String? rutaFoto,
  });

  /// Alerta activa del usuario en tiempo real (aceptada, ETA, llegada).
  /// Emite `null` cuando no hay alerta activa.
  Stream<Alerta?> escucharAlertaActiva();

  /// U-07: ubicación del usuario mientras la alerta está activa.
  Future<void> enviarUbicacion(String alertaId, PuntoGeo ubicacion);

  /// U-09: solo en `guardiaEnLugar`. Lanza `EstadoInvalidoError`.
  Future<Alerta> confirmarAtencion(String alertaId);

  /// Mis alertas, las más recientes primero.
  Future<List<Alerta>> obtenerHistorial();
}
