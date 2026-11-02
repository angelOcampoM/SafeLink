// CAPA: DOMINIO — comparación de texto para búsquedas
// A-02: "la búsqueda encuentra coincidencias sin importar mayúsculas,
// minúsculas o acentos". Dart puro, sin dependencias de plataforma.
// No hace: no busca en ninguna lista; solo dice si un texto contiene a otro.

abstract final class TextoBusqueda {
  // Dart no trae normalización Unicode, así que se mapean las letras que el
  // español necesita. Se incluye la diéresis (güero) y la eñe se respeta:
  // "ñ" y "n" son letras distintas y no deben confundirse al buscar.
  static const _acentos = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  };

  /// Minúsculas, sin acentos y sin espacios sobrantes.
  static String normalizar(String texto) {
    final buffer = StringBuffer();
    for (final letra in texto.trim().toLowerCase().split('')) {
      buffer.write(_acentos[letra] ?? letra);
    }
    return buffer.toString();
  }

  /// `true` si [texto] contiene a [consulta] ignorando mayúsculas y acentos.
  /// Una consulta vacía coincide con todo.
  static bool contiene(String texto, String consulta) {
    final q = normalizar(consulta);
    return q.isEmpty || normalizar(texto).contains(q);
  }
}
