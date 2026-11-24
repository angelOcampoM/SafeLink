// CAPA: PRESENTACIÓN — ViewModel
// Historial de mis alertas (usuario protegido; complementa U-08/U-09)
// Carga las alertas del usuario en un EstadoVista y recuerda cuál está abierta.
// No importa material.dart.

import '../../datos/alerta_usuario_repository.dart';
import '../../dominio/alerta.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class HistorialUsuarioViewModel extends ViewModel {
  HistorialUsuarioViewModel(this._alertas, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaUsuarioRepository _alertas;
  final DateTime Function() _reloj;

  EstadoVista<List<Alerta>> estado = const Cargando();

  DateTime get ahora => _reloj();

  Future<void> cargar() async {
    if (estado is! Listo) {
      estado = const Cargando();
      notifyListeners();
    }
    try {
      estado = EstadoVista.deLista(await _alertas.obtenerHistorial());
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }
}
