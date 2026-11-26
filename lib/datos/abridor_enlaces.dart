// CAPA: DATOS — el contrato para abrir un enlace en otra app
// G-06 Ruta hacia el usuario (CR-F04): "Abrir en Google Maps".
// Dice "abre esta dirección", no con qué plugin: en el teléfono es url_launcher
// (abridor_enlaces_real.dart) y en pruebas y demo, el simulado de aquí abajo.
// No hace: no arma la dirección (eso es del ViewModel) ni avisa al usuario.

abstract interface class AbridorEnlaces {
  /// Abre [url] fuera de la app. `false` si el teléfono no tiene con qué abrirla.
  ///
  /// Nunca lanza: un fallo se reporta como `false` para que la pantalla siga viva.
  Future<bool> abrir(Uri url);
}

/// Guarda lo que se le pidió abrir. Sirve en pruebas y en web/escritorio.
class AbridorEnlacesSimulado implements AbridorEnlaces {
  AbridorEnlacesSimulado({this.falla = false});

  /// `true` reproduce "no hay app que abra el enlace".
  final bool falla;

  final List<Uri> abiertos = [];

  @override
  Future<bool> abrir(Uri url) async {
    if (falla) return false;
    abiertos.add(url);
    return true;
  }
}
