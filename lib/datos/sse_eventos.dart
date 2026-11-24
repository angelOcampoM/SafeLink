// CAPA: DATOS — lector del formato SSE (texto → eventos JSON)
// D3 · Contrato sección 6. Función pura sobre un flujo de líneas: no abre conexiones,
// no reintenta y no sabe de HTTP. Así se puede probar el formato sin servidor.
//
// Del formato `text/event-stream` el contrato solo usa dos cosas:
//   - `data: <json>` seguido de una línea en blanco = un evento;
//   - una línea que empieza con `:` es un comentario (el `: ping` del servidor, D26).
// Los campos `event`, `id` y `retry` no se usan: cada evento del backend es el envoltorio
// completo (`{"data":...}` o `{"error":{...}}`), así que no hace falta distinguir tipos.

import 'dart:convert';

import 'nube_mapeadores.dart' show Json;

/// Convierte las líneas de un flujo SSE en el objeto JSON de cada evento.
///
/// Lo que no es un objeto JSON válido se descarta en silencio: un evento roto no debe
/// tumbar un canal del que depende una alerta en curso.
Stream<Json> eventosSse(Stream<String> lineas) async* {
  final datos = <String>[];

  Json? cerrarEvento() {
    if (datos.isEmpty) return null;
    final texto = datos.join('\n');
    datos.clear();
    if (texto.trim().isEmpty) return null;
    try {
      final decodificado = jsonDecode(texto);
      return decodificado is Map ? Json.from(decodificado) : null;
    } on Object {
      return null; // JSON incompleto o basura: se ignora el evento
    }
  }

  await for (final linea in lineas) {
    if (linea.isEmpty) {
      final evento = cerrarEvento();
      if (evento != null) yield evento;
      continue;
    }
    if (linea.startsWith(':')) continue; // comentario, p. ej. ": ping"

    final separador = linea.indexOf(':');
    final campo = separador == -1 ? linea : linea.substring(0, separador);
    var valor = separador == -1 ? '' : linea.substring(separador + 1);
    // El formato permite un espacio de cortesía después de los dos puntos.
    if (valor.startsWith(' ')) valor = valor.substring(1);
    if (campo == 'data') datos.add(valor);
  }
  // Si el servidor cortó a media escritura, el evento incompleto NO se emite: emitirlo
  // entregaría un snapshot a medias, que es peor que esperar a la reconexión.
}
