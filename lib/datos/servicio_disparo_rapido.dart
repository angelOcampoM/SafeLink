// CAPA: DATOS — el contrato del disparo con la pantalla bloqueada
// U-05. Un servicio en segundo plano que escucha el botón de bajar volumen
// y, mientras vive, mantiene una notificación visible (Android lo exige).
// No hace: no decide qué es un doble clic (eso es ReglaDobleClic) ni crea alertas.

abstract interface class ServicioDisparoRapido {
  /// Una emisión por cada pulsación del botón de bajar volumen.
  Stream<DateTime> get pulsaciones;

  bool get enEjecucion;

  /// La notificación permanente que acompaña al servicio en segundo plano.
  bool get notificacionVisible;

  Future<void> iniciar();

  Future<void> detener();

  /// ¿El sistema va a dejar llegar las pulsaciones?
  ///
  /// En Android no basta con encender el servicio desde la app: la persona tiene que
  /// activarlo en Ajustes → Accesibilidad, y mientras no lo haga el botón no hace nada.
  /// Donde no haga falta ningún permiso del sistema, `true`.
  Future<bool> listoEnElSistema();

  /// Abre la pantalla del sistema donde se concede ese acceso. Donde no haga falta, nada.
  Future<void> abrirAjustesDelSistema();
}

/// U-05: el teléfono confirma por vibración que la alerta salió.
abstract interface class Vibrador {
  Future<void> vibrar();
}
