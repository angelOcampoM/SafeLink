// CAPA: PRESENTACIÓN — apoyo de las pestañas del guardia
// G-03 Datos frescos: avisa cuando una pestaña vuelve a verse para que su ViewModel recargue.
// Usa TickerMode porque ya cubre los dos casos sin tocar el router ni el contrato:
// StatefulShellRoute.indexedStack apaga los tickers de las pestañas ocultas, y el
// Navigator apaga los de las pantallas tapadas por el flujo de atención.
// No hace: no recarga por su cuenta ni sabe de repositorios.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

mixin RecargaAlVolver<T extends StatefulWidget> on State<T> {
  ValueListenable<TickerModeData>? _visible;
  var _estabaVisible = true;

  /// Se llama cada vez que la pantalla pasa de oculta a visible (no al abrirla).
  void alVolverAVerse();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notificador = TickerMode.getValuesNotifier(context);
    if (identical(notificador, _visible)) return;
    _visible?.removeListener(_alCambiarVisibilidad);
    _visible = notificador..addListener(_alCambiarVisibilidad);
    _estabaVisible = notificador.value.enabled;
  }

  void _alCambiarVisibilidad() {
    final visible = _visible!.value.enabled;
    // TickerMode cambia mientras se construye el árbol: la recarga espera al siguiente frame.
    if (visible && !_estabaVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) alVolverAVerse();
      });
    }
    _estabaVisible = visible;
  }

  @override
  void dispose() {
    _visible?.removeListener(_alCambiarVisibilidad);
    super.dispose();
  }
}
