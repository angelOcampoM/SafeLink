// A-02 (unitaria) — "la búsqueda encuentra coincidencias sin importar
// mayúsculas, minúsculas o acentos".
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/texto_busqueda.dart';

void main() {
  test('encuentra sin importar mayúsculas', () {
    expect(TextoBusqueda.contiene('Carlos Hernández López', 'carlos'), isTrue);
    expect(TextoBusqueda.contiene('Carlos Hernández López', 'CARLOS'), isTrue);
  });

  test('encuentra aunque la consulta venga sin acentos', () {
    expect(TextoBusqueda.contiene('Carlos Hernández López', 'hernandez'), isTrue);
    expect(TextoBusqueda.contiene('Carlos Hernández López', 'lopez'), isTrue);
  });

  test('encuentra aunque el texto venga sin acentos y la consulta con ellos', () {
    expect(TextoBusqueda.contiene('Carlos Hernandez', 'Hernández'), isTrue);
  });

  test('la eñe no se confunde con la ene', () {
    expect(TextoBusqueda.contiene('Muñoz', 'munoz'), isFalse);
    expect(TextoBusqueda.contiene('Muñoz', 'muñoz'), isTrue);
  });

  test('la diéresis también se normaliza', () {
    expect(TextoBusqueda.contiene('Agüero', 'aguero'), isTrue);
  });

  test('ignora espacios sobrantes en la consulta', () {
    expect(TextoBusqueda.contiene('Carlos Hernández', '  carlos  '), isTrue);
  });

  test('una consulta vacía coincide con todo', () {
    expect(TextoBusqueda.contiene('cualquier cosa', ''), isTrue);
    expect(TextoBusqueda.contiene('cualquier cosa', '   '), isTrue);
  });

  test('lo que no coincide sigue sin coincidir', () {
    expect(TextoBusqueda.contiene('Carlos Hernández', 'rodriguez'), isFalse);
  });

  test('normalizar deja el texto en minúsculas y sin acentos', () {
    expect(TextoBusqueda.normalizar('  ÁÉÍÓÚ Ü  '), 'aeiou u');
  });
}
