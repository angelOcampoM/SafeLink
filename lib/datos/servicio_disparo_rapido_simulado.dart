// CAPA: DATOS — servicio de disparo rápido simulado
// U-05. Reproduce el servicio en segundo plano sin tocar el sistema: las
// pulsaciones se inyectan con `pulsar()` desde la demo o las pruebas.
// Al enchufar el plugin real solo cambia esta implementación.

import 'dart:async';

import 'servicio_disparo_rapido.dart';

class ServicioDisparoRapidoSimulado implements ServicioDisparoRapido {
  final _control = StreamController<DateTime>.broadcast();
  bool _enEjecucion = false;

  @override
  Stream<DateTime> get pulsaciones => _control.stream;

  @override
  bool get enEjecucion => _enEjecucion;

  /// La notificación vive exactamente mientras vive el servicio.
  @override
  bool get notificacionVisible => _enEjecucion;

  @override
  Future<void> iniciar() async => _enEjecucion = true;

  @override
  Future<void> detener() async => _enEjecucion = false;

  /// Solo en demo y pruebas: finge una pulsación del botón de bajar volumen.
  /// Con el servicio detenido no llega nada, igual que en el teléfono.
  void pulsar(DateTime cuando) {
    if (_enEjecucion) _control.add(cuando);
  }

  void dispose() => _control.close();
}

class VibradorSimulado implements Vibrador {
  int veces = 0;

  @override
  Future<void> vibrar() async => veces++;
}
