// CAPA: DATOS — implementación de hoy (almacén local de sesión)
// U-02. Todo vive en el objeto: al destruirlo se olvida.
// La usan las pruebas y cualquier arranque que no quiera tocar el disco.

import 'sesion_guardada.dart';

class MemoriaSesionGuardada implements SesionGuardada {
  MemoriaSesionGuardada({String? usuarioId, Set<String>? permisosVistos})
      : _usuarioId = usuarioId,
        _permisosVistos = {...?permisosVistos};

  String? _usuarioId;
  final Set<String> _permisosVistos;

  @override
  Future<String?> leerUsuarioId() async => _usuarioId;

  @override
  Future<void> guardarUsuarioId(String usuarioId) async => _usuarioId = usuarioId;

  @override
  Future<void> borrarUsuarioId() async => _usuarioId = null;

  @override
  Future<Set<String>> leerPermisosVistos() async => {..._permisosVistos};

  @override
  Future<void> marcarPermisosVistos(String usuarioId) async => _permisosVistos.add(usuarioId);
}
