// CAPA: PRESENTACIÓN — ViewModel
// U-02 Inicio de sesión · G-01 Login del guardia (compartido por los tres roles)
// Guarda el estado (cargando, errores por campo, error del servidor) y orquesta:
// pide la regla al dominio y el inicio de sesión a la sesión.
// No importa material.dart: no pinta y no navega (el router redirige por rol).

import '../../dominio/regla_registro.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

class LoginViewModel extends ViewModel {
  LoginViewModel(this._sesion, {this.cuentasDemo = const [], this.contrasenaDemo = ''});

  final SesionViewModel _sesion;

  /// Solo en demo: (etiqueta, correo) para rellenar el formulario.
  final List<(String, String)> cuentasDemo;
  final String contrasenaDemo;

  bool cargando = false;
  String? error;
  String? errorCorreo;
  String? errorContrasena;

  bool get modoDemo => cuentasDemo.isNotEmpty;

  /// Devuelve `true` si inició sesión.
  Future<bool> entrar(String correo, String contrasena) async {
    errorCorreo = ReglaRegistro.correo(correo);
    errorContrasena = ReglaRegistro.contrasenaLogin(contrasena);
    error = null;
    if (errorCorreo != null || errorContrasena != null) {
      notifyListeners();
      return false;
    }

    cargando = true;
    notifyListeners();
    try {
      await _sesion.iniciarSesion(correo, contrasena);
      return true;
    } catch (e) {
      error = ViewModel.mensajeDe(e);
      return false;
    } finally {
      cargando = false;
      notifyListeners();
    }
  }
}
