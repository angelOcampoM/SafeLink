// Prueba de arquitectura: la regla de dependencias se cumple leyendo los imports.
//   presentacion → datos → dominio · dominio no depende de nadie.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> dartEn(String carpeta) => Directory(carpeta)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

List<String> importsDe(File f) => f
    .readAsLinesSync()
    .where((l) => l.trimLeft().startsWith('import ') || l.trimLeft().startsWith('export '))
    .toList();

String nombre(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('lib/dominio es Dart puro: ningún archivo importa package:flutter', () {
    final archivos = dartEn('lib/dominio');
    expect(archivos, isNotEmpty);
    final culpables = [
      for (final f in archivos)
        if (importsDe(f).any((l) => l.contains('package:flutter'))) nombre(f),
    ];
    expect(culpables, isEmpty, reason: 'El dominio no debe conocer Flutter');
  });

  test('lib/dominio no depende de datos ni de presentación', () {
    final culpables = [
      for (final f in dartEn('lib/dominio'))
        if (importsDe(f).any((l) => l.contains('datos/') || l.contains('presentacion/'))) nombre(f),
    ];
    expect(culpables, isEmpty);
  });

  test('lib/datos no depende de presentación', () {
    final culpables = [
      for (final f in dartEn('lib/datos'))
        if (importsDe(f).any((l) => l.contains('presentacion/'))) nombre(f),
    ];
    expect(culpables, isEmpty);
  });

  // De `package:flutter`, la capa de datos solo puede tocar la puerta al sistema operativo
  // (`services.dart`: canales nativos; `foundation.dart`: kIsWeb y tipos base). Nada de
  // interfaz: un repositorio o un adaptador no pinta. La lista es cerrada a propósito, así
  // que sumar otra importación de Flutter aquí obliga a cambiar esta prueba y discutirlo.
  const flutterPermitidoEnDatos = [
    'package:flutter/services.dart',
    'package:flutter/foundation.dart',
  ];

  test('lib/datos solo usa de Flutter la puerta al sistema, nunca la interfaz', () {
    final culpables = <String>[];
    for (final f in dartEn('lib/datos')) {
      for (final linea in importsDe(f)) {
        if (!linea.contains('package:flutter/')) continue;
        if (flutterPermitidoEnDatos.any(linea.contains)) continue;
        culpables.add('${nombre(f)}: ${linea.trim()}');
      }
    }
    expect(culpables, isEmpty,
        reason:
            'La capa de datos no conoce la interfaz: solo services.dart y foundation.dart',);
  });

  test('ningún archivo de lib/datos importa material, widgets ni cupertino', () {
    final culpables = [
      for (final f in dartEn('lib/datos'))
        if (importsDe(f).any((l) =>
            l.contains('package:flutter/material.dart') ||
            l.contains('package:flutter/widgets.dart') ||
            l.contains('package:flutter/cupertino.dart'),)) nombre(f),
    ];
    expect(culpables, isEmpty);
  });

  test('ningún *_view_model.dart importa material.dart (ni widgets)', () {
    final vms = dartEn('lib').where((f) => f.path.endsWith('_view_model.dart')).toList();
    expect(vms.length, greaterThanOrEqualTo(18));
    final culpables = [
      for (final f in vms)
        if (importsDe(f).any((l) =>
            l.contains('package:flutter/material.dart') ||
            l.contains('package:flutter/widgets.dart') ||
            l.contains('package:flutter/cupertino.dart'),)) nombre(f),
    ];
    expect(culpables, isEmpty, reason: 'El ViewModel no pinta: solo foundation');
  });

  test('las Views no llaman repositorios ni conocen implementaciones', () {
    final pages = dartEn('lib/presentacion').where((f) => f.path.endsWith('_page.dart'));
    final culpables = [
      for (final f in pages)
        if (importsDe(f).any((l) => l.contains('datos/'))) nombre(f),
    ];
    expect(culpables, isEmpty);
  });

  test('solo main.dart conoce las implementaciones memoria_ y nube_', () {
    final culpables = [
      for (final f in dartEn('lib/presentacion'))
        if (importsDe(f).any((l) => l.contains('memoria_') || l.contains('nube_') || l.contains('safelink_service'))) nombre(f),
    ];
    expect(culpables, isEmpty);
  });
}
