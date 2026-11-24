// CAPA: DATOS — implementación de mañana (sesión)
// U-01 · U-02 · G-01 · U-05
// Cumple el MISMO contrato que MemoriaAuthRepository, pero traduce
// Usuario <-> JSON y usa el servicio. Enchufarla solo requiere `usarNube = true`.

import '../dominio/usuario.dart';
import 'auth_repository.dart';
import 'cliente_api.dart';
import 'nube_mapeadores.dart';

class NubeAuthRepository implements AuthRepository {
  NubeAuthRepository(this._service);
  final ClienteApi _service;

  Usuario? _actual;

  @override
  Usuario? get usuarioActual => _actual;

  Usuario _guardar(Json respuesta) => _actual = UsuarioJson.desdeJson(RespuestaJson.datos(respuesta)! as Json);

  @override
  Future<Usuario> iniciarSesion({required String correo, required String contrasena}) async =>
      _guardar(await _service.post('/auth/login', {'email': correo, 'password': contrasena}));

  @override
  Future<Usuario> registrar({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
  }) async =>
      _guardar(await _service.post('/auth/register', {
        'name': nombre,
        'email': correo,
        'phone': telefono,
        'password': contrasena,
      }),);

  @override
  Future<void> cerrarSesion() async {
    try {
      RespuestaJson.datos(await _service.post('/auth/logout'));
    } finally {
      _actual = null; // la sesión local se cierra aunque el servidor falle
    }
  }

  @override
  Future<Usuario> refrescarSesion() async => _guardar(await _service.get('/auth/me'));

  @override
  Future<Usuario?> restaurarSesion(String usuarioId) async {
    // API real: primero se canjea el refresh token guardado (sin sesión → null).
    final previo = await _service.restaurarSesionGuardada();
    if (previo != null) {
      RespuestaJson.datos(previo); // lanza si fue un fallo de red
      return null;
    }
    final respuesta = await _service.post('/auth/session', {'userId': usuarioId});
    final datos = RespuestaJson.datos(respuesta);
    return datos == null ? null : _guardar(respuesta);
  }

  @override
  Future<Usuario> actualizarDobleClicVolumen({required bool activa}) async =>
      _guardar(await _service.patch('/users/me/settings', {'volumeDoubleClickEnabled': activa}));
}
