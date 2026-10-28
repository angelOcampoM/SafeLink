// CAPA: PRESENTACIÓN — ViewModel
// U-01 Registro de usuario protegido
// Guarda errores por campo y del servidor; pide las reglas al dominio y el
// registro a la sesión. No importa material.dart y no navega.

import '../../dominio/regla_registro.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

class RegistroViewModel extends ViewModel {
  RegistroViewModel(this._sesion);
  final SesionViewModel _sesion;

  bool cargando = false;
  String? error;
  String? errorNombre;
  String? errorCorreo;
  String? errorTelefono;
  String? errorContrasena;
  String? errorConfirmacion;

  Future<bool> registrar({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
    required String confirmacion,
  }) async {
    errorNombre = ReglaRegistro.nombre(nombre);
    errorCorreo = ReglaRegistro.correo(correo);
    errorTelefono = ReglaRegistro.telefono(telefono);
    errorContrasena = ReglaRegistro.contrasena(contrasena);
    errorConfirmacion = ReglaRegistro.confirmarContrasena(contrasena, confirmacion);
    error = null;
    if ([errorNombre, errorCorreo, errorTelefono, errorContrasena, errorConfirmacion].any((e) => e != null)) {
      notifyListeners();
      return false;
    }

    cargando = true;
    notifyListeners();
    try {
      // La sesión queda con `permisosPendientes`: el router lleva a la
      // pantalla de permisos antes del inicio (U-01).
      await _sesion.registrar(nombre: nombre, correo: correo, telefono: telefono, contrasena: contrasena);
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
