// CAPA: DOMINIO — tiempo estimado de llegada del guardia (U-08)
// Convierte la distancia que falta en segundos de camino. Dart puro: no sabe
// de mapas ni de tráfico real, solo aplica la velocidad de desplazamiento.
// No hace: no mide la distancia (eso es ReglaGeocerca) ni actualiza la alerta.

abstract final class ReglaEta {
  /// Segundos que tardará el guardia en recorrer [distanciaMetros].
  ///
  /// A menor distancia, menor tiempo. Nunca negativo: si ya llegó, 0.
  static int segundos({required double distanciaMetros, required int metrosPorMinutoGuardia}) {
    if (distanciaMetros <= 0 || metrosPorMinutoGuardia <= 0) return 0;
    return (distanciaMetros / metrosPorMinutoGuardia * 60).round();
  }
}
