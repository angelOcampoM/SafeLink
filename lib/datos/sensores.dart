// CAPA: DATOS — los contratos de los sensores del teléfono
// U-06 Captura automática de evidencia · U-07 Ubicación en tiempo real
// Hablan de "toma una foto", "dame la posición", "dame el rumbo". No dicen
// con qué plugin: hoy son simulados y mañana serán cámara, GPS y brújula reales.
// No hace: no crea alertas ni decide cuándo capturar (eso es del ViewModel).

import '../dominio/punto_geo.dart';

/// Una sola foto automática del entorno, sin intervención del usuario (U-06).
abstract interface class Camara {
  /// Ruta de la foto, o `null` si no se pudo tomar: la alerta viaja igual,
  /// marcada como evidencia incompleta.
  Future<String?> tomarFoto();
}

/// Posición del dispositivo (U-06 al disparar, U-07 mientras dura la alerta).
abstract interface class Ubicacion {
  /// Coordenada actual, o `null` si todavía no hay señal válida: la alerta
  /// queda pendiente de ubicación y no se publica.
  Future<PuntoGeo?> posicionActual();

  /// Posiciones sucesivas mientras la alerta está activa.
  Stream<PuntoGeo> seguir();
}

/// Rumbo de la cámara en grados respecto al norte (U-06).
abstract interface class Brujula {
  /// Grados 0–359, o `null` si el magnetómetro no responde.
  Future<int?> rumbo();
}
