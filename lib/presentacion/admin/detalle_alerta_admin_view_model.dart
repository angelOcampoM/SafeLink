// CAPA: PRESENTACIÓN — ViewModel
// A-05 Detalle de una alerta del historial del admin
// Busca la alerta por id dentro del historial y la expone con los cuatro
// estados de vista. No importa material.dart y no navega.

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class DetalleAlertaAdminViewModel extends ViewModel {
  DetalleAlertaAdminViewModel(this._admin, this.alertaId, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AdminRepository _admin;
  final String alertaId;
  final DateTime Function() _reloj;

  EstadoVista<Alerta> estado = const Cargando();

  DateTime get ahora => _reloj();

  Future<void> cargar() async {
    estado = const Cargando();
    notifyListeners();
    try {
      final historial = await _admin.obtenerHistorial(const FiltroHistorial());
      final alerta = historial.where((a) => a.id == alertaId).firstOrNull;
      estado = alerta == null ? const Vacio<Alerta>() : Listo(alerta);
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }
}
