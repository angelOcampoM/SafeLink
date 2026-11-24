// CAPA: DATOS — contrato del cliente de la API
// Lo que necesitan los repositorios `nube_*`: enviar una petición y escuchar un
// canal en tiempo real. Lo cumplen el servicio simulado (SafeLinkService) y el
// cliente HTTP real (HttpSafeLinkService). Los repositorios no saben cuál usan.
// Toda respuesta es el envoltorio `{ "data": ... }` o `{ "error": { ... } }`.

import 'nube_mapeadores.dart';

abstract class ClienteApi {
  const ClienteApi();

  /// Envía una petición. Nunca lanza por errores de la API ni de red: los
  /// devuelve dentro del envoltorio `{ "error": ... }`.
  Future<Json> enviar(String metodo, String ruta, {Json? cuerpo, Map<String, String>? query});

  /// Canal en tiempo real. Cada evento es `{ "data": ... }` o `{ "error": ... }`.
  Stream<Json> escuchar(String canal);

  /// Paso previo a `POST /auth/session` (U-02). En la API real canjea el
  /// refresh token guardado. Devuelve `null` si se puede continuar con
  /// `/auth/session` (caso del simulado); si devuelve un envoltorio, ese es el
  /// resultado final: `{ "data": null }` = sin sesión recuperable (no hay token
  /// o el refresh dio UNAUTHORIZED), `{ "error": ... }` = fallo de red.
  Future<Json?> restaurarSesionGuardada() async => null;

  /// POST con un archivo adjunto (U-06: la foto de la alerta). [datos] es el
  /// mismo JSON de siempre y [rutaArchivo] la ruta local del archivo, o `null`.
  /// Por defecto (servicio simulado) es un POST normal: el archivo no viaja.
  Future<Json> postConArchivo(String ruta, Json datos, {String? rutaArchivo}) => post(ruta, datos);

  Future<Json> get(String ruta, {Map<String, String> query = const {}}) => enviar('GET', ruta, query: query);
  Future<Json> post(String ruta, [Json cuerpo = const {}]) => enviar('POST', ruta, cuerpo: cuerpo);
  Future<Json> put(String ruta, [Json cuerpo = const {}]) => enviar('PUT', ruta, cuerpo: cuerpo);
  Future<Json> patch(String ruta, [Json cuerpo = const {}]) => enviar('PATCH', ruta, cuerpo: cuerpo);
  Future<Json> delete(String ruta) => enviar('DELETE', ruta);
}
