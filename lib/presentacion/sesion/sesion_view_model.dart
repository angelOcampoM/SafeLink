// CAPA: PRESENTACIÓN — ViewModel de sesión (global)
// U-02 · G-01 · U-05 · A-08 (bloqueo)
// Sabe quién está en sesión y avisa cuando cambia; el router lo escucha para
// redirigir por rol. Los demás ViewModels le piden iniciar o cerrar sesión.
// No importa material.dart. No valida formularios (eso es de Login/Registro).

import '../../datos/auth_repository.dart';
import '../../datos/permisos_sistema.dart';
import '../../datos/sesion_guardada.dart';
import '../../dominio/enums.dart';
import '../../dominio/usuario.dart';
import '../comun/view_model.dart';

class SesionViewModel extends ViewModel {
  SesionViewModel(
    this._auth,
    this._guardada, {
    DateTime Function()? reloj,
    PermisosSistema? permisos,
  })  : _reloj = reloj ?? DateTime.now,
        _permisos = permisos ?? const PermisosConcedidos();

  final AuthRepository _auth;
  final SesionGuardada _guardada;
  final DateTime Function() _reloj;
  final PermisosSistema _permisos;

  Usuario? get usuario => _auth.usuarioActual;
  bool get haySesion => usuario != null;
  bool get bloqueado => usuario?.bloqueadoEn(_reloj()) ?? false;

  /// U-01 · U-02: la primera vez que un usuario protegido entra (registro o
  /// primer inicio de sesión) hay que mostrar la pantalla de permisos.
  /// El router la consulta para redirigir; se apaga al tocar "Continuar".
  bool permisosPendientes = false;

  /// Usuarios que ya vieron la pantalla de permisos (se lee del almacén al
  /// arrancar, así la explicación no se repite tras reinstalar la sesión).
  final _permisosVistosPor = <String>{};

  /// U-02: reabre la sesión que quedó guardada en el dispositivo.
  /// `main.dart` la llama antes de pintar; si no hay nada guardada no hace nada.
  Future<void> restaurar() async {
    _permisosVistosPor.addAll(await _guardada.leerPermisosVistos());
    final id = await _guardada.leerUsuarioId();
    if (id == null) return;
    final u = await _auth.restaurarSesion(id);
    // La cuenta pudo darse de baja mientras la app estaba cerrada.
    if (u == null) {
      await _guardada.borrarUsuarioId();
      return;
    }
    permisosPendientes = _faltanPermisos(u);
    notifyListeners();
  }

  bool _faltanPermisos(Usuario u) =>
      u.rol == RolUsuario.usuarioProtegido && !_permisosVistosPor.contains(u.id);

  /// Lanza `ErrorDominio`; quien llama decide cómo mostrarlo.
  Future<Usuario> iniciarSesion(String correo, String contrasena) async {
    final u = await _auth.iniciarSesion(correo: correo.trim(), contrasena: contrasena);
    await _guardada.guardarUsuarioId(u.id);
    permisosPendientes = _faltanPermisos(u);
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
    await _guardada.guardarUsuarioId(u.id);
    permisosPendientes = true;
    notifyListeners();
    return u;
  }

  Future<void> cambiarDobleClicVolumen(bool activa) async {
    await _auth.actualizarDobleClicVolumen(activa: activa);
    notifyListeners();
  }

  Future<void> refrescar() async {
    await _auth.refrescarSesion();
    notifyListeners();
  }

  /// Desde Configuración: vuelve a mostrar la explicación de los permisos.
  void revisarPermisos() {
    permisosPendientes = true;
    notifyListeners();
  }

  /// La pantalla de permisos ya se mostró: el router deja pasar al inicio.
  /// Último estado conocido de los permisos del sistema (para Configuración).
  EstadoPermisos? estadoPermisos;

  /// U-01 · U-02 · "Continuar": ahora SÍ se los pide al sistema, después de haber explicado
  /// para qué sirven. La pantalla se marca como vista pase lo que pase con la respuesta:
  /// negarse deja la app en pie (la alerta viajará sin foto o pendiente de ubicación) y no
  /// puede dejar a nadie atrapado en la explicación.
  Future<void> permisosVistos() async {
    final id = usuario?.id;
    permisosPendientes = false;
    notifyListeners();
    if (id != null) {
      _permisosVistosPor.add(id);
      await _guardada.marcarPermisosVistos(id);
    }
    estadoPermisos = await _permisos.pedirLosDeLaAlerta();
    notifyListeners();
  }

  /// Lo ya concedido, sin preguntar: lo usa Configuración para mostrar el estado.
  Future<void> revisarPermisosDelSistema() async {
    estadoPermisos = await _permisos.estado();
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    // Aunque el cierre en el servidor falle, la sesión local se cierra igual y se avisa:
    // así se apagan el GPS del guardia y la transmisión de ubicación (CR-F02).
    try {
      await _auth.cerrarSesion();
    } finally {
      await _guardada.borrarUsuarioId();
      permisosPendientes = false;
      notifyListeners();
    }
  }
}
