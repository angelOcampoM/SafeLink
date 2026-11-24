// CAPA: PRESENTACIÓN — envío espaciado de posiciones (CR-F02 · CR-F05)
// El GPS puede emitir varias posiciones por segundo, pero la API limita cuántas
// acepta por ventana y responde 429 si se excede. Esta clase deja pasar como
// mucho un envío por [intervalo], con un solo envío en vuelo, y si llegan
// varias posiciones mientras espera manda solo la más reciente.
// No hace: no lee sensores ni decide qué se envía; no importa material.dart.

import 'dart:async';

class EnvioEspaciado<T> {
  EnvioEspaciado({required this.intervalo, required Future<void> Function(T valor) enviar}) : _enviar = enviar;

  /// Tiempo mínimo entre el fin de un envío y el inicio del siguiente.
  /// `Duration.zero` = sin espaciado: cada valor se envía en cuanto llega.
  final Duration intervalo;
  final Future<void> Function(T valor) _enviar;

  T? _pendiente;
  bool _hayPendiente = false;

  /// `true` mientras hay un envío en vuelo o se está esperando el intervalo.
  bool _ocupado = false;
  bool _cerrado = false;
  Timer? _espera;

  /// Encola [valor]; si ya había otro pendiente, lo reemplaza.
  void agregar(T valor) {
    if (_cerrado) return;
    if (intervalo == Duration.zero) {
      unawaited(_enviar(valor).catchError((Object _) {}));
      return;
    }
    _pendiente = valor;
    _hayPendiente = true;
    if (!_ocupado) unawaited(_despachar());
  }

  Future<void> _despachar() async {
    if (_cerrado || !_hayPendiente) {
      _ocupado = false;
      return;
    }
    _ocupado = true;
    final valor = _pendiente as T;
    _pendiente = null;
    _hayPendiente = false;
    try {
      await _enviar(valor);
    } on Object {
      // Un fallo de red no detiene el seguimiento: la siguiente posición lo reintenta.
    }
    if (_cerrado) return;
    _espera = Timer(intervalo, () => unawaited(_despachar()));
  }

  /// Descarta lo pendiente y no vuelve a enviar.
  void cerrar() {
    _cerrado = true;
    _espera?.cancel();
    _pendiente = null;
    _hayPendiente = false;
  }
}
