// CAPA: DATOS — abrir enlaces con url_launcher
// G-06 (CR-F04). Abre la dirección en la app que el teléfono tenga para ella
// (Google Maps, si está instalada; si no, el navegador).
// Android 11+ exige declarar en el manifest qué intents se consultan (<queries>).

import 'package:url_launcher/url_launcher.dart';

import 'abridor_enlaces.dart';

class AbridorEnlacesReal implements AbridorEnlaces {
  const AbridorEnlacesReal();

  @override
  Future<bool> abrir(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object {
      return false; // sin app que lo abra o plataforma sin soporte: lo avisa la pantalla
    }
  }
}
