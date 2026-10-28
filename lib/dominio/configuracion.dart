// CAPA: DOMINIO — valores configurables (sección 5)
// Los marcados como provisionales aún no los define el equipo: cámbialos SOLO
// aquí, nunca en las vistas. Los "de demo" solo afectan a las simulaciones.
// No hace: no elige memoria o nube (eso es `usarNube` en main.dart).

class Configuracion {
  const Configuracion({
    this.segundosCuentaRegresiva = 3,
    this.radioGeocercaMetros = 50, // provisional
    this.minutosAceptacion = 5, // provisional
    this.minutosConfirmacion = 15, // provisional
    this.limiteFalsasAlarmas = 3, // provisional
    this.diasBloqueo = 7, // provisional
    this.segundosActualizacionUbicacion = 5, // provisional
    this.metrosPorMinutoEspera = 100, // provisional (sección 6.3)
    this.radioCoberturaMinMetros = 500,
    this.radioCoberturaMaxMetros = 10000,
    this.segundosEscalamientoDemo = 90, // demo: en producción son minutosAceptacion
    this.segundosNuevaAlertaMin = 20, // demo
    this.segundosNuevaAlertaMax = 40, // demo
    this.modoDemo = true,
  });

  final int segundosCuentaRegresiva;
  final int radioGeocercaMetros;
  final int minutosAceptacion;
  final int minutosConfirmacion;
  final int limiteFalsasAlarmas;
  final int diasBloqueo;
  final int segundosActualizacionUbicacion;
  final int metrosPorMinutoEspera;
  final int radioCoberturaMinMetros;
  final int radioCoberturaMaxMetros;

  /// Si nadie acepta una alerta en este tiempo pasa a `escalada` (simulación).
  final int segundosEscalamientoDemo;

  /// Intervalo aleatorio entre alertas simuladas cerca del guardia en sesión.
  final int segundosNuevaAlertaMin;
  final int segundosNuevaAlertaMax;

  /// Muestra cuentas de prueba y botones "Simular …" (datos ficticios).
  final bool modoDemo;

  static const porDefecto = Configuracion();
}
