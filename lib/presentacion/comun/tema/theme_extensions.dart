// CAPA: PRESENTACIÓN — sistema de diseño (tema)
// Atajos de BuildContext (context.text, context.showSnack). No hace: no guarda estado.

import 'package:flutter/material.dart';

/// Atajos para no escribir `Theme.of(context).textTheme` en cada widget.
///
/// ```dart
/// Text('Hola', style: context.text.titleMedium)
/// ```
extension ThemeContext on BuildContext {
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;

  void showSnack(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
