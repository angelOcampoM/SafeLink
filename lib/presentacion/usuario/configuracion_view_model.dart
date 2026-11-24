// CAPA: PRESENTACIÓN — ViewModel
// U-05 Configuración (activar/desactivar el doble clic de volumen)
// Guarda el estado de guardado y pide el cambio a la sesión.
// No importa material.dart.

import '../../dominio/usuario.dart';
import '../comun/view_model.dart';
import 'disparo_rapido.dart';
import '../sesion/sesion_view_model.dart';

class ConfiguracionViewModel extends ViewModel {
  ConfiguracionViewModel(this._sesion, this._disparoRapido);
  final SesionViewModel _sesion;
  final DisparoRapido _disparoRapido;

  bool guardando = false;
  String? mensaje;

  Usuario? get usuario => _sesion.usuario;

  /// U-05: el atajo está activado pero el sistema aún no deja llegar las pulsaciones.
  /// En Android pasa hasta que la persona activa el servicio en Ajustes → Accesibilidad.
  bool get faltaAccesoDelSistema => _disparoRapido.faltaAccesoDelSistema;

  /// Abre los Ajustes del sistema y, al volver, vuelve a preguntar.
  Future<void> concederAccesoDelSistema() async {
    await _disparoRapido.abrirAjustesDelSistema();
    await _disparoRapido.revisarAccesoDelSistema();
    notifyListeners();
  }

  /// Al volver a la pantalla: puede que el acceso ya se haya concedido.
  Future<void> revisarAccesoDelSistema() async {
    await _disparoRapido.revisarAccesoDelSistema();
    notifyListeners();
  }

  Future<void> cambiarDobleClicVolumen(bool activa) async {
    guardando = true;
    notifyListeners();
    try {
      await _sesion.cambiarDobleClicVolumen(activa);
      // U-05: la preferencia y el servicio en segundo plano van juntos.
      activa ? await _disparoRapido.activar() : await _disparoRapido.desactivar();
      mensaje = activa ? 'Doble clic de volumen activado' : 'Doble clic de volumen desactivado';
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
    } finally {
      guardando = false;
      notifyListeners();
    }
  }

  /// U-02: vuelve a abrir la explicación de permisos (el router la muestra).
  void revisarPermisos() => _sesion.revisarPermisos();

  Future<void> cerrarSesion() => _sesion.cerrarSesion();

  void consumirMensaje() => mensaje = null;
}
