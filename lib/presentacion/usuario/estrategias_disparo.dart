// CAPA: PRESENTACIÓN — patrón Strategy para los métodos de disparo
// U-03 Toque con cuenta regresiva · U-04 Mantener con zona de descarte · U-05 Agitación
// Cada estrategia decide CUÁNDO se envía la alerta; el InicioViewModel solo
// sabe "iniciar", "cancelar" y qué hacer al enviar o descartar.
// No importa material.dart, no llama repositorios ni pinta nada.

import 'dart:async';

import '../../dominio/enums.dart';

/// Lo que una estrategia puede pedirle al ViewModel que la usa.
abstract interface class ControlDisparo {
  void enviar(MetodoDisparo metodo);
  void descartar();
  void cambio();
}

abstract class EstrategiaDisparo {
  MetodoDisparo get metodo;
  bool get activa;

  void iniciar(ControlDisparo control);
  void cancelar();
}

/// U-03: tocar inicia una cuenta regresiva cancelable; al llegar a 0 se envía.
class ToqueConCuentaRegresiva extends EstrategiaDisparo {
  ToqueConCuentaRegresiva({required this.segundos, this.intervalo = const Duration(seconds: 1)});

  final int segundos;

  /// Un "segundo" de la cuenta. Las pruebas lo acortan.
  final Duration intervalo;

  Timer? _timer;
  int? restante;

  @override
  MetodoDisparo get metodo => MetodoDisparo.toque;

  @override
  bool get activa => restante != null;

  @override
  void iniciar(ControlDisparo control) {
    cancelar();
    restante = segundos;
    control.cambio();
    _timer = Timer.periodic(intervalo, (t) {
      if (restante! <= 1) {
        t.cancel();
        restante = null;
        control.enviar(metodo);
      } else {
        restante = restante! - 1;
        control.cambio();
      }
    });
  }

  @override
  void cancelar() {
    _timer?.cancel();
    _timer = null;
    restante = null;
  }
}

/// U-04: al soltar se envía, salvo que el dedo esté sobre la zona de descarte.
class MantenerConDescarte extends EstrategiaDisparo {
  bool manteniendo = false;
  bool sobreDescarte = false;
  ControlDisparo? _control;

  @override
  MetodoDisparo get metodo => MetodoDisparo.mantener;

  @override
  bool get activa => manteniendo;

  @override
  void iniciar(ControlDisparo control) {
    _control = control;
    manteniendo = true;
    sobreDescarte = false;
    control.cambio();
  }

  void mover({required bool sobreDescarte}) {
    if (!manteniendo || this.sobreDescarte == sobreDescarte) return;
    this.sobreDescarte = sobreDescarte;
    _control?.cambio();
  }

  void soltar() {
    final control = _control;
    if (!manteniendo || control == null) return;
    final descartar = sobreDescarte;
    cancelar();
    descartar ? control.descartar() : control.enviar(metodo);
  }

  @override
  void cancelar() {
    manteniendo = false;
    sobreDescarte = false;
  }
}

/// U-05: la agitación es urgente: se envía al instante, sin cuenta regresiva.
class Agitacion extends EstrategiaDisparo {
  @override
  MetodoDisparo get metodo => MetodoDisparo.agitacion;

  @override
  bool get activa => false;

  @override
  void iniciar(ControlDisparo control) => control.enviar(metodo);

  @override
  void cancelar() {}
}
