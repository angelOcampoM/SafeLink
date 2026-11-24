// CAPA: PRESENTACIÓN — ViewModel
// G-02 Recepción de alerta (pantalla "Alerta entrante")
// Carga la alerta y la distancia al guardia; si ya no busca guardia queda en
// Vacío. "Ignorar" se la pide al repositorio. No importa material.dart.

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

typedef AlertaEntrante = ({Alerta alerta, double? distancia});

class AlertaEntranteViewModel extends ViewModel {
  AlertaEntranteViewModel(this._alertas, this.alertaId, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final String alertaId;
  final DateTime Function() _reloj;

  EstadoVista<AlertaEntrante> estado = const Cargando();
  bool ignorando = false;
  String? mensaje;

  DateTime get ahora => _reloj();

  Future<void> cargar() async {
    estado = const Cargando();
    notifyListeners();
    try {
      final r = await Future.wait<Object>([_alertas.obtenerAlerta(alertaId), _alertas.obtenerMiPerfil()]);
      final alerta = r[0] as Alerta;
      final aqui = (r[1] as Guardia).perfil.ultimaUbicacion;
      estado = alerta.estado != EstadoAlerta.buscando
          ? const Vacio()
          : Listo((
              alerta: alerta,
              distancia: aqui == null || alerta.ubicacion == null ? null : ReglaGeocerca.distanciaMetros(aqui, alerta.ubicacion!),
            ),);
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  /// Devuelve `true` si quedó ignorada.
  Future<bool> ignorar() async {
    ignorando = true;
    notifyListeners();
    try {
      await _alertas.ignorarAlerta(alertaId);
      return true;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
      return false;
    } finally {
      ignorando = false;
      notifyListeners();
    }
  }
}
