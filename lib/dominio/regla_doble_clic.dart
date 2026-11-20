// CAPA: DOMINIO — detección del doble clic del botón de bajar volumen
// U-05. Dos pulsaciones dentro de la ventana son un doble clic; una sola no.
// Dart puro y sin temporizadores: recibe la hora de cada pulsación y responde.
// No hace: no escucha el botón (eso es ServicioDisparoRapido) ni crea alertas.

class ReglaDobleClic {
  ReglaDobleClic({this.ventana = ventanaPorDefecto});

  /// Ventana por defecto del doble clic. La comparte el servicio nativo de Android
  /// (`ServicioDisparoRapidoNativo` se la pasa a Kotlin al iniciar) para que las dos
  /// capas cuenten con el mismo tiempo y no haya dos reglas distintas.
  static const Duration ventanaPorDefecto = Duration(milliseconds: 600);

  /// Tiempo máximo entre las dos pulsaciones para que cuenten como doble clic.
  final Duration ventana;

  DateTime? _pendiente;

  /// `true` cuando esta pulsación cierra un doble clic.
  ///
  /// El par se consume: tres pulsaciones seguidas son un doble clic y una
  /// suelta, no dos dobles.
  bool registrar(DateTime cuando) {
    final previa = _pendiente;
    if (previa != null && cuando.difference(previa) <= ventana && !cuando.isBefore(previa)) {
      _pendiente = null;
      return true;
    }
    _pendiente = cuando;
    return false;
  }

  /// Olvida la pulsación suelta (al detener el servicio).
  void reiniciar() => _pendiente = null;
}
