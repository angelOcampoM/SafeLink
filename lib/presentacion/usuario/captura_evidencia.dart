// CAPA: PRESENTACIÓN — captura de evidencia (U-06)
// Lee los tres sensores a la vez y devuelve lo que viaja con la alerta.
// Lo comparten el botón de la pantalla de inicio y el disparo con la pantalla
// bloqueada, para que la evidencia sea idéntica venga de donde venga.
// No importa material.dart y no crea alertas.

import '../../datos/sensores.dart';
import '../../dominio/punto_geo.dart';

typedef Evidencia = ({String? foto, PuntoGeo? ubicacion, int? rumbo});

class CapturaEvidencia {
  CapturaEvidencia({required Camara camara, required Ubicacion ubicacion, required Brujula brujula})
      : _camara = camara,
        _ubicacion = ubicacion,
        _brujula = brujula;

  final Camara _camara;
  final Ubicacion _ubicacion;
  final Brujula _brujula;

  /// Una sola foto automática, con la coordenada y el rumbo del mismo
  /// instante. Si un sensor falla devuelve `null` y la alerta viaja igual:
  /// el repositorio la marcará como evidencia incompleta o pendiente de
  /// ubicación, según el caso.
  Future<Evidencia> capturar() async {
    final leidos = await Future.wait([_camara.tomarFoto(), _ubicacion.posicionActual(), _brujula.rumbo()]);
    return (foto: leidos[0] as String?, ubicacion: leidos[1] as PuntoGeo?, rumbo: leidos[2] as int?);
  }
}
