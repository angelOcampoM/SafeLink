// CAPA: PRESENTACIÓN — ViewModel de sesión (global)
// U-02 · G-01 · U-05 · A-08 (bloqueo)
// Sabe quién está en sesión y avisa cuando cambia; el router lo escucha para
// redirigir por rol. Los demás ViewModels le piden iniciar o cerrar sesión.
// No importa material.dart. No valida formularios (eso es de Login/Registro).

import '../../datos/auth_repository.dart';
import '../../dominio/usuario.dart';
import '../comun/view_model.dart';

class SesionViewModel extends ViewModel {
  SesionViewModel(this._auth, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AuthRepository _auth;
  final DateTime Function() _reloj;

  Usuario? get usuario => _auth.usuarioActual;
  bool get haySesion => usuario != null;
  bool get bloqueado => usuario?.bloqueadoEn(_reloj()) ?? false;

  /// Lanza `ErrorDominio`; quien llama decide cómo mostrarlo.
  Future<Usuario> iniciarSesion(String correo, String contrasena) async {
    final u = await _auth.iniciarSesion(correo: correo.trim(), contrasena: contrasena);
    notifyListeners();
    return u;
  }

  Future<Usuario> registrar({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
  }) async {
    final u = await _auth.registrar(nombre: nombre, correo: correo, telefono: telefono, contrasena: contrasena);
    notifyListeners();
    return u;
  }

  Future<void> cambiarAgitacion(bool activa) async {
    await _auth.actualizarAgitacion(activa: activa);
    notifyListeners();
  }

  Future<void> refrescar() async {
    await _auth.refrescarSesion();
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    await _auth.cerrarSesion();
    notifyListeners();
  }
}
