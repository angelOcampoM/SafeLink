// CAPA: DATOS — implementación de mañana (sesión)
// U-01 · U-02 · G-01 · U-05
// Cumple el MISMO contrato que MemoriaAuthRepository, pero traduce
// Usuario <-> JSON y usa el servicio. Enchufarla solo requiere `usarNube = true`.

import '../dominio/usuario.dart';
import 'auth_repository.dart';
import 'nube_mapeadores.dart';
import 'safelink_service.dart';

class NubeAuthRepository implements AuthRepository {
  NubeAuthRepository(this._service);
  final SafeLinkService _service;

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
    RespuestaJson.datos(await _service.post('/auth/logout'));
    _actual = null;
  }

  @override
  Future<Usuario> refrescarSesion() async => _guardar(await _service.get('/auth/me'));

  @override
  Future<Usuario> actualizarAgitacion({required bool activa}) async =>
      _guardar(await _service.patch('/users/me/settings', {'shakeEnabled': activa}));
}
