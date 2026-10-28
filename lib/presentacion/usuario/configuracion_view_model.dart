// CAPA: PRESENTACIÓN — ViewModel
// U-05 Configuración (activar/desactivar agitación)
// Guarda el estado de guardado y pide el cambio a la sesión.
// No importa material.dart.

import '../../dominio/usuario.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

class ConfiguracionViewModel extends ViewModel {
  ConfiguracionViewModel(this._sesion);
  final SesionViewModel _sesion;

  bool guardando = false;
  String? mensaje;

  Usuario? get usuario => _sesion.usuario;

  Future<void> cambiarAgitacion(bool activa) async {
    guardando = true;
    notifyListeners();
    try {
      await _sesion.cambiarAgitacion(activa);
      mensaje = activa ? 'Agitación activada' : 'Agitación desactivada';
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
    } finally {
      guardando = false;
      notifyListeners();
    }
  }

  Future<void> cerrarSesion() => _sesion.cerrarSesion();

  void consumirMensaje() => mensaje = null;
}
