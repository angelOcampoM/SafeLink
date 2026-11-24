// CAPA: PRESENTACIÓN — base de todos los ViewModels
// ChangeNotifier (Observer) que no avisa después de desecharse: una petición
// que termina cuando el usuario ya salió de la pantalla no truena la app.
// También traduce cualquier error a un mensaje en español.
// No importa material.dart: no pinta y no conoce widgets.

import 'package:flutter/foundation.dart';

import '../../dominio/errores.dart';

abstract class ViewModel extends ChangeNotifier {
  bool _desechado = false;
  bool get desechado => _desechado;

  @override
  void notifyListeners() {
    if (!_desechado) super.notifyListeners();
  }

  @override
  void dispose() {
    _desechado = true;
    super.dispose();
  }

  /// Mensaje listo para mostrar a partir de cualquier error.
  static String mensajeDe(Object e) =>
      e is ErrorDominio ? e.mensaje : 'Algo salió mal. Intenta de nuevo.';
}
