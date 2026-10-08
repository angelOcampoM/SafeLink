/// Validadores de formularios. Devuelven el mensaje de error o `null`,
/// así se conectan directo a `TextFormField(validator: Validators.email)`.
abstract final class Validators {
  static final _emailRe = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  static String? required(String? v, {String message = 'Este campo es obligatorio'}) =>
      (v == null || v.trim().isEmpty) ? message : null;

  static String? name(String? v) {
    final r = required(v, message: 'Escribe tu nombre');
    if (r != null) return r;
    return v!.trim().length < 3 ? 'Escribe tu nombre completo' : null;
  }

  static String? email(String? v) {
    final r = required(v, message: 'Escribe tu correo');
    if (r != null) return r;
    return _emailRe.hasMatch(v!.trim()) ? null : 'Correo no válido';
  }

  /// 10 dígitos (sección 4.1).
  static String? phone(String? v) {
    final r = required(v, message: 'Escribe tu teléfono');
    if (r != null) return r;
    return RegExp(r'^\d{10}$').hasMatch(v!.trim()) ? null : 'Debe tener 10 dígitos';
  }

  static String? password(String? v) {
    final r = required(v, message: 'Escribe tu contraseña');
    if (r != null) return r;
    if (v!.length < 8) return 'Mínimo 8 caracteres';
    if (!RegExp(r'\d').hasMatch(v)) return 'Incluye al menos un número';
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) =>
      (v) => v != original() ? 'Las contraseñas no coinciden' : null;
}
